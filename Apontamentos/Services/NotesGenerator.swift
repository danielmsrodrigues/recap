import Foundation
import PDFKit

/// O que o Claude recebe sobre uma aula.
struct ContextoAula: Sendable {
    var cadeira: String
    var titulo: String
    var data: Date
    var glossario: String
    var transcricao: Transcricao
    var slides: [SlideComImagem] = []
    /// PDF dos slides publicado pelo professor; quando existe, substitui as capturas do vídeo.
    var pdfProfessor: Data?
}

struct SlideComImagem: Sendable {
    var slide: Slide
    var jpeg: Data
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
        if c.pdfProfessor != nil || !c.slides.isEmpty {
            let numero = c.pdfProfessor != nil ? "o número da página do PDF (a primeira é 1)" : "o número do slide na lista acima"
            pedido += """


            Slides dentro dos apontamentos:
            - Para mostrar um slide, escreve numa linha própria `![Slide N — <título curto>](slide:N)`, em que N é \(numero).
            - Põe cada slide dado na aula logo a seguir ao título ou ao parágrafo do tema a que pertence. Cada slide entra uma vez só.
            - Deixa de fora capas, separadores de tema, índices, slides só com logótipos ou imagens decorativas, slides repetidos e slides que não foram dados nesta aula.
            - A imagem não substitui o texto: a matéria do slide continua escrita nos apontamentos, para se estudar e pesquisar sem a imagem.
            """
        }
        return materiais(c) + [.texto(pedido)]
    }

    /// Cabeçalho, glossário, slides (ou o PDF do professor) e transcrição: o que se sabe da aula.
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
        if let pdf = c.pdfProfessor {
            let paginas = PDFDocument(data: pdf)?.pageCount
            blocos.append(.texto("Slides publicados pelo professor (PDF\(paginas.map { ", \($0) páginas" } ?? "")). Usa-os como fonte principal para a notação, as fórmulas, os valores e a ordem dos temas; a transcrição diz o que foi explicado sobre eles. O PDF pode trazer slides de outras aulas: usa só os que foram dados nesta."))
            blocos.append(.documentoPDF(base64: pdf.base64EncodedString()))
        } else if !c.slides.isEmpty {
            blocos.append(.texto("Slides projetados na aula (\(c.slides.count)), cada um precedido do momento em que apareceu:"))
            for (i, s) in c.slides.enumerated() {
                var legenda = "[\(Timestamp.format(s.slide.inicio))] Slide \(i + 1)"
                if !s.slide.reaparicoes.isEmpty {
                    legenda += " (volta a aparecer em " + s.slide.reaparicoes.map { "[\(Timestamp.format($0))]" }.joined(separator: ", ") + ")"
                }
                blocos.append(.texto(legenda))
                blocos.append(.imagem(mediaType: "image/jpeg", base64: s.jpeg.base64EncodedString()))
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
        aoRecomecar: () -> Void,
        aoReceber: (String) -> Void,
        aoRepetir: (Int, Double, ErroClaude) -> Void
    ) async throws -> ResultadoApontamentos {
        try await gerar(sistema: prompt, conteudo: Self.conteudo(contexto),
                        aoRecomecar: aoRecomecar, aoReceber: aoReceber, aoRepetir: aoRepetir)
    }

    /// Qualquer pedido de texto (apontamentos, perguntas, exercícios, ligações), pelo motor escolhido.
    func gerar(
        sistema: String,
        conteudo: [BlocoConteudo],
        aoRecomecar: () -> Void,
        aoReceber: (String) -> Void,
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
        aoRecomecar: () -> Void,
        aoReceber: (String) -> Void,
        aoRepetir: (Int, Double, ErroClaude) -> Void
    ) async throws -> ResultadoApontamentos {
        let resposta = try await comRepeticao(aoRepetir: aoRepetir) {
            aoRecomecar()
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
