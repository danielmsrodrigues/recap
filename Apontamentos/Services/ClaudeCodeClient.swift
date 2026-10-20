import Foundation
import Synchronization

enum ErroClaudeCode: LocalizedError, Equatable {
    case naoEncontrado
    case semSessao(String)
    case limite(reiniciaEm: Date?)
    case modelo(String)
    case falhou(String)

    var errorDescription: String? {
        switch self {
        case .naoEncontrado:
            "Não encontrei o Claude Code (comando claude). Instala-o ou indica o caminho em Definições → Claude."
        case .semSessao(let detalhe):
            "O Claude Code não tem sessão iniciada. Abre o Terminal, corre claude e faz login com a tua conta. (\(detalhe))"
        case .limite(let data):
            if let data {
                "Atingiste o limite de utilização da tua subscrição. Volta a tentar depois das \(data.formatted(date: .omitted, time: .shortened))."
            } else {
                "Atingiste o limite de utilização da tua subscrição. Volta a tentar mais tarde."
            }
        case .modelo(let detalhe):
            "O Claude Code não aceitou o modelo. Verifica-o em Definições → Claude. (\(detalhe))"
        case .falhou(let detalhe):
            "O Claude Code falhou: \(detalhe)"
        }
    }
}

struct RespostaClaudeCode: Sendable {
    var resposta: RespostaFinal
    /// Quanto custaria na API; com subscrição não é cobrado.
    var custoEquivalente: Double?
    /// Fração usada da janela de 5 horas da subscrição.
    var uso5h: Double?
}

/// Gera texto com o Claude Code em modo não interativo (`claude -p`), usando a sessão
/// e a subscrição (Pro/Max) do utilizador em vez de uma chave API.
///
/// O pedido entra em `stream-json` com os mesmos blocos de conteúdo da API e a resposta
/// sai como eventos da API embrulhados em `stream_event`, lidos pelo `AcumuladorStream`.
struct ClaudeCodeClient: Sendable {
    var executavel: URL

    static let candidatos = [
        "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        "~/.local/bin/claude", "~/.claude/local/claude", "~/.npm-global/bin/claude",
    ]

    /// As apps abertas pelo Finder não herdam o PATH da shell, por isso procuramos nos sítios habituais.
    static func localizar(personalizado: String = "") -> URL? {
        let fm = FileManager.default
        let caminhos = personalizado.isEmpty ? candidatos : [personalizado]
        return caminhos
            .map { ($0 as NSString).expandingTildeInPath }
            .first { fm.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    @concurrent
    static func versao(_ executavel: URL) async -> String? {
        let p = Process()
        p.executableURL = executavel
        p.arguments = ["--version"]
        p.environment = ambiente()
        let saida = Pipe()
        p.standardOutput = saida
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: dados, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sem as variáveis de uma sessão do Claude Code nem chaves da API: assim usa o login do utilizador.
    static func ambiente() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { chave, _ in
            !(chave.hasPrefix("CLAUDE") || chave.hasPrefix("ANTHROPIC_"))
        }
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] = "64000"
        return env
    }

    /// Corre fora do fio principal: codificar o pedido (PDFs e imagens em base64, dezenas de MB) e ler o stream
    /// linha a linha bloqueava a interface. O texto chega a `aoReceber` em lotes, não token a token.
    @concurrent
    func gerar(
        sistema: String,
        conteudo: [BlocoConteudo],
        modelo: String,
        esforco: Esforco,
        aoRecomecar: @MainActor @Sendable () -> Void,
        aoReceber: @MainActor @Sendable (String) -> Void
    ) async throws -> RespostaClaudeCode {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "Recap-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let ficheiroSistema = pasta.appending(path: "sistema.md")
        try sistema.write(to: ficheiroSistema, atomically: true, encoding: .utf8)

        let processo = Process()
        processo.executableURL = executavel
        processo.currentDirectoryURL = pasta // pasta vazia: sem CLAUDE.md de nenhum projeto
        processo.environment = Self.ambiente()
        processo.arguments = [
            "-p",
            "--safe-mode", // sem CLAUDE.md, memória, skills, hooks nem MCP
            "--tools", "",
            "--no-session-persistence",
            "--model", modelo,
            "--effort", esforco.rawValue,
            "--system-prompt-file", ficheiroSistema.path,
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
        ]
        let entrada = Pipe(), saida = Pipe(), erros = Pipe()
        processo.standardInput = entrada
        processo.standardOutput = saida
        processo.standardError = erros

        let (fim, continuacaoFim) = AsyncStream<Int32>.makeStream()
        processo.terminationHandler = { p in
            continuacaoFim.yield(p.terminationStatus)
            continuacaoFim.finish()
        }
        let mensagem = try JSONEncoder().encode(EntradaUtilizador(message: .init(role: "user", content: conteudo)))
        do { try processo.run() } catch { throw ErroClaudeCode.falhou(error.localizedDescription) }
        let controlo = ControloProcesso(processo)

        // Escrever e ler em paralelo: a transcrição pode ser maior do que o buffer do pipe.
        let escrita = Task.detached {
            try? entrada.fileHandleForWriting.write(contentsOf: mensagem + Data("\n".utf8))
            try? entrada.fileHandleForWriting.close()
        }
        let leituraErros = Task.detached { erros.fileHandleForReading.readDataToEndOfFile() }

        var acumulador = AcumuladorStream()
        var mensagens = 0
        var resultado: [String: Any]?
        var uso5h: Double?
        var reinicio: Date?
        var lote = LoteDeTexto()

        try await withTaskCancellationHandler {
            for await linha in Self.linhas(saida.fileHandleForReading) {
                guard let dados = linha.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
                      let tipo = obj["type"] as? String
                else { continue }
                switch tipo {
                case "stream_event":
                    guard let evento = obj["event"] as? [String: Any] else { continue }
                    if evento["type"] as? String == "message_start" {
                        mensagens += 1
                        // Só esperamos uma mensagem; se o Claude Code repetir o pedido, recomeça o texto.
                        if mensagens > 1 { acumulador = AcumuladorStream(); lote = LoteDeTexto(); await aoRecomecar() }
                    }
                    let json = try JSONSerialization.data(withJSONObject: evento)
                    if let novo = try acumulador.processar(json), let pronto = lote.juntar(novo) { await aoReceber(pronto) }
                case "rate_limit_event":
                    let info = obj["rate_limit_info"] as? [String: Any]
                    let janela = (info?["unifiedWindows"] as? [String: Any])?["five_hour"] as? [String: Any]
                    uso5h = janela?["utilization"] as? Double ?? uso5h
                    if let r = (janela?["resetsAt"] ?? info?["resetsAt"]) as? Double { reinicio = Date(timeIntervalSince1970: r) }
                case "result":
                    resultado = obj
                default:
                    break
                }
            }
        } onCancel: {
            controlo.terminar()
        }
        if let resto = lote.esvaziar() { await aoReceber(resto) }
        _ = await escrita.value
        var estado: Int32 = 0
        for await s in fim { estado = s }
        try Task.checkCancellation()

        guard let resultado else {
            let stderr = String(data: await leituraErros.value, encoding: .utf8) ?? ""
            throw Self.erro(mensagem: stderr.isEmpty ? "terminou com o código \(estado)" : stderr, status: nil, reinicio: reinicio)
        }
        if resultado["is_error"] as? Bool == true {
            throw Self.erro(mensagem: resultado["result"] as? String ?? "erro desconhecido",
                            status: resultado["api_error_status"] as? Int, reinicio: reinicio)
        }
        return RespostaClaudeCode(
            resposta: try acumulador.resultado(),
            custoEquivalente: resultado["total_cost_usd"] as? Double,
            uso5h: uso5h
        )
    }

    /// As linhas da saída, lidas tão depressa quanto o Claude Code as escreve.
    ///
    /// O Claude Code (Node) sai logo a seguir à última linha, e o que ainda não coube no pipe perde-se: lendo
    /// byte a byte, ao ritmo de quem processa as linhas, o fim da resposta (a linha do resultado) ficava por ler
    /// e a geração falhava com "terminou com o código 0". Aqui uma thread esvazia o pipe para um buffer sem limite.
    static func linhas(_ fonte: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuacao in
            DispatchQueue.global(qos: .userInitiated).async {
                var pendente = Data()
                while true {
                    let bloco = fonte.availableData // bloqueia até haver dados; vazio no fim
                    if bloco.isEmpty { break }
                    pendente.append(bloco)
                    var inicio = pendente.startIndex
                    while let fim = pendente[inicio...].firstIndex(of: 0x0A) {
                        continuacao.yield(String(decoding: pendente[inicio..<fim], as: UTF8.self))
                        inicio = pendente.index(after: fim)
                    }
                    pendente = Data(pendente[inicio...])
                }
                if !pendente.isEmpty { continuacao.yield(String(decoding: pendente, as: UTF8.self)) }
                continuacao.finish()
            }
        }
    }

    static func erro(mensagem: String, status: Int?, reinicio: Date?) -> ErroClaudeCode {
        let m = mensagem.trimmingCharacters(in: .whitespacesAndNewlines)
        let minusculas = m.lowercased()
        if status == 401 || minusculas.contains("login") || minusculas.contains("not logged in") || minusculas.contains("invalid api key") {
            return .semSessao(m)
        }
        if status == 429 || minusculas.contains("usage limit") || minusculas.contains("rate limit") {
            return .limite(reiniciaEm: reinicio)
        }
        if status == 404 || minusculas.contains("selected model") { return .modelo(m) }
        return .falhou(String(m.suffix(500)))
    }
}

private struct EntradaUtilizador: Encodable {
    struct Mensagem: Encodable { var role: String; var content: [BlocoConteudo] }
    var type = "user"
    var message: Mensagem
}

/// O `Process` não é Sendable; isto só o deixa ser terminado a partir do handler de cancelamento.
private final class ControloProcesso: Sendable {
    private let processo: Mutex<Process?>
    init(_ p: Process) { processo = Mutex(p) }
    func terminar() { processo.withLock { $0?.terminate() } }
}
