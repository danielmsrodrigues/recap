import Foundation
import Testing
import WebKit
@testable import Apontamentos

/// A página dos apontamentos (`notes.js`) num WKWebView, sem a app à volta.
@MainActor
struct NotesWebTests {
    /// Em streaming só o último bloco muda: os outros ficam no DOM (os `img` não voltam a carregar, o scroll não salta).
    @Test func renderPorBlocosMantemOsNosQueNaoMudaram() async throws {
        let pagina = try await Pagina.carregar()
        let md1 = "# Título\n\nUm $x^2$ e [01:05].\n\n> Resolução\n> a = b\n\nFim"
        try await pagina.render(md1)
        // Uma propriedade JS, não um atributo: um atributo mudava o nó e ele seria substituído, e bem.
        _ = try await pagina.web.evaluateJavaScript("document.getElementById('conteudo').children[0].marca = 'fica'; true")
        try await pagina.render(md1 + " mais texto")
        let r = try #require(try await pagina.web.evaluateJavaScript("""
            [document.getElementById('conteudo').children[0].marca,
             document.querySelectorAll('.math').length,
             document.querySelectorAll('a.ts').length,
             document.querySelectorAll('details.resolucao summary').length,
             document.getElementById('conteudo').lastElementChild.textContent]
            """) as? [Any])
        #expect(r[0] as? String == "fica")
        #expect(r[1] as? Int == 1)
        #expect(r[2] as? Int == 1)
        #expect(r[3] as? Int == 1)
        #expect((r[4] as? String)?.contains("mais texto") == true)

        // O documento volta a Markdown como antes.
        let md = try await pagina.web.evaluateJavaScript("obterMarkdown()") as? String
        #expect(md?.contains("$x^2$") == true)
        #expect(md?.contains("[01:05]") == true)
    }

    /// A resolução dos exercícios fica escondida em qualquer língua dos apontamentos.
    @Test func resolucaoEscondidaNoutrasLinguas() async throws {
        let pagina = try await Pagina.carregar()
        try await pagina.render("## Exercise 1\n\n> **Solution**\n> x = 2\n\n## Ejercicio 2\n\n> **Resolución**\n> y = 3")
        let n = try await pagina.web.evaluateJavaScript("document.querySelectorAll('details.resolucao').length") as? Int
        #expect(n == 2)
    }

    /// A mesma fórmula renderiza uma vez (cache do KaTeX) e dá o mesmo HTML nas duas.
    @Test func formulasRepetidasSaemIguais() async throws {
        let pagina = try await Pagina.carregar()
        try await pagina.render("$\\lambda_1$ e outra vez $\\lambda_1$ e $$\\int_0^1 x\\,dx$$")
        let r = try #require(try await pagina.web.evaluateJavaScript("""
            [...document.querySelectorAll('.math')].map(m => m.innerHTML)
            """) as? [String])
        #expect(r.count == 3)
        #expect(r[0] == r[1])
        #expect(r[2] != r[0])
    }

    /// Um bloco ```mermaid vira um desenho; um que o Mermaid não percebe fica como código; o último, a meio do
    /// streaming, espera pelo fim. O documento volta a Markdown com o bloco tal como era.
    @Test func esquemasDesenhados() async throws {
        let pagina = try await Pagina.carregar()
        let bom = "```mermaid\nflowchart TD\n  A[\"Empresa\"] --> B[\"Sector primário\"]\n```"
        let mau = "```mermaid\nisto não é um esquema\n```"
        try await pagina.render("Antes\n\n\(bom)\n\n\(mau)\n\nDepois", emStreaming: false)
        _ = try await pagina.web.callAsyncJavaScript("await esquemasProntos(); return true", contentWorld: .page)
        let r = try #require(try await pagina.web.evaluateJavaScript("""
            [document.querySelectorAll('.esquema.desenhado svg').length,
             document.querySelectorAll('.esquema.desenhado pre').length,
             document.querySelector('.esquema svg').textContent]
            """) as? [Any])
        #expect(r[0] as? Int == 1)
        #expect(r[1] as? Int == 1)
        #expect((r[2] as? String)?.contains("Sector primário") == true)
        let md = try await pagina.web.evaluateJavaScript("obterMarkdown()") as? String
        #expect(md?.contains("```mermaid\nflowchart TD") == true)

        // As cores dos ramos vêm da página: `:::c1` chega à caixa sem o Claude definir cores.
        try await pagina.render("```mermaid\nflowchart LR\n  A[\"Tema\"] --> B[\"Ramo\"]:::c1\n```", emStreaming: false)
        _ = try await pagina.web.callAsyncJavaScript("await esquemasProntos(); return true", contentWorld: .page)
        let cor = try await pagina.web.evaluateJavaScript("""
            getComputedStyle(document.querySelector('.esquema .node.c1 rect, .esquema .node.c1 path')).fill
            """) as? String
        #expect(cor != nil && cor != "none")

        try await pagina.render("Texto\n\n```mermaid\nflowchart TD\n  A --> ", emStreaming: true)
        let porDesenhar = try await pagina.web.evaluateJavaScript("document.querySelectorAll('.esquema:not(.desenhado)').length") as? Int
        #expect(porDesenhar == 1)
    }

    @MainActor
    final class Pagina: NSObject, WKNavigationDelegate {
        let web: WKWebView
        private var carregou: CheckedContinuation<Void, any Error>?

        private init(web: WKWebView) { self.web = web }

        static func carregar() async throws -> Pagina {
            let pasta = try #require(Bundle.main.url(forResource: "Web", withExtension: nil))
            let pagina = Pagina(web: WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 800)))
            pagina.web.navigationDelegate = pagina
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                pagina.carregou = c
                pagina.web.loadFileURL(pasta.appending(path: "notes.html"), allowingReadAccessTo: pasta)
            }
            return pagina
        }

        func render(_ markdown: String, emStreaming: Bool = true) async throws {
            let json = String(data: try JSONEncoder().encode(markdown), encoding: .utf8) ?? "\"\""
            _ = try await web.evaluateJavaScript("renderMarkdown(\(json), \(emStreaming), ''); true")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            carregou?.resume()
            carregou = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            carregou?.resume(throwing: error)
            carregou = nil
        }
    }
}
