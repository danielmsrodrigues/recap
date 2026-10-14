import Foundation

/// Executa as etapas de um job: áudio → transcrição → slides → apontamentos.
/// Transcrição e slides já guardados são reutilizados; só se refazem apagando `transcricao.json` ou `slides.json`.
@MainActor
final class PipelineRunner {
    private let library: Library
    private let definicoes: Definicoes
    private let transcriber = Transcriber()
    private let modelos = ModelStore()

    init(library: Library, definicoes: Definicoes) {
        self.library = library
        self.definicoes = definicoes
    }

    func executar(_ job: Job) async {
        do {
            let transcricao = try await obterTranscricao(job)
            _ = try await obterSlides(job)
            if job.gerarApontamentos {
                try await gerarApontamentos(job, transcricao: transcricao)
            }
            job.estado = .concluido
        } catch is CancellationError {
            job.cancelar()
        } catch {
            job.falhar(error.localizedDescription)
        }
        library.recarregar()
    }

    /// Liberta a memória do modelo do Whisper quando a fila esvazia.
    func filaVazia() {
        Task { await transcriber.libertar() }
    }

    // MARK: Transcrição

    private func obterTranscricao(_ job: Job) async throws -> Transcricao {
        if let existente = Disco.lerTranscricao(job.pastaAula) {
            job.saltar(.audio, detalhe: "Transcrição já existente")
            job.saltar(.transcricao, detalhe: "Reutilizada de transcricao.json")
            return existente
        }
        guard !job.soApontamentos else {
            throw NSError(domain: "Apontamentos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Esta aula ainda não tem transcrição."])
        }
        // 1. Áudio (do vídeo, ou captado em direto): só se valida; é lido por blocos durante a transcrição.
        let fonte: URL
        if let direto = job.audioDireto {
            fonte = direto
        } else if let video = job.video {
            fonte = video
        } else {
            throw NSError(domain: "Apontamentos", code: 2, userInfo: [NSLocalizedDescriptionKey: "O vídeo desta aula não foi encontrado. Localiza-o na aula e tenta de novo."])
        }
        job.iniciar(.audio)
        let duracaoAudio = try await VideoResolver.comAcesso(fonte) { try await AudioExtractor.duracao(fonte) }
        job.concluir(.audio, detalhe: Timestamp.duracao(duracaoAudio * job.velocidade)
                     + (job.audioDireto != nil ? " de aula, captado em direto" : " de áudio"))

        // 2. Modelo + transcrição
        let modelo = definicoes.modeloWhisper
        job.iniciar(.transcricao, detalhe: "A preparar o modelo \(modelo.nome)…")
        if !modelos.estaDescarregado(modelo) {
            job.atualizar(.transcricao, progresso: 0, detalhe: "A descarregar o modelo \(modelo.nome) (só na primeira vez)…")
            _ = try await modelos.descarregar(modelo) { p in
                Task { @MainActor in
                    job.atualizar(.transcricao, progresso: p,
                                  detalhe: "A descarregar o modelo \(modelo.nome)… \(p.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
            try Task.checkCancellation()
        }
        job.atualizar(.transcricao, progresso: nil, detalhe: "A carregar o modelo (na primeira vez pode demorar alguns minutos)…")
        try await transcriber.carregar(modelo, store: modelos)
        try Task.checkCancellation()
        job.atualizar(.transcricao, progresso: nil, detalhe: "A preparar a identificação de vozes (professor e alunos)…")
        await transcriber.carregarVozes(base: modelos.base)
        try Task.checkCancellation()

        job.atualizar(.transcricao, progresso: 0, detalhe: "A transcrever…")
        let glossario = library.cadeira(nome: library.aula(em: job.pastaAula)?.cadeira ?? "")?.meta.glossario ?? ""
        let inicio = Date.now
        let captados = try await VideoResolver.comAcesso(fonte) {
            try await transcriber.transcrever(ficheiro: fonte, duracao: duracaoAudio, glossario: glossario) { p in
                Task { @MainActor in job.atualizar(.transcricao, progresso: p) }
            }
        }
        // A 1,5× ou 2×, um segundo captado corresponde a 1,5 ou 2 segundos da aula.
        let segmentos = Self.ajustarVelocidade(captados, job.velocidade)
        let duracao = duracaoAudio * job.velocidade

        let transcricao = Transcricao(idioma: "es", modelo: modelo.rawValue, duracao: duracao, criadaEm: .now, segmentos: segmentos)
        try Disco.escreverTranscricao(transcricao, em: job.pastaAula)
        try library.atualizarMeta(em: job.pastaAula) {
            $0.duracao = duracao
            $0.modeloWhisper = modelo.rawValue
        }
        // Não fica nenhuma gravação: o áudio captado só existia para ser transcrito.
        if let direto = job.audioDireto { try? FileManager.default.removeItem(at: direto) }
        let demorou = Timestamp.duracao(Date.now.timeIntervalSince(inicio))
        var detalhe = "\(segmentos.count) segmentos em \(demorou)"
        if transcricao.temOradores {
            let alunos = segmentos.filter { $0.orador == .aluno }.count
            detalhe += alunos > 0 ? " · \(alunos) de alunos" : " · só a voz do professor"
        } else if let motivo = await transcriber.semVozes {
            detalhe += " · sem identificação de vozes (\(motivo))"
        }
        job.concluir(.transcricao, detalhe: detalhe)
        return transcricao
    }

    nonisolated static func ajustarVelocidade(_ segmentos: [Segmento], _ velocidade: Double) -> [Segmento] {
        guard velocidade != 1 else { return segmentos }
        return segmentos.map { Segmento(inicio: $0.inicio * velocidade, fim: $0.fim * velocidade, texto: $0.texto, orador: $0.orador) }
    }

    // MARK: Slides

    private func obterSlides(_ job: Job) async throws -> [Slide] {
        if let frames = job.framesDireto {
            let cadeira = library.cadeira(nome: library.aula(em: job.pastaAula)?.cadeira ?? "")
            var config = definicoes.configSlides(regiao: cadeira?.meta.regiaoIgnorar ?? .automatica)
            config.escalaTempo = job.velocidade
            config.recortarZonaAtiva = true
            job.iniciar(.slides, progresso: 0)
            let slides = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: frames), para: job.pastaAula) { p in
                Task { @MainActor in job.atualizar(.slides, progresso: p) }
            }
            let capturas = try await FontePasta(pasta: frames).tempos(intervalo: 0).count
            try? FileManager.default.removeItem(at: frames)
            job.concluir(.slides, detalhe: slides.isEmpty
                         ? (capturas == 0 ? "Nenhuma imagem da janela foi captada" : "Nenhum slide em \(capturas) capturas da janela")
                         : "\(slides.count) slides das capturas")
            return slides
        }
        if let existentes = Disco.lerSlides(job.pastaAula) {
            job.saltar(.slides, detalhe: existentes.isEmpty ? "Já analisado: sem slides" : "\(existentes.count) slides já extraídos")
            return existentes
        }
        guard let video = job.video else {
            let direto = job.audioDireto != nil || library.aula(em: job.pastaAula)?.meta.origem == "direto"
            job.saltar(.slides, detalhe: direto ? "Captado em direto: sem vídeo" : "Vídeo em falta")
            return []
        }
        let cadeira = library.cadeira(nome: library.aula(em: job.pastaAula)?.cadeira ?? "")
        let extrator = SlideExtractor(config: definicoes.configSlides(regiao: cadeira?.meta.regiaoIgnorar ?? .automatica))
        job.iniciar(.slides, progresso: 0)
        let slides = try await VideoResolver.comAcesso(video) {
            try await extrator.extrair(de: video, para: job.pastaAula) { p in
                Task { @MainActor in job.atualizar(.slides, progresso: p) }
            }
        }
        job.concluir(.slides, detalhe: slides.isEmpty ? "Nenhum slide encontrado (só câmara?)" : "\(slides.count) slides")
        return slides
    }

    // MARK: Apontamentos

    private func gerarApontamentos(_ job: Job, transcricao: Transcricao) async throws {
        let gerador: NotesGenerator
        do { gerador = try definicoes.gerador() } catch {
            job.iniciar(.apontamentos)
            throw error
        }
        guard let aula = library.aula(em: job.pastaAula) else {
            throw NSError(domain: "Apontamentos", code: 3, userInfo: [NSLocalizedDescriptionKey: "A pasta da aula desapareceu."])
        }

        // As páginas do PDF viram imagens antes do pedido, para os slides poderem entrar nos apontamentos.
        let paginasPDF = await SlidesNosApontamentos.garantirPaginasEmFundo(em: job.pastaAula)
        let contexto = ContextoAula.carregar(aula, library: library, transcricao: transcricao)
        let prompt = PromptStore.ler()

        job.iniciar(.apontamentos, detalhe: "A preparar o pedido…")
        var detalheBase = "A gerar com \(definicoes.modeloClaude) via \(definicoes.motor.nome)"
        if let estimativa = try? await gerador.estimar(contexto, prompt: prompt) {
            detalheBase += " · \(estimativa.tokens.formatted()) tokens de entrada (≈ \(TabelaPrecos.formatar(estimativa.custoEntrada)) + saída)"
        }
        try Task.checkCancellation()
        job.atualizar(.apontamentos, progresso: nil, detalhe: detalheBase + "…")

        let resultado = try await gerador.gerar(
            contexto,
            prompt: prompt,
            aoRecomecar: { job.textoEmCurso = "" },
            aoReceber: { job.textoEmCurso += $0 },
            aoRepetir: { tentativa, espera, erro in
                job.aviso = "\(erro.localizedDescription) Nova tentativa (\(tentativa + 1)) daqui a \(Int(espera)) s."
            }
        )
        job.aviso = nil

        var markdown = SlidesNosApontamentos.resolver(resultado.markdown, imagens: SlidesNosApontamentos.imagens(
            em: job.pastaAula, paginasPDF: paginasPDF, capturas: contexto.slides.map(\.slide)))
        var titulo: String?
        // Lido de novo: o utilizador pode ter mudado o título à mão enquanto o Claude escrevia.
        let tituloManual = (try? Disco.lerMeta(job.pastaAula))?.tituloManual ?? aula.meta.tituloManual
        if tituloManual != true, let tema = TituloAula.tema(markdown) {
            titulo = TituloAula.titulo(numero: library.numeroDaAula(aula), tema: tema)
            markdown = TituloAula.trocarCabecalho(markdown, por: titulo!)
        }

        try Disco.guardarCopiaApontamentos(em: job.pastaAula)
        try Disco.escreverApontamentos(markdown, em: job.pastaAula)
        try library.atualizarMeta(em: job.pastaAula) {
            $0.geracoes.append(resultado.geracao)
            if let titulo { $0.titulo = titulo }
        }

        let g = resultado.geracao
        var resumo = g.resumo
        if g.modeloServido != g.modeloPedido { resumo += " · servido por \(g.modeloServido) (fallback)" }
        job.concluir(.apontamentos, detalhe: resumo)
        if g.truncada {
            job.aviso = "Os apontamentos atingiram o limite de \(gerador.maxTokens.formatted()) tokens e ficaram incompletos."
        }
        job.textoEmCurso = ""
    }
}
