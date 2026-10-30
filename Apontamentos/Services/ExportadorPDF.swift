import AppKit
import Synchronization
import WebKit

/// Gera um PDF A4 paginado dos apontamentos, com as fórmulas já renderizadas e em tema claro,
/// pronto para anotar no Freeform, GoodNotes, Pré-visualização…
///
/// Usa o mesmo `notes.html` do ecrã num WKWebView fora do ecrã e a impressão do macOS,
/// que é quem sabe partir as páginas sem cortar linhas a meio.
@MainActor
final class ExportadorPDF: NSObject, WKNavigationDelegate {
    private var janela: NSWindow?
    private var web: WKWebView?
    private var carregou: CheckedContinuation<Void, any Error>?
    /// O AppKit termina a impressão noutra thread; a continuação fica protegida por um Mutex.
    private nonisolated let imprimiu = Mutex<CheckedContinuation<Bool, Never>?>(nil)

    /// `pastaAula`: de onde vêm as imagens dos slides referidas nos apontamentos.
    static func exportar(markdown: String, pastaAula: URL? = nil, para destino: URL) async throws {
        try await ExportadorPDF().exportar(markdown: markdown, pastaAula: pastaAula, para: destino)
    }

    private let esquema = EsquemaAula()

    private func exportar(markdown: String, pastaAula: URL?, para destino: URL) async throws {
        guard let pasta = Bundle.main.url(forResource: "Web", withExtension: nil) else { throw CocoaError(.fileNoSuchFile) }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(esquema, forURLScheme: EsquemaAula.nome)
        // Largura de uma página A4 menos as margens, para o texto partir as linhas como no papel.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 523, height: 800), configuration: config)
        web.navigationDelegate = self
        let janela = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 523, height: 800),
                              styleMask: .borderless, backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false // é o ARC que a liberta; senão o close() liberta-a duas vezes
        janela.contentView = web
        janela.appearance = NSAppearance(named: .aqua)
        self.web = web
        self.janela = janela
        defer { janela.close() }

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

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842) // A4 em pontos
        info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 36; info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destino

        let operacao = web.printOperation(with: info)
        operacao.showsPrintPanel = false
        operacao.showsProgressPanel = false
        operacao.view?.frame = web.bounds
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            imprimiu.withLock { $0 = c }
            operacao.runModal(for: janela, delegate: self, didRun: #selector(terminou(_:sucesso:contexto:)), contextInfo: nil)
        }
        guard ok, FileManager.default.fileExists(atPath: destino.path) else {
            throw NSError(domain: "Recap", code: 10, userInfo: [NSLocalizedDescriptionKey: "Não foi possível criar o PDF."])
        }
        // Os slides vêm sem perdas do WebKit: em JPEG o PDF fica com cerca de um terço. Se falhar, fica o original.
        let pdf = destino
        try? await Task.detached { try ComprimirPDF.comprimir(pdf) }.value
    }

    @objc nonisolated private func terminou(_ operacao: NSPrintOperation, sucesso: Bool, contexto: UnsafeMutableRawPointer?) {
        imprimiu.withLock {
            $0?.resume(returning: sucesso)
            $0 = nil
        }
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
