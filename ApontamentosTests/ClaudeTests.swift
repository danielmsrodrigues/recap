import Foundation
import Testing
@testable import Apontamentos

struct ClaudeTests {
    private func eventos(_ linhas: [String]) throws -> (AcumuladorStream, String) {
        var acc = AcumuladorStream()
        var recebido = ""
        for l in linhas { if let t = try acc.processar(Data(l.utf8)) { recebido += t } }
        return (acc, recebido)
    }

    /// O fim da resposta são linhas grandes (a mensagem inteira e o resultado), escritas mesmo antes de o processo
    /// sair; têm de chegar inteiras, mesmo a última sem quebra de linha.
    @Test func linhasDaSaidaChegamInteiras() async {
        let pipe = Pipe()
        let grande = String(repeating: "á", count: 300_000)
        let escritas = ["{\"type\":\"a\"}\n", "{\"type\":\"b\",\"t\":\"", grande, "\"}\n", "{\"type\":\"result\"}"]
        DispatchQueue.global().async {
            for e in escritas { pipe.fileHandleForWriting.write(Data(e.utf8)) }
            try? pipe.fileHandleForWriting.close()
        }
        var linhas: [String] = []
        for await l in ClaudeCodeClient.linhas(pipe.fileHandleForReading) { linhas.append(l) }
        #expect(linhas.count == 3)
        #expect(linhas.first == "{\"type\":\"a\"}")
        #expect(linhas.dropFirst().first == "{\"type\":\"b\",\"t\":\"\(grande)\"}")
        #expect(linhas.last == "{\"type\":\"result\"}")
    }

    @Test func juntaTextoEUso() throws {
        let (acc, recebido) = try eventos([
            #"{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":1200,"output_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"..."}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            ##"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"# Aula"}}"##,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" 1"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_details":null},"usage":{"output_tokens":800}}"#,
            #"{"type":"message_stop"}"#,
        ])
        #expect(recebido == "# Aula 1")
        let r = try acc.resultado()
        #expect(r.texto == "# Aula 1")
        #expect(r.uso.modelo == "claude-sonnet-5-5")
        #expect(r.uso.contagem == ContagemTokens(input: 1200, output: 800))
        #expect(!r.houveFallback)
    }

    @Test func recusaViraErro() throws {
        let (acc, _) = try eventos([
            #"{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10}}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"bio","explanation":"Declined."}},"usage":{"output_tokens":0}}"#,
        ])
        #expect(throws: ErroClaude.recusa(categoria: "bio", explicacao: "Declined.")) { try acc.resultado() }
    }

    @Test func fallbackUsaModeloServidoEIteracoes() throws {
        let (acc, _) = try eventos([
            #"{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":1000}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Olá"}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"claude-sonnet-5-5"},"to":{"model":"claude-sonnet-5"}}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":" mundo"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":300,"iterations":[{"type":"message","model":"claude-sonnet-5-5","input_tokens":1000,"output_tokens":100},{"type":"fallback_message","model":"claude-sonnet-5","input_tokens":1000,"output_tokens":200}]}}"#,
        ])
        let r = try acc.resultado()
        #expect(r.texto == "Olá mundo")
        #expect(r.houveFallback)
        #expect(r.uso.modelo == "claude-sonnet-5")
        #expect(r.uso.iteracoes.count == 2)
        // 2000 × $2 + 300 × $10 por milhão
        let custo = TabelaPrecos().custo(r.uso, modeloPedido: "claude-sonnet-5-5")
        #expect(abs(custo - 0.007) < 1e-9)
    }

    @Test func erroNoStream() throws {
        let (acc, _) = try eventos([#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])
        #expect(throws: ErroClaude.streamInterrompido(tipo: "overloaded_error", mensagem: "Overloaded")) { try acc.resultado() }
        #expect(ErroClaude.streamInterrompido(tipo: "overloaded_error", mensagem: nil).repetivel)
    }

    @Test func streamSemFimEInterrompido() throws {
        let (acc, _) = try eventos([
            #"{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"meio"}}"#,
        ])
        #expect(throws: ErroClaude.self) { try acc.resultado() }
    }

    @Test func precosPorPrefixoECusto() throws {
        let t = TabelaPrecos()
        #expect(t.preco(para: "claude-sonnet-5-5")?.entrada == 2)
        #expect(t.preco(para: "claude-sonnet-5-5-20260901")?.entrada == 2)
        #expect(t.preco(para: "claude-sonnet-5")?.leituraCache == 0.20)
        #expect(t.preco(para: "claude-opus-5-5")?.saida == 20)
        #expect(t.preco(para: "modelo-desconhecido") == nil)
        let uso = UsoTokens(modelo: "claude-sonnet-5-5", contagem: ContagemTokens(input: 100_000, output: 10_000, cacheRead: 0, cacheWrite: 0))
        #expect(abs(t.custo(uso, modeloPedido: "claude-sonnet-5-5") - 0.3) < 1e-9)
        let personalizada = TabelaPrecos(personalizados: ["claude-sonnet-5-5": Preco(entrada: 1, saida: 1, escritaCache: 1, leituraCache: 1)])
        #expect(personalizada.preco(para: "claude-sonnet-5-5")?.saida == 1)
    }

    @Test func repetiveis() {
        #expect(ErroClaude.http(status: 429, tipo: nil, mensagem: nil, retryAfter: 3).repetivel)
        #expect(ErroClaude.http(status: 529, tipo: nil, mensagem: nil, retryAfter: nil).repetivel)
        #expect(!ErroClaude.http(status: 401, tipo: nil, mensagem: nil, retryAfter: nil).repetivel)
        #expect(!ErroClaude.recusa(categoria: nil, explicacao: nil).repetivel)
        #expect(ErroClaude.rede("offline").repetivel)
    }

    @Test func pedidoTemFallbackEOutputConfigMasContagemNao() throws {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: [Segmento(inicio: 0, fim: 2, texto: "Hola")])
        let g = NotesGenerator(motor: .api(AnthropicClient(chave: "x")), modelo: "claude-sonnet-5-5", esforco: .high, precos: TabelaPrecos())
        let ctx = ContextoAula(cadeira: "Cálculo", titulo: "Límites", data: .now, glossario: "límite", transcricao: t)
        var p = g.pedido(ctx, prompt: "SISTEMA")
        p.stream = true
        let real = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        #expect(real["fallbacks"] as? String == "default")
        #expect(real["max_tokens"] as? Int == 64_000)
        #expect((real["output_config"] as? [String: String])?["effort"] == "high")
        #expect(real["system"] as? String == "SISTEMA")
        let texto = String(data: try JSONEncoder().encode(p), encoding: .utf8)!
        #expect(texto.contains("[00:00] Hola"))
        #expect(texto.contains("límite"))

        let contagem = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p.paraContagem)) as! [String: Any]
        #expect(Set(contagem.keys) == ["model", "system", "messages"])
    }
}

struct ClaudeCodeTests {
    @Test func errosDoClaudeCode() {
        #expect(ClaudeCodeClient.erro(mensagem: "Invalid API key · Please run /login", status: nil, reinicio: nil) == .semSessao("Invalid API key · Please run /login"))
        let reinicio = Date(timeIntervalSince1970: 1_791_491_400)
        #expect(ClaudeCodeClient.erro(mensagem: "x", status: 429, reinicio: reinicio) == .limite(reiniciaEm: reinicio))
        #expect(ClaudeCodeClient.erro(mensagem: "There's an issue with the selected model (y).", status: 404, reinicio: nil)
                == .modelo("There's an issue with the selected model (y)."))
        #expect(ClaudeCodeClient.erro(mensagem: "boom", status: 500, reinicio: nil) == .falhou("boom"))
    }

    @Test func ambienteSemVariaveisDeSessaoNemChaves() {
        let env = ClaudeCodeClient.ambiente()
        #expect(!env.keys.contains { $0.hasPrefix("ANTHROPIC_") || $0 == "CLAUDECODE" })
        #expect(env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"] == "64000")
        #expect(env["PATH"]?.hasPrefix("/opt/homebrew/bin") == true)
    }

    @Test func resumoDaGeracao() {
        var g = Geracao(data: .now, modeloPedido: "m", modeloServido: "m", inputTokens: 1000, outputTokens: 200,
                        cacheReadTokens: 0, cacheWriteTokens: 0, custoUSD: 0, truncada: false)
        #expect(g.resumo.hasPrefix("US$") || g.resumo.contains("$"))
        g.motor = "claude-code"
        g.usoSubscricao5h = 0.23
        #expect(g.resumo.hasPrefix("subscrição"))
        #expect(g.resumo.contains("23"))
    }
}

struct PDFProfessorTests {
    private static let json: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes
        return e
    }()

    @Test func pdfsECapturasNoPedido() throws {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: [Segmento(inicio: 0, fim: 2, texto: "Hola")])
        let slide = SlideComImagem(slide: Slide(ficheiro: "s.jpg", inicio: 0, fim: 2), jpeg: Data([1, 2, 3]))
        var ctx = ContextoAula(cadeira: "C", titulo: "T", data: .now, glossario: "", transcricao: t, slides: [slide])
        let semPDF = String(data: try Self.json.encode(NotesGenerator.conteudo(ctx)), encoding: .utf8)!
        #expect(semPDF.contains("\"image\""))
        #expect(!semPDF.contains("\"document\""))
        #expect(semPDF.contains("(slide:N)") && !semPDF.contains("slide:P/N"))

        ctx.pdfsProfessor = [
            PDFComDados(pdf: PDFProfessor(numero: 1, nome: "Tema 1.pdf"), dados: Data("%PDF-1.4".utf8)),
            PDFComDados(pdf: PDFProfessor(numero: 3), dados: Data("%PDF-1.4".utf8)),
        ]
        let blocos = NotesGenerator.conteudo(ctx)
        let comPDF = String(data: try Self.json.encode(blocos), encoding: .utf8)!
        #expect(comPDF.components(separatedBy: "\"document\"").count == 3)
        #expect(comPDF.contains("application/pdf"))
        // As capturas continuam, para se saber que páginas foram dadas, e podem ser citadas à parte.
        #expect(comPDF.contains("\"image\""))
        #expect(comPDF.contains("Captura 1"))
        #expect(comPDF.contains("PDF 1 \\\"Tema 1\\\":"))
        #expect(comPDF.contains("PDF 3:"))
        #expect(comPDF.contains("slide:P/N") && comPDF.contains("(slide:N)"))
        #expect(comPDF.contains("fica de fora por completo"))
    }
}
