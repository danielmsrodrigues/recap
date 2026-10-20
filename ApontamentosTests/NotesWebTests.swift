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
