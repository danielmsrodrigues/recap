import SwiftUI
import UIKit
import WebKit

/// Gera um PDF A4 paginado de Markdown (uma resposta, os apontamentos), com as fórmulas já renderizadas e em
/// tema claro. O mesmo `notes.html` do ecrã, num WKWebView fora do ecrã; no iOS quem pagina é o
/// `UIPrintPageRenderer` (no Mac é a impressão do AppKit, em `Apontamentos/Services/ExportadorPDF.swift`).
@MainActor
final class ExportadorPDF: NSObject, WKNavigationDelegate {
    private var carregou: CheckedContinuation<Void, any Error>?
    private let esquema = EsquemaAula()

    /// `pastaAula`: de onde vêm as imagens dos slides referidas no Markdown.
    static func exportar(markdown: String, pastaAula: URL? = nil, para destino: URL) async throws {
        try await ExportadorPDF().exportar(markdown: markdown, pastaAula: pastaAula, para: destino)
    }

    private func exportar(markdown: String, pastaAula: URL?, para destino: URL) async throws {
        guard let pasta = Bundle.main.url(forResource: "Web", withExtension: nil) else { throw CocoaError(.fileNoSuchFile) }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(esquema, forURLScheme: EsquemaAula.nome)
        // Largura de uma página A4 menos as margens, para o texto partir as linhas como no papel.
        // Fora de uma janela o WebKit não desenha nem acaba os scripts (a página nunca fica pronta): vai para a janela
        // da app, fora da área visível, como a janela fora do ecrã do Mac.
        let web = WKWebView(frame: CGRect(x: -10_000, y: 0, width: 523, height: 800), configuration: config)
        web.overrideUserInterfaceStyle = .light
        web.navigationDelegate = self
        let janela = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        janela?.addSubview(web)
        defer { web.removeFromSuperview() }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            carregou = c
            web.loadFileURL(pasta.appending(path: "notes.html"), allowingReadAccessTo: pasta)
        }
        let json = String(data: try JSONEncoder().encode(markdown), encoding: .utf8) ?? "\"\""
        let base = pastaAula.map { esquema.base(para: $0) } ?? ""
        _ = try await web.evaluateJavaScript("document.documentElement.classList.add('impressao'); renderMarkdown(\(json), false, '\(base)'); true")
        // Dar tempo aos esquemas, às fontes do KaTeX e às imagens dos slides antes de paginar.
        _ = try await web.callAsyncJavaScript(
            "await esquemasProntos(); await document.fonts.ready; await Promise.all([...document.images].map(i => i.decode().catch(() => {}))); return true",
            contentWorld: .page)

        let pagina = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 em pontos
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(pagina, forKey: "paperRect")
        renderer.setValue(pagina.inset(by: UIEdgeInsets(top: 40, left: 36, bottom: 40, right: 36)), forKey: "printableRect")
        let dados = UIGraphicsPDFRenderer(bounds: pagina).pdfData { contexto in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
            for i in 0..<renderer.numberOfPages {
                contexto.beginPage()
                renderer.drawPage(at: i, in: pagina)
            }
        }
        guard renderer.numberOfPages > 0 else {
            throw NSError(domain: "Recap", code: 10, userInfo: [NSLocalizedDescriptionKey: "Não foi possível criar o PDF."])
        }
        try dados.write(to: destino, options: .atomic)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        carregou?.resume()
        carregou = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        carregou?.resume(throwing: error)
        carregou = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        carregou?.resume(throwing: error)
        carregou = nil
    }

    /// O processo da página morreu a carregar: sem isto, a espera nunca acabava e o botão ficava "a criar o PDF".
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        carregou?.resume(throwing: NSError(domain: "Recap", code: 11, userInfo: [NSLocalizedDescriptionKey: "A página do PDF fechou-se a meio. Tenta outra vez."]))
        carregou = nil
    }
}

/// Um ficheiro criado na hora para partilhar (um `ShareLink` precisa do ficheiro antes de o botão aparecer).
struct FicheiroPartilhado: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A folha de partilha do iOS (guardar no Ficheiros, abrir no GoodNotes, AirDrop…).
struct FolhaPartilha: UIViewControllerRepresentable {
    let ficheiro: FicheiroPartilhado

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [ficheiro.url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
