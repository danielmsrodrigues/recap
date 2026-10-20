import Foundation
import PDFKit

/// O que o Claude recebe sobre uma aula.
struct ContextoAula: Sendable {
    var cadeira: String
    var titulo: String
    var data: Date
    var glossario: String
    var transcricao: Transcricao
    /// Capturas dos slides (do vídeo ou em direto). Com PDFs do professor, servem para saber que páginas foram dadas.
    var slides: [SlideComImagem] = []
    /// PDFs dos slides publicados pelo professor; quando existem, são a fonte principal dos slides.
    var pdfsProfessor: [PDFComDados] = []
    /// A ficha da cadeira (ver `FichaCadeira`): situa a aula no programa.
    var fichaCadeira: String?
}

struct PDFComDados: Sendable {
    var pdf: PDFProfessor
    var dados: Data
    /// Já em base64 e com as páginas contadas: o pedido monta-se sem trabalho pesado (isto faz-se ao carregar, fora do fio principal).
    var base64: String
    var paginas: Int?

    init(pdf: PDFProfessor, dados: Data) {
        self.pdf = pdf
        self.dados = dados
        base64 = dados.base64EncodedString()
        paginas = PDFDocument(data: dados)?.pageCount
    }
}

struct SlideComImagem: Sendable {
    var slide: Slide
    var jpeg: Data
    var base64: String

    init(slide: Slide, jpeg: Data) {
        self.slide = slide
        self.jpeg = jpeg
        base64 = jpeg.base64EncodedString()
    }
}

struct ResultadoApontamentos: Sendable {
    var markdown: String
    var geracao: Geracao
}

/// Por onde o pedido chega ao Claude.
enum Motor: Sendable {
    /// `claude -p` com a subscrição do utilizador (predefinido).
    case claudeCode(ClaudeCodeClient)
    /// API REST paga à parte.
    case api(AnthropicClient)
}

/// Monta o pedido ao Claude e devolve os apontamentos em Markdown.
struct NotesGenerator: Sendable {
    var motor: Motor
    var modelo: String
    var esforco: Esforco
    var precos: TabelaPrecos
    var maxTokens = 64_000

    func pedido(_ contexto: ContextoAula, prompt: String) -> PedidoMensagens {
        pedido(sistema: prompt, conteudo: Self.conteudo(contexto))
    }

    func pedido(sistema: String, conteudo: [BlocoConteudo]) -> PedidoMensagens {
        PedidoMensagens(
            model: modelo,
            maxTokens: maxTokens,
            system: sistema,
            messages: [MensagemAPI(role: "user", content: conteudo)],
            outputConfig: .init(effort: esforco.rawValue),
            fallbacks: "default"
        )
    }

    static func conteudo(_ c: ContextoAula) -> [BlocoConteudo] {
        var pedido = "Escreve os apontamentos desta aula seguindo as instruções."
        if c.fichaCadeira != nil {
            pedido += "\n\nA ficha da cadeira serve para situares esta aula no programa (o tema, a ordem, os nomes oficiais). Em \"Sobre a cadeira\" escreve só o que foi dito nesta aula, mesmo que a ficha já o tenha, e nada copiado da ficha."
        }
        if !c.pdfsProfessor.isEmpty || !c.slides.isEmpty {
            var marcas: [String] = []
            if !c.pdfsProfessor.isEmpty {
                marcas.append("`![Slide N — <título curto>](slide:P/N)` para a página N do PDF P (a primeira página de cada PDF é 1)")
            }
            if !c.slides.isEmpty {
                marcas.append("`![Slide N — <título curto>](slide:N)` para a \(c.pdfsProfessor.isEmpty ? "imagem" : "captura") N da lista acima")
            }
            pedido += "\n\nSlides dentro dos apontamentos:\n- Para mostrar um slide, escreve numa linha própria \(marcas.joined(separator: ", ou "))."
            if !c.pdfsProfessor.isEmpty && !c.slides.isEmpty {
                pedido += "\n- Prefere sempre a página do PDF. Usa uma captura só para o que foi projetado e não está em nenhum PDF."
            }
            pedido += """

            - Põe cada slide dado na aula logo a seguir ao título ou ao parágrafo do tema a que pertence. Cada slide entra uma vez só.
            - Deixa de fora capas, separadores de tema, índices, slides só com logótipos ou imagens decorativas, slides repetidos e slides que não foram dados nesta aula.
            - A imagem não substitui o texto: a matéria do slide continua escrita nos apontamentos, para se estudar e pesquisar sem a imagem.
            """
            if !c.pdfsProfessor.isEmpty {
                pedido += """

                - Em "Sobre a cadeira", diz de cada PDF que páginas foram dadas nesta aula e quais ficaram de fora (por exemplo "PDF 2 (Tema 3): páginas 4–18; 19–30 ainda por dar"), ou que o PDF não corresponde a esta aula e foi ignorado.
                """
            }
        }
        return materiais(c) + [.texto(pedido)]
    }

    /// Cabeçalho, glossário, PDFs do professor, capturas dos slides e transcrição: o que se sabe da aula.
    static func materiais(_ c: ContextoAula) -> [BlocoConteudo] {
        var cabecalho = """
        Cadeira: \(c.cadeira)
        Aula: \(c.titulo)
        Data: \(c.data.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_PT"))))
        Duração: \(Timestamp.duracao(c.transcricao.duracao))
        """
        let glossario = c.glossario.trimmingCharacters(in: .whitespacesAndNewlines)
        if !glossario.isEmpty {
            cabecalho += "\n\nGlossário da cadeira (termos que costumam aparecer; usa-os para corrigir a transcrição):\n\(glossario)"
        }
        var blocos: [BlocoConteudo] = [.texto(cabecalho)]
        if let ficha = c.fichaCadeira?.trimmingCharacters(in: .whitespacesAndNewlines), !ficha.isEmpty {
            blocos.append(.texto("Ficha da cadeira até agora (programa, avaliação, datas e avisos, do programa oficial e das aulas anteriores):\n\n<ficha>\n\(ficha)\n</ficha>"))
        }
        if !c.pdfsProfessor.isEmpty {
            let quantos = c.pdfsProfessor.count == 1 ? "1 PDF" : "\(c.pdfsProfessor.count) PDFs"
            let pelas = c.slides.isEmpty ? "pela transcrição" : "pela transcrição e pelas capturas do ecrã"
            blocos.append(.texto("""
            Slides publicados pelo professor (\(quantos)). Usa-os como fonte principal para a notação, as fórmulas, os valores e a ordem dos temas; a transcrição diz o que foi explicado sobre eles.
            Cada PDF pode ter sido dado só em parte nesta aula, ou nada (pode trazer slides de outras aulas). Antes de escrever, identifica \(pelas) que páginas de cada PDF o professor deu nesta aula, e usa só essas: as outras não entram, nem como matéria nem como imagem. Um PDF sem nenhuma página dada nesta aula fica de fora por completo.
            """))
            for p in c.pdfsProfessor {
                let nome = p.pdf.nome == nil ? "" : " \"\(p.pdf.titulo)\""
                blocos.append(.texto("PDF \(p.pdf.numero)\(nome)\(p.paginas.map { " (\($0) páginas)" } ?? ""):"))
                blocos.append(.documentoPDF(base64: p.base64))
            }
        }
        if !c.slides.isEmpty {
            blocos.append(.texto(c.pdfsProfessor.isEmpty
                ? "Slides projetados na aula (\(c.slides.count)), cada um precedido do momento em que apareceu:"
                : "Capturas do ecrã durante a aula (\(c.slides.count)), cada uma precedida do momento em que apareceu. Mostram que páginas dos PDFs foram projetadas e quando:"))
            for (i, s) in c.slides.enumerated() {
                var legenda = "[\(Timestamp.format(s.slide.inicio))] \(c.pdfsProfessor.isEmpty ? "Slide" : "Captura") \(i + 1)"
                if !s.slide.reaparicoes.isEmpty {
                    legenda += " (volta a aparecer em " + s.slide.reaparicoes.map { "[\(Timestamp.format($0))]" }.joined(separator: ", ") + ")"
                }
                blocos.append(.texto(legenda))
                blocos.append(.imagem(mediaType: "image/jpeg", base64: s.base64))
            }
        }
        let vozes = c.transcricao.temOradores
            ? "A identificação de voz marcou com (aluno) as linhas ditas por alunos; as restantes são do professor. Pode falhar."
            : "Esta transcrição não tem identificação de voz: deduz pelo contexto quem fala."
        let transcricao = """
        Transcrição automática da aula (espanhol), um segmento por linha com o seu timestamp. \(vozes)

        <transcricao>
        \(c.transcricao.textoComTimestamps)
        </transcricao>
        """
        blocos.append(.texto(transcricao))
        return blocos
    }

    /// Tokens de entrada e custo mínimo (só entrada) do pedido. Só com a API (o `count_tokens` precisa da chave).
    func estimar(_ contexto: ContextoAula, prompt: String) async throws -> (tokens: Int, custoEntrada: Double)? {
        guard case .api(let cliente) = motor else { return nil }
        let tokens = try await cliente.contarTokens(pedido(contexto, prompt: prompt))
        let preco = precos.preco(para: modelo)?.entrada ?? 0
        return (tokens, Double(tokens) * preco / 1_000_000)
    }

    func gerar(
        _ contexto: ContextoAula,
        prompt: String,
        aoRecomecar: @MainActor @Sendable () -> Void,
        aoReceber: @MainActor @Sendable (String) -> Void,
        aoRepetir: (Int, Double, ErroClaude) -> Void
    ) async throws -> ResultadoApontamentos {
        try await gerar(sistema: prompt, conteudo: Self.conteudo(contexto),
                        aoRecomecar: aoRecomecar, aoReceber: aoReceber, aoRepetir: aoRepetir)
    }

    /// Qualquer pedido de texto (apontamentos, perguntas, exercícios, ligações), pelo motor escolhido.
    /// `aoReceber` traz o texto em lotes, já no fio principal.
    func gerar(
        sistema: String,
        conteudo: [BlocoConteudo],
        aoRecomecar: @MainActor @Sendable () -> Void,
        aoReceber: @MainActor @Sendable (String) -> Void,
        aoRepetir: (Int, Double, ErroClaude) -> Void
    ) async throws -> ResultadoApontamentos {
        switch motor {
        case .api(let cliente):
            return try await gerarComAPI(cliente, pedido(sistema: sistema, conteudo: conteudo),
                                         aoRecomecar: aoRecomecar, aoReceber: aoReceber, aoRepetir: aoRepetir)
        case .claudeCode(let cc):
            let r = try await cc.gerar(sistema: sistema, conteudo: conteudo, modelo: modelo, esforco: esforco,
                                       aoRecomecar: aoRecomecar, aoReceber: aoReceber)
            let uso = r.resposta.uso
            let geracao = Geracao(
                data: .now,
                modeloPedido: modelo,
                modeloServido: uso.modelo ?? modelo,
                inputTokens: uso.contagem.input + uso.contagem.cacheRead + uso.contagem.cacheWrite,
                outputTokens: uso.contagem.output,
                cacheReadTokens: uso.contagem.cacheRead,
                cacheWriteTokens: uso.contagem.cacheWrite,
                custoUSD: 0,
                truncada: r.resposta.stopReason == "max_tokens",
                motor: "claude-code",
                custoEquivalenteAPI: r.custoEquivalente,
                usoSubscricao5h: r.uso5h
            )
            return ResultadoApontamentos(markdown: r.resposta.texto, geracao: geracao)
        }
    }

    private func gerarComAPI(
        _ cliente: AnthropicClient,
        _ p: PedidoMensagens,
        aoRecomecar: @MainActor @Sendable () -> Void,
        aoReceber: @MainActor @Sendable (String) -> Void,
        aoRepetir: (Int, Double, ErroClaude) -> Void
    ) async throws -> ResultadoApontamentos {
        let resposta = try await comRepeticao(aoRepetir: aoRepetir) {
            await aoRecomecar()
            return try await cliente.gerar(p, aoReceber: aoReceber)
        }
        let uso = resposta.uso
        let geracao = Geracao(
            data: .now,
            modeloPedido: modelo,
            modeloServido: uso.modelo ?? modelo,
            inputTokens: uso.iteracoes.isEmpty ? uso.contagem.input : uso.iteracoes.reduce(0) { $0 + $1.contagem.input },
            outputTokens: uso.iteracoes.isEmpty ? uso.contagem.output : uso.iteracoes.reduce(0) { $0 + $1.contagem.output },
            cacheReadTokens: uso.contagem.cacheRead,
            cacheWriteTokens: uso.contagem.cacheWrite,
            custoUSD: precos.custo(uso, modeloPedido: modelo),
            truncada: resposta.stopReason == "max_tokens"
        )
        return ResultadoApontamentos(markdown: resposta.texto, geracao: geracao)
    }
}
