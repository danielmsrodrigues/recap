import CoreGraphics
import Foundation
import Testing
@testable import Apontamentos

/// As procuras nas aulas anteriores ("Sai no exame" e o progresso da guia) quando o Claude falha.
/// O Claude Code é um script que escreve o mesmo stream-json e conta os pedidos, para não gastar a subscrição.
@MainActor
struct ProcuraAulasTests {
    private static let sessaoExpirada = "Failed to authenticate: OAuth session expired and could not be refreshed"
    private static let respostaExame = "[]"
    private static let respostaGuia = #"{"explicadas":[],"remetidas":[],"mencionadas":[]}"#

    private struct Cenario {
        var raiz: URL
        var library: Library
        var estudo: Estudo
        var cadeira: Cadeira
        var pastasDasAulas: [URL]

        /// Quantas vezes o `claude` foi chamado.
        var pedidos: Int {
            let texto = try? String(contentsOf: raiz.appending(path: "contador"), encoding: .utf8)
            return Int(texto?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        }
    }

    private static func resposta(_ texto: String) -> [String] {
        [
            #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10}}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(texto.replacingOccurrences(of: "\"", with: "\\\""))"}}}"#,
            #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"ok","total_cost_usd":0.001}"#,
        ]
    }

    /// O que o Claude Code escreve quando o pedido falha.
    private static func falha(_ mensagem: String, status: Int? = nil) -> [String] {
        [#"{"type":"result","subtype":"success","is_error":true,"result":"\#(mensagem)","api_error_status":\#(status.map(String.init) ?? "null"),"total_cost_usd":0}"#]
    }

    /// `pedidos`: o que o `claude` responde a cada pedido, por ordem; o último repete-se.
    private func cenario(aulas: Int = 3, pedidos: [[String]]) throws -> Cenario {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "procura-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let contador = raiz.appending(path: "contador").path
        let casos = pedidos.enumerated().map { i, linhas in
            let corpo = linhas.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n")
            return "\(i == pedidos.count - 1 ? "*" : String(i + 1))) \(corpo) ;;"
        }.joined(separator: "\n")
        let script = raiz.appending(path: "claude")
        try """
        #!/bin/sh
        cat > /dev/null
        n=$(( $(cat '\(contador)' 2>/dev/null || echo 0) + 1 ))
        echo $n > '\(contador)'
        case $n in
        \(casos)
        esac

        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "procura-\(UUID().uuidString)")!)
        definicoes.motor = .claudeCode
        definicoes.caminhoClaude = script.path
        let library = Library(raiz: raiz)
        let pastas = try (1...aulas).map { n in
            let pasta = try library.criarAula(cadeira: "Cálculo", titulo: "Aula \(n)", data: .now, video: nil)
            try Disco.escreverTranscricao(Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                                                      segmentos: [Segmento(inicio: 5, fim: 9, texto: "Los límites.")]), em: pasta)
            return pasta
        }
        library.recarregar()
        return Cenario(raiz: raiz, library: library, estudo: Estudo(library: library, definicoes: definicoes),
                       cadeira: try #require(library.cadeira(nome: "Cálculo")), pastasDasAulas: pastas)
    }

    /// A guia da cadeira: um PDF de uma página e o índice já guardado, para `GuiaEstudo.carregar` o encontrar.
    private func juntarGuia(a cadeira: Cadeira) throws {
        var caixa = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try #require(CGContext(FichaCadeira.urlPrograma(cadeira.pasta) as CFURL, mediaBox: &caixa, nil))
        ctx.beginPDFPage(nil)
        ctx.endPDFPage()
        ctx.closePDF()
        let hash = try #require(FichaCadeira.hashDoPrograma(cadeira.pasta))
        let indice = IndiceGuia(hash: hash, desvio: 0, seccoes: [SeccaoGuia(id: "1", titulo: "Límites", paginaInicio: 1, paginaFim: 1)])
        try Disco.escrever(indice, em: cadeira.pasta.appending(path: GuiaEstudo.ficheiro))
    }

    private func procurarExame(_ c: Cenario) async throws {
        c.estudo.procurarPistasExame(c.cadeira.aulas)
        for _ in 0..<80 where c.estudo.procuraExame != nil { try await Task.sleep(for: .milliseconds(250)) }
        #expect(c.estudo.procuraExame == nil)
    }

    private func procurarGuia(_ c: Cenario) async throws {
        c.estudo.procurarSeccoesGuia(c.cadeira)
        for _ in 0..<80 where c.estudo.procuraGuia[c.cadeira.pasta] != nil { try await Task.sleep(for: .milliseconds(250)) }
        #expect(c.estudo.procuraGuia[c.cadeira.pasta] == nil)
    }

    // MARK: Que erros param a procura

    @Test(arguments: [
        (ErroClaude.semChave, true),
        (.http(status: 401, tipo: nil, mensagem: nil, retryAfter: nil), true),
        (.http(status: 403, tipo: nil, mensagem: nil, retryAfter: nil), true),
        (.http(status: 404, tipo: nil, mensagem: nil, retryAfter: nil), true),
        (.http(status: 429, tipo: nil, mensagem: nil, retryAfter: nil), true),
        (.http(status: 400, tipo: "invalid_request_error", mensagem: "Your credit balance is too low", retryAfter: nil), true),
        // Tem a ver com esta aula, ou passa sozinho.
        (.http(status: 400, tipo: "invalid_request_error", mensagem: "Bad request", retryAfter: nil), false),
        (.http(status: 413, tipo: nil, mensagem: nil, retryAfter: nil), false),
        (.http(status: 500, tipo: nil, mensagem: nil, retryAfter: nil), false),
        (.http(status: 529, tipo: nil, mensagem: nil, retryAfter: nil), false),
        (.rede("sem ligação"), false),
        (.recusa(categoria: nil, explicacao: nil), false),
        (.streamInterrompido(tipo: nil, mensagem: nil), false),
        (.respostaVazia, false),
    ])
    func errosDaAPI(erro: ErroClaude, afeta: Bool) {
        #expect(erro.afetaOsProximosPedidos == afeta)
    }

    // MARK: Sai no exame

    @Test func exameSemSessaoParaNaPrimeiraAulaEDizComoResolver() async throws {
        let c = try cenario(pedidos: [Self.falha(Self.sessaoExpirada)])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try await procurarExame(c)
        #expect(c.pedidos == 1)
        let erro = try #require(c.estudo.erroExame)
        #expect(erro.contains(Self.sessaoExpirada))
        #expect(erro.contains("login"))
        #expect(!erro.contains("mais tarde"))
    }

    @Test func exameNoLimiteDaSubscricaoParaNaPrimeiraAula() async throws {
        let c = try cenario(pedidos: [Self.falha("Claude usage limit reached", status: 429)])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try await procurarExame(c)
        #expect(c.pedidos == 1)
        #expect(c.estudo.erroExame?.contains("limite de utilização") == true)
    }

    /// As aulas vistas antes de a sessão expirar ficam vistas: não se voltam a pedir.
    @Test func exameGuardaOQueViuAntesDeParar() async throws {
        let c = try cenario(pedidos: [Self.resposta(Self.respostaExame), Self.falha(Self.sessaoExpirada)])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try await procurarExame(c)
        #expect(c.pedidos == 2)
        #expect(c.pastasDasAulas.filter { Disco.lerPistasExame($0) != nil }.count == 1)
        #expect(c.estudo.erroExame?.contains("login") == true)
    }

    @Test func exameComUmaFalhaPontualVeAsOutrasAulas() async throws {
        let c = try cenario(pedidos: [
            Self.resposta(Self.respostaExame),
            Self.falha("boom", status: 500),
            Self.resposta(Self.respostaExame),
        ])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try await procurarExame(c)
        #expect(c.pedidos == 3)
        #expect(c.pastasDasAulas.filter { Disco.lerPistasExame($0) != nil }.count == 2)
        let erro = try #require(c.estudo.erroExame)
        #expect(erro.contains("1 aula ficou por ver"))
        #expect(erro.contains("mais tarde"))
        // Se a falha afinal se repetir, o motivo não fica escondido.
        #expect(erro.contains("boom"))
    }

    @Test func exameQueCorreBemNaoMostraErro() async throws {
        let c = try cenario(pedidos: [Self.resposta(Self.respostaExame)])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try await procurarExame(c)
        #expect(c.pedidos == 3)
        #expect(c.estudo.erroExame == nil)
    }

    // MARK: Progresso da guia

    @Test func guiaSemSessaoParaNaPrimeiraAulaEDizComoResolver() async throws {
        let c = try cenario(pedidos: [Self.falha(Self.sessaoExpirada)])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try juntarGuia(a: c.cadeira)
        try await procurarGuia(c)
        #expect(c.pedidos == 1)
        let erro = try #require(c.estudo.erroGuia[c.cadeira.pasta])
        #expect(erro.contains(Self.sessaoExpirada))
        #expect(erro.contains("login"))
        #expect(!erro.contains("mais tarde"))
    }

    @Test func guiaComUmaFalhaPontualVeAsOutrasAulas() async throws {
        let c = try cenario(pedidos: [
            Self.resposta(Self.respostaGuia),
            Self.falha("boom", status: 500),
            Self.resposta(Self.respostaGuia),
        ])
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        try juntarGuia(a: c.cadeira)
        try await procurarGuia(c)
        #expect(c.pedidos == 3)
        #expect(c.pastasDasAulas.filter { Disco.lerSeccoesGuia($0) != nil }.count == 2)
        let erro = try #require(c.estudo.erroGuia[c.cadeira.pasta])
        #expect(erro.contains("1 aula ficou por ver"))
        #expect(erro.contains("boom"))
    }
}
