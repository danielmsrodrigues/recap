import Foundation

/// Executa as etapas de um job: áudio e transcrição ao mesmo tempo que os slides, e no fim os apontamentos.
/// Transcrição e slides já guardados são reutilizados; só se refazem apagando `transcricao.json` ou `slides.json`.
@MainActor
final class PipelineRunner {
    private let library: Library
    private let definicoes: Definicoes
    private let fichas: Fichas
    private let estudo: Estudo
    private let transcriber = Transcriber()
    private let modelos = ModelStore()
    /// Libertação do modelo do Whisper agendada para quando a fila esvazia (cancelada se entrar outro job).
    private var libertacao: Task<Void, Never>?
    /// Quanto tempo o modelo fica em memória depois do último job: voltar a carregá-lo custa 5–20 s.
    static let esperaAteLibertar: Duration = .seconds(300)

    init(library: Library, definicoes: Definicoes, fichas: Fichas, estudo: Estudo) {
        self.library = library
        self.definicoes = definicoes
        self.fichas = fichas
        self.estudo = estudo
    }

    func executar(_ job: Job) async {
        libertacao?.cancel()
        libertacao = nil
        do {
            // A transcrição (Whisper) e os slides (Vision) não dependem um do outro: correm ao mesmo tempo.
            async let transcricaoEmCurso = obterTranscricao(job)
            async let slidesEmCurso = obterSlides(job)
            let transcricao = try await transcricaoEmCurso
            _ = try await slidesEmCurso
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

    /// Liberta a memória do modelo do Whisper algum tempo depois de a fila esvaziar.
    func filaVazia() {
        libertacao?.cancel()
        libertacao = Task { [transcriber] in
            try? await Task.sleep(for: Self.esperaAteLibertar)
            guard !Task.isCancelled else { return }
            await transcriber.libertar()
        }
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
        let cadeira = library.cadeira(nome: library.aula(em: job.pastaAula)?.cadeira ?? "")
        let glossario = cadeira?.meta.glossario ?? ""
        let idioma = definicoes.idioma(da: cadeira)
        let inicio = Date.now
        let captados = try await VideoResolver.comAcesso(fonte) {
            try await transcriber.transcrever(ficheiro: fonte, duracao: duracaoAudio, glossario: glossario, idioma: idioma) { p in
                Task { @MainActor in job.atualizar(.transcricao, progresso: p) }
            }
        }
        // A 1,5× ou 2×, um segundo captado corresponde a 1,5 ou 2 segundos da aula.
        let segmentos = Self.ajustarVelocidade(captados, job.velocidade)
        let duracao = duracaoAudio * job.velocidade

        let transcricao = Transcricao(idioma: idioma.rawValue, modelo: modelo.rawValue, duracao: duracao, criadaEm: .now, segmentos: segmentos)
        try Disco.escreverTranscricao(transcricao, em: job.pastaAula)
        try library.atualizarMeta(em: job.pastaAula) {
            $0.duracao = duracao
            $0.modeloWhisper = modelo.rawValue
        }
        // Não fica nenhuma gravação: o áudio captado só existia para ser transcrito.
        if let direto = job.audioDireto {
            try? FileManager.default.removeItem(at: direto)
            CaptacaoGuardada.de(audio: direto)?.apagarSeAcabada()
        }
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

    /// As capturas da janela, se ainda lá estiverem. Depois de extraídos os slides, a pasta é apagada: ao repetir um
    /// trabalho que falhou mais à frente, usam-se os slides já guardados (extrair de nada apagava-os).
    nonisolated static func capturasPorAnalisar(_ frames: URL?) -> URL? {
        guard let frames, FileManager.default.fileExists(atPath: frames.path) else { return nil }
        return frames
    }

    private func obterSlides(_ job: Job) async throws -> [Slide] {
        if let frames = Self.capturasPorAnalisar(job.framesDireto) {
            let cadeira = library.cadeira(nome: library.aula(em: job.pastaAula)?.cadeira ?? "")
            var config = definicoes.configSlides(regiao: cadeira?.meta.regiaoIgnorar ?? .automatica)
            config.escalaTempo = job.velocidade
            config.recortarZonaAtiva = true
            job.iniciar(.slides, progresso: 0)
            let slides = try await SlidesDireto.extrair(frames, com: SlideExtractor(config: config), para: job.pastaAula) { p in
                Task { @MainActor in job.atualizar(.slides, progresso: p) }
            }
            var capturas = 0
            for troco in FontePasta.trocos(frames) { capturas += try await FontePasta(pasta: troco).tempos(intervalo: 0).count }
            try? FileManager.default.removeItem(at: frames)
            if let audio = job.audioDireto { CaptacaoGuardada.de(audio: audio)?.apagarSeAcabada() }
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

        // As páginas dos PDFs viram imagens antes do pedido, para os slides poderem entrar nos apontamentos.
        let paginasPDF = await SlidesNosApontamentos.garantirPaginasEmFundo(em: job.pastaAula)
        let cadeira = library.cadeira(nome: aula.cadeira)
        var contexto = await ContextoAula.carregar(aula, cadeira: cadeira, transcricao: transcricao)
        let prompt = definicoes.promptApontamentos(idioma: IdiomaAula(codigo: transcricao.idioma))

        job.iniciar(.apontamentos, detalhe: "A preparar o pedido…")

        // A guía de estudio da cadeira: as secções que esta aula tocou entram no pedido. Se falhar, gera-se sem ela.
        var avisos: [String] = []
        var geracaoSelecao: Geracao?
        if let pasta = cadeira?.pasta, FichaCadeira.temPrograma(pasta) {
            if let (indice, paginas) = await Task.detached(operation: { GuiaEstudo.carregar(cadeira: pasta) }).value {
                job.atualizar(.apontamentos, progresso: nil, detalhe: "A escolher as secções da guia…")
                do {
                    let r = try await SeccoesDaAula.escolher(indice, transcricao: transcricao, gerador: gerador)
                    geracaoSelecao = r.geracao
                    // Fica na aula para o progresso do programa ("Sobre a cadeira").
                    try? Disco.escreverSeccoesGuia(SeccoesGuardadas(r.selecao, indice: indice), em: job.pastaAula)
                    contexto.guia = GuiaDaAula.montar(indice, paginas: paginas, selecao: r.selecao)
                    if let semEspaco = contexto.guia?.semEspaco, !semEspaco.isEmpty {
                        avisos.append("Secções da guia que não couberam no pedido (só com a referência): \(semEspaco.map(\.id).joined(separator: ", ")).")
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    avisos.append("Não foi possível escolher as secções da guia (\(error.localizedDescription)); os apontamentos saíram sem ela.")
                }
            } else {
                avisos.append("Não consegui ler o índice da guia; os apontamentos saíram sem ela.")
            }
        }
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
            paginasPDF: paginasPDF, capturas: contexto.slides.map(\.slide)))
        var titulo: String?
        // Lido de novo: o utilizador pode ter mudado o título à mão enquanto o Claude escrevia.
        let tituloManual = (try? Disco.lerMeta(job.pastaAula))?.tituloManual ?? aula.meta.tituloManual
        if tituloManual != true, let tema = TituloAula.tema(markdown) {
            titulo = TituloAula.titulo(numero: library.numeroDaAula(aula), tema: tema,
                                       aula: RotulosApontamentos.rotulo("Aula", definicoes.linguaApontamentos))
            markdown = TituloAula.trocarCabecalho(markdown, por: titulo!)
        }

        // O que a aula disse sobre a cadeira vai para a ficha da cadeira, não fica nos apontamentos.
        let separado = FichaCadeira.separar(markdown)
        var semSobre = separado.0
        let sobre = separado.1

        // Segundo passo: o que o professor deixou vago ganha uma 💡 na mesma linha. Se falhar, ficam os apontamentos sem elas.
        var geracao = resultado.geracao
        if let geracaoSelecao { geracao.somar(geracaoSelecao) }
        job.atualizar(.apontamentos, progresso: nil, detalhe: "A acrescentar explicações 💡…")
        var revisor = gerador
        revisor.esforco = .medium
        do {
            let r = try await ExplicacoesExtra.rever(semSobre, lingua: definicoes.linguaApontamentos, guia: contexto.guia, gerador: revisor)
            semSobre = r.markdown
            geracao.somar(r.geracao)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            avisos.append("Não foi possível acrescentar as explicações 💡: \(error.localizedDescription)")
        }

        // Terceiro passo: o que o professor disse que sai no exame (`exame.json`). Se falhar, a aula fica por procurar.
        job.atualizar(.apontamentos, progresso: nil, detalhe: "A procurar o que sai no exame…")
        var pistasExame: [PistasExame.Pista]?
        do {
            let r = try await PistasExame.procurar(transcricao, lingua: definicoes.linguaApontamentos, gerador: revisor)
            pistasExame = r.pistas
            geracao.somar(r.geracao)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            avisos.append("Não foi possível procurar o que sai no exame: \(error.localizedDescription)")
        }

        // As páginas da guia citadas têm de vir das secções enviadas; as outras ficam "por confirmar".
        if let guia = contexto.guia {
            let v = CitacoesGuia.verificar(semSobre, paginas: guia.paginasPermitidas, seccoes: guia.idsPermitidos)
            semSobre = v.markdown
            if v.invalidas > 0 {
                avisos.append("\(v.invalidas) páginas da guia citadas não foram enviadas ao Claude: estão marcadas «página por confirmar».")
            }
        }
        if resultado.geracao.truncada {
            avisos.append("Os apontamentos atingiram o limite de \(gerador.maxTokens.formatted()) tokens e ficaram incompletos.")
        }
        job.aviso = avisos.isEmpty ? nil : avisos.joined(separator: " ")

        try Task.checkCancellation()

        try Disco.guardarCopiaApontamentos(em: job.pastaAula)
        try Disco.escreverApontamentos(semSobre, em: job.pastaAula)
        try FichaCadeira.escreverExcerto(sobre, em: job.pastaAula)
        if let pistasExame { try Disco.escreverPistasExame(pistasExame, em: job.pastaAula) }
        try library.atualizarMeta(em: job.pastaAula) {
            $0.geracoes.append(geracao)
            if let titulo { $0.titulo = titulo }
        }

        let g = geracao
        var resumo = g.resumo
        if g.modeloServido != g.modeloPedido { resumo += " · servido por \(g.modeloServido) (fallback)" }
        job.concluir(.apontamentos, detalhe: resumo)
        if sobre != nil { fichas.atualizar(nomeCadeira: aula.cadeira) }
        // As ligações com as outras aulas da cadeira fazem-se logo, sem ter de as pedir.
        if let nova = library.aula(em: job.pastaAula) { estudo.aposApontamentos(nova) }
        job.textoEmCurso = ""
    }
}
