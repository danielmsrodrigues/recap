import Foundation

// Não há SDK oficial da Anthropic para Swift: a API REST é chamada diretamente.
// Referência: platform.claude.com/docs (Messages API, streaming, refusals-and-fallback).

// MARK: Pedido

enum BlocoConteudo: Encodable, Sendable {
    case texto(String)
    case imagem(mediaType: String, base64: String)
    case documentoPDF(base64: String)

    private enum Chaves: String, CodingKey { case type, text, source }
    private struct Fonte: Encodable { let type = "base64"; let media_type: String; let data: String }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Chaves.self)
        switch self {
        case .texto(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .imagem(let tipo, let dados):
            try c.encode("image", forKey: .type)
            try c.encode(Fonte(media_type: tipo, data: dados), forKey: .source)
        case .documentoPDF(let dados):
            try c.encode("document", forKey: .type)
            try c.encode(Fonte(media_type: "application/pdf", data: dados), forKey: .source)
        }
    }
}

struct MensagemAPI: Encodable, Sendable {
    var role: String
    var content: [BlocoConteudo]
}

struct PedidoMensagens: Encodable, Sendable {
    struct OutputConfig: Encodable, Sendable { var effort: String }

    var model: String
    var maxTokens: Int
    var system: String
    var messages: [MensagemAPI]
    var outputConfig: OutputConfig?
    /// `"default"`: se o modelo recusar, a API repete no modelo que a Anthropic recomenda para essa categoria.
    var fallbacks: String?
    var stream: Bool?

    /// O `count_tokens` só aceita os campos que formam o prompt.
    var paraContagem: PedidoMensagens {
        PedidoMensagens(model: model, maxTokens: maxTokens, system: system, messages: messages)
    }

    private enum CodingKeys: String, CodingKey {
        case model, maxTokens = "max_tokens", system, messages, outputConfig = "output_config", fallbacks, stream
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(system, forKey: .system)
        try c.encode(messages, forKey: .messages)
        // count_tokens rejeita max_tokens, stream e fallbacks; só os enviamos no pedido real.
        if stream != nil {
            try c.encode(maxTokens, forKey: .maxTokens)
            try c.encodeIfPresent(outputConfig, forKey: .outputConfig)
            try c.encodeIfPresent(fallbacks, forKey: .fallbacks)
            try c.encodeIfPresent(stream, forKey: .stream)
        }
    }
}

// MARK: Resposta

struct RespostaFinal: Sendable {
    var texto: String
    var stopReason: String?
    var uso: UsoTokens
    /// Houve fallback para outro modelo durante a resposta.
    var houveFallback: Bool
}

enum ErroClaude: LocalizedError, Equatable {
    case semChave
    case http(status: Int, tipo: String?, mensagem: String?, retryAfter: Double?)
    case rede(String)
    case recusa(categoria: String?, explicacao: String?)
    case streamInterrompido(tipo: String?, mensagem: String?)
    case respostaVazia

    var errorDescription: String? {
        switch self {
        case .semChave:
            return "Falta a chave API da Anthropic. Adiciona-a em Definições → API."
        case .http(let status, let tipo, let mensagem, _):
            let detalhe = mensagem.map { " (\($0))" } ?? ""
            switch status {
            case 401: return "A chave API foi rejeitada. Verifica-a em Definições → API."
            case 403: return "A chave API não tem permissão para este pedido\(detalhe)."
            case 404: return "Modelo não encontrado. Verifica o nome do modelo em Definições → API\(detalhe)."
            case 413: return "O pedido é demasiado grande para a API\(detalhe)."
            case 429: return "Limite de pedidos da API atingido\(detalhe)."
            case 529: return "Os servidores da Anthropic estão sobrecarregados. Tenta de novo daqui a pouco."
            case 500...: return "Erro no servidor da Anthropic (\(status))\(detalhe)."
            default:
                if tipo == "invalid_request_error", let mensagem, mensagem.localizedCaseInsensitiveContains("credit") {
                    return "Sem créditos na conta da Anthropic: \(mensagem)"
                }
                return "Pedido recusado pela API (\(status))\(detalhe)."
            }
        case .rede(let detalhe):
            return "Falha de rede: \(detalhe)"
        case .recusa(let categoria, let explicacao):
            let c = categoria.map { " [\($0)]" } ?? ""
            return "O modelo recusou o pedido\(c). \(explicacao ?? "")"
        case .streamInterrompido(let tipo, let mensagem):
            return "A resposta foi interrompida (\(tipo ?? "erro")): \(mensagem ?? "sem detalhe")"
        case .respostaVazia:
            return "A API devolveu uma resposta vazia."
        }
    }

    /// Erros transitórios que vale a pena repetir.
    var repetivel: Bool {
        switch self {
        case .http(let status, _, _, _): status == 408 || status == 409 || status == 429 || status >= 500
        case .rede: true
        case .streamInterrompido(let tipo, _): tipo == "overloaded_error" || tipo == "api_error" || tipo == nil
        default: false
        }
    }

    var esperaSugerida: Double? {
        if case .http(_, _, _, let retryAfter) = self { return retryAfter }
        return nil
    }
}

// MARK: Eventos SSE

/// Junta os eventos do stream numa resposta. Separado da rede para ser testável.
struct AcumuladorStream: Sendable {
    private(set) var texto = ""
    private(set) var stopReason: String?
    private(set) var stopDetails: (categoria: String?, explicacao: String?)?
    private(set) var uso = UsoTokens()
    private(set) var houveFallback = false
    private(set) var erro: ErroClaude?

    /// Processa a linha `data:` de um evento. Devolve o texto novo, se houver.
    mutating func processar(_ json: Data) throws -> String? {
        let ev = try Self.decoder.decode(Evento.self, from: json)
        switch ev.type {
        case "message_start":
            uso.modelo = ev.message?.model
            if let u = ev.message?.usage { aplicar(u) }
        case "content_block_start":
            if let bloco = ev.contentBlock {
                if bloco.type == "fallback" {
                    houveFallback = true
                    if let para = bloco.to?.model { uso.modelo = para }
                } else if bloco.type == "text", let t = bloco.text, !t.isEmpty {
                    texto += t
                    return t
                }
            }
        case "content_block_delta":
            if ev.delta?.type == "text_delta", let t = ev.delta?.text {
                texto += t
                return t
            }
        case "message_delta":
            if let r = ev.delta?.stopReason { stopReason = r }
            if let d = ev.delta?.stopDetails { stopDetails = (d.category, d.explanation) }
            if let u = ev.usage { aplicar(u) }
        case "error":
            erro = .streamInterrompido(tipo: ev.error?.type, mensagem: ev.error?.message)
        default:
            break // ping, content_block_stop, message_stop
        }
        return nil
    }

    func resultado() throws -> RespostaFinal {
        if let erro { throw erro }
        if stopReason == "refusal" {
            throw ErroClaude.recusa(categoria: stopDetails?.categoria, explicacao: stopDetails?.explicacao)
        }
        guard stopReason != nil else { throw ErroClaude.streamInterrompido(tipo: nil, mensagem: "o stream terminou sem message_delta") }
        guard !texto.isEmpty else { throw ErroClaude.respostaVazia }
        return RespostaFinal(texto: texto, stopReason: stopReason, uso: uso, houveFallback: houveFallback)
    }

    private mutating func aplicar(_ u: Evento.Usage) {
        if let v = u.inputTokens { uso.contagem.input = v }
        if let v = u.outputTokens { uso.contagem.output = v }
        if let v = u.cacheReadInputTokens { uso.contagem.cacheRead = v }
        if let v = u.cacheCreationInputTokens { uso.contagem.cacheWrite = v }
        if let its = u.iterations, !its.isEmpty {
            uso.iteracoes = its.map {
                UsoTokens.Iteracao(tipo: $0.type, modelo: $0.model, contagem: ContagemTokens(
                    input: $0.inputTokens ?? 0, output: $0.outputTokens ?? 0,
                    cacheRead: $0.cacheReadInputTokens ?? 0, cacheWrite: $0.cacheCreationInputTokens ?? 0))
            }
            if let servido = its.last(where: { $0.type == "fallback_message" })?.model {
                houveFallback = true
                uso.modelo = servido
            }
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private struct Evento: Decodable {
        struct Usage: Decodable {
            struct Iteracao: Decodable {
                var type: String
                var model: String?
                var inputTokens: Int?
                var outputTokens: Int?
                var cacheReadInputTokens: Int?
                var cacheCreationInputTokens: Int?
            }
            var inputTokens: Int?
            var outputTokens: Int?
            var cacheReadInputTokens: Int?
            var cacheCreationInputTokens: Int?
            var iterations: [Iteracao]?
        }
        struct Message: Decodable { var model: String?; var usage: Usage? }
        struct Modelo: Decodable { var model: String? }
        struct Bloco: Decodable { var type: String; var text: String?; var to: Modelo? }
        struct StopDetails: Decodable { var category: String?; var explanation: String? }
        struct Delta: Decodable { var type: String?; var text: String?; var stopReason: String?; var stopDetails: StopDetails? }
        struct Erro: Decodable { var type: String?; var message: String? }

        var type: String
        var message: Message?
        var contentBlock: Bloco?
        var delta: Delta?
        var usage: Usage?
        var error: Erro?
    }
}

/// Junta os pedaços do stream e entrega-os à interface no máximo ~12 vezes por segundo: cada entrega redesenha
/// a vista, e token a token eram dezenas por segundo.
struct LoteDeTexto {
    private var texto = ""
    private var ultimaEntrega = ContinuousClock.now
    static let intervalo: Duration = .milliseconds(80)

    /// O que há para entregar, se já passou tempo suficiente desde a última entrega.
    mutating func juntar(_ pedaco: String) -> String? {
        texto += pedaco
        guard ContinuousClock.now - ultimaEntrega >= Self.intervalo else { return nil }
        return esvaziar()
    }

    mutating func esvaziar() -> String? {
        guard !texto.isEmpty else { return nil }
        defer { texto = ""; ultimaEntrega = .now }
        return texto
    }
}

// MARK: Cliente

struct AnthropicClient: Sendable {
    var chave: String
    var base = URL(string: "https://api.anthropic.com/v1/")!
    var sessao: URLSession = .shared

    static let betaFallback = "server-side-fallback-2026-07-01"

    private func pedidoHTTP(_ caminho: String, corpo: Data, beta: String? = nil) -> URLRequest {
        var r = URLRequest(url: base.appending(path: caminho))
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        r.setValue(chave, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { r.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        r.httpBody = corpo
        return r
    }

    @concurrent
    private static func codificar(_ pedido: PedidoMensagens) async throws -> Data {
        try JSONEncoder().encode(pedido)
    }

    /// Tokens de entrada do pedido (gratuito). Serve para mostrar o custo antes de gerar.
    func contarTokens(_ pedido: PedidoMensagens) async throws -> Int {
        let corpo = try await Self.codificar(pedido.paraContagem)
        let (data, resposta) = try await executar(pedidoHTTP("messages/count_tokens", corpo: corpo))
        try Self.verificar(resposta, corpo: data)
        struct Contagem: Decodable { var input_tokens: Int }
        return try JSONDecoder().decode(Contagem.self, from: data).input_tokens
    }

    /// Faz o pedido em streaming e chama `aoReceber` com o texto à medida que chega, em lotes.
    /// Fora do fio principal: descodificar cada evento do stream na interface fazia-a engasgar.
    @concurrent
    func gerar(_ pedido: PedidoMensagens, aoReceber: @MainActor @Sendable (String) -> Void) async throws -> RespostaFinal {
        var pedido = pedido
        pedido.stream = true
        let corpo = try await Self.codificar(pedido)
        let http = pedidoHTTP("messages", corpo: corpo, beta: pedido.fallbacks != nil ? Self.betaFallback : nil)

        let bytes: URLSession.AsyncBytes
        let resposta: URLResponse
        do {
            (bytes, resposta) = try await sessao.bytes(for: http)
        } catch {
            throw Self.erroDeRede(error)
        }
        if let h = resposta as? HTTPURLResponse, h.statusCode != 200 {
            var dados = Data()
            for try await b in bytes { dados.append(b); if dados.count > 64_000 { break } }
            try Self.verificar(resposta, corpo: dados)
        }

        var acumulador = AcumuladorStream()
        var lote = LoteDeTexto()
        do {
            // `lines` salta as linhas vazias; cada evento da Anthropic tem uma única linha `data:`.
            for try await linha in bytes.lines where linha.hasPrefix("data:") {
                let json = Data(linha.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                if let novo = try acumulador.processar(json), let pronto = lote.juntar(novo) { await aoReceber(pronto) }
            }
            if let resto = lote.esvaziar() { await aoReceber(resto) }
        } catch is CancellationError {
            throw CancellationError()
        } catch let erro as DecodingError {
            throw ErroClaude.streamInterrompido(tipo: "json", mensagem: String(describing: erro))
        } catch {
            throw Self.erroDeRede(error)
        }
        return try acumulador.resultado()
    }

    private func executar(_ r: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await sessao.data(for: r) } catch { throw Self.erroDeRede(error) }
    }

    private static func erroDeRede(_ erro: any Error) -> any Error {
        if erro is CancellationError { return erro }
        if let u = erro as? URLError {
            if u.code == .cancelled { return CancellationError() }
            return ErroClaude.rede(u.localizedDescription)
        }
        return erro
    }

    static func verificar(_ resposta: URLResponse, corpo: Data) throws {
        guard let h = resposta as? HTTPURLResponse else { throw ErroClaude.rede("resposta inválida") }
        guard h.statusCode != 200 else { return }
        struct Corpo: Decodable { struct E: Decodable { var type: String?; var message: String? }; var error: E? }
        let e = (try? JSONDecoder().decode(Corpo.self, from: corpo))?.error
        let retry = h.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
        throw ErroClaude.http(status: h.statusCode, tipo: e?.type, mensagem: e?.message, retryAfter: retry)
    }
}

// MARK: Repetição

/// Repete erros transitórios com espera exponencial (2, 4, 8 s) ou a indicada em `retry-after`.
func comRepeticao<T>(
    tentativas: Int = 4,
    aoRepetir: (_ tentativa: Int, _ espera: Double, _ erro: ErroClaude) -> Void,
    _ operacao: () async throws -> T
) async throws -> T {
    var tentativa = 1
    while true {
        do {
            return try await operacao()
        } catch let erro as ErroClaude where erro.repetivel && tentativa < tentativas {
            let espera = min(60, erro.esperaSugerida ?? pow(2, Double(tentativa)))
            aoRepetir(tentativa, espera, erro)
            try await Task.sleep(for: .seconds(espera))
            tentativa += 1
        }
    }
}
