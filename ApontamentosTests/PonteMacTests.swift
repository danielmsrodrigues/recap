import Foundation
import Testing
@testable import Apontamentos

/// Os pedidos do iPad e do iPhone respondidos pelo Mac (`CaixaPedidos`, `PonteMac`).
/// O Claude Code é um script que escreve o mesmo stream-json, para não gastar a subscrição.
@MainActor
struct PonteMacTests {
    private struct Cenario {
        var raiz: URL
        var library: Library
        var definicoes: Definicoes
        var estudo: Estudo
        var ponte: PonteMac
        var aula: Aula
    }

    private func cenario(claude: String? = nil) throws -> Cenario {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "ponte-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "ponte-\(UUID().uuidString)")!)
        definicoes.motor = .claudeCode
        definicoes.caminhoClaude = claude ?? raiz.appending(path: "nao-existe").path
        let library = Library(raiz: raiz)
        let pasta = try library.criarAula(cadeira: "Finanzas", titulo: "Aula 1 · Juros", data: .now, video: nil)
        try Disco.escreverApontamentos("# Aula 1 · Juros\n\n## Resumo\nCapitalização composta.\n", em: pasta)
        try Disco.escreverTranscricao(Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                                                  segmentos: [Segmento(inicio: 5, fim: 9, texto: "El interés compuesto.")]), em: pasta)
        library.recarregar()
        let estudo = Estudo(library: library, definicoes: definicoes)
        return Cenario(raiz: raiz, library: library, definicoes: definicoes, estudo: estudo,
                       ponte: PonteMac(library: library, estudo: estudo, definicoes: definicoes),
                       aula: try #require(library.aula(em: pasta)))
    }

    /// Um `claude` que responde em dois pedaços, com uma pausa entre eles.
    private func claudeFalso(em pasta: URL) throws -> URL {
        let linhas = [
            #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10}}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Resposta "}}}"#,
            "SLEEP",
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"do Mac."}}}"#,
            #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}}"#,
            #"{"type":"result","is_error":false,"total_cost_usd":0.001}"#,
        ]
        let corpo = linhas.map { $0 == "SLEEP" ? "sleep 1" : "printf '%s\\n' '\($0)'" }.joined(separator: "\n")
        let script = pasta.appending(path: "claude")
        try "#!/bin/sh\ncat > /dev/null\n\(corpo)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func esperarEstado(_ id: UUID, raiz: URL, ate fases: Set<EstadoPedidoMac.Fase>) async throws -> EstadoPedidoMac {
        for _ in 0..<60 {
            if let e = CaixaPedidos.estado(id, raiz: raiz), fases.contains(e.fase) { return e }
            try await Task.sleep(for: .milliseconds(250))
        }
        return try #require(CaixaPedidos.estado(id, raiz: raiz))
    }

    @Test func soOsPedidosSemEstadoEstaoPorTratar() throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        let antigo = PedidoMac(tipo: .exercicios, aula: "x", criadoEm: .now.addingTimeInterval(-60))
        let novo = PedidoMac(tipo: .pergunta, aula: "x", pergunta: "?")
        let tratado = PedidoMac(tipo: .ligacoes, aula: "x")
        for p in [novo, antigo, tratado] { try CaixaPedidos.enviar(p, raiz: c.raiz) }
        try CaixaPedidos.escreverEstado(EstadoPedidoMac(fase: .feito), id: tratado.id, raiz: c.raiz)
        #expect(CaixaPedidos.porTratar(c.raiz).map(\.id) == [antigo.id, novo.id])
        // A pasta dos pedidos vive dentro de `_recap`, que não é uma cadeira.
        c.library.recarregar()
        #expect(c.library.cadeiras.map(\.nome) == ["Finanzas"])
    }

    @Test func soAceitaAulasDentroDaPasta() throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        let caminho = Estudo.caminhoRelativo(c.aula.pasta, raiz: c.raiz)
        #expect(CaixaPedidos.aula(PedidoMac(tipo: .pergunta, aula: caminho), em: c.library)?.pasta == c.aula.pasta)
        #expect(CaixaPedidos.aula(PedidoMac(tipo: .pergunta, aula: "../\(caminho)"), em: c.library) == nil)
        #expect(CaixaPedidos.aula(PedidoMac(tipo: .pergunta, aula: "Finanzas/não existe"), em: c.library) == nil)
    }

    @Test func limpaOsPedidosAntigos() throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        let velho = PedidoMac(tipo: .pergunta, aula: "x"), recente = PedidoMac(tipo: .pergunta, aula: "x")
        try CaixaPedidos.enviar(velho, raiz: c.raiz)
        try CaixaPedidos.enviar(recente, raiz: c.raiz)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * 86_400)],
                                              ofItemAtPath: CaixaPedidos.url(velho.id, raiz: c.raiz).path)
        CaixaPedidos.limparAntigos(c.raiz)
        #expect(CaixaPedidos.porTratar(c.raiz).map(\.id) == [recente.id])
    }

    @Test func respondeComOClaudeDoMac() async throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        c.definicoes.caminhoClaude = try claudeFalso(em: c.raiz).path
        let pedido = PedidoMac(tipo: .pergunta, aula: Estudo.caminhoRelativo(c.aula.pasta, raiz: c.raiz), pergunta: "O que é o juro composto?")
        try CaixaPedidos.enviar(pedido, raiz: c.raiz)

        c.ponte.verificar()
        let parcial = try await esperarEstado(pedido.id, raiz: c.raiz, ate: [.aGerar, .feito, .erro])
        #expect(parcial.fase != .erro, "\(parcial.erro ?? "")")
        let fim = try await esperarEstado(pedido.id, raiz: c.raiz, ate: [.feito, .erro])
        #expect(fim.fase == .feito, "\(fim.erro ?? "")")
        #expect(fim.texto == "Resposta do Mac.")
        let perguntas = Disco.lerPerguntas(c.aula.pasta)
        #expect(perguntas.map(\.pergunta) == ["O que é o juro composto?"])
        #expect(perguntas.first?.resposta == "Resposta do Mac.")
        // Já tem estado: não volta a ser tratado.
        #expect(CaixaPedidos.porTratar(c.raiz).isEmpty)
    }

    @Test func avisaQuandoOMacNaoConsegueResponder() async throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        let semClaude = PedidoMac(tipo: .exercicios, aula: Estudo.caminhoRelativo(c.aula.pasta, raiz: c.raiz))
        let foraDaPasta = PedidoMac(tipo: .pergunta, aula: "../fora", pergunta: "?")
        try CaixaPedidos.enviar(semClaude, raiz: c.raiz)
        try CaixaPedidos.enviar(foraDaPasta, raiz: c.raiz)
        c.ponte.verificar()
        let e1 = try await esperarEstado(semClaude.id, raiz: c.raiz, ate: [.erro, .feito])
        #expect(e1.fase == .erro)
        #expect(e1.erro?.contains("Claude Code") == true)
        let e2 = try await esperarEstado(foraDaPasta.id, raiz: c.raiz, ate: [.erro])
        #expect(e2.erro?.contains("não está no Mac") == true)
    }

    @Test func desligadaNaoRespondeANada() throws {
        let c = try cenario()
        defer { try? FileManager.default.removeItem(at: c.raiz) }
        c.definicoes.responderPedidos = false
        let pedido = PedidoMac(tipo: .exercicios, aula: Estudo.caminhoRelativo(c.aula.pasta, raiz: c.raiz))
        try CaixaPedidos.enviar(pedido, raiz: c.raiz)
        c.ponte.verificar()
        #expect(CaixaPedidos.estado(pedido.id, raiz: c.raiz) == nil)
    }
}
