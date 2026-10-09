import SwiftUI
import WebKit

/// Liga a barra de formatação nativa ao documento editável dentro do WKWebView.
@MainActor @Observable
final class ControladorNotas {
    struct Formato: Equatable { var negrito = false, italico = false, bloco = "p" }

    @ObservationIgnored fileprivate(set) weak var web: WKWebView?
    private(set) var editando = false
    var formato = Formato()
    /// Há alterações por gravar. Não é observado: muda a cada tecla e não deve redesenhar a interface.
    @ObservationIgnored var alterado = false
    /// Chamado 1,5 s depois da última alteração (gravação automática, como no Word).
    @ObservationIgnored var aoGravar: (() async -> Void)?
    @ObservationIgnored private var gravacao: Task<Void, Never>?

    func definirEdicao(_ ligar: Bool) {
        editando = ligar
        alterado = false
        gravacao?.cancel()
        web?.evaluateJavaScript("definirEdicao(\(ligar))")
    }

    fileprivate func registarAlteracao() {
        alterado = true
        gravacao?.cancel()
        gravacao = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.editando else { return }
            await self.aoGravar?()
        }
    }

    func comando(_ nome: String, _ valor: String? = nil) {
        let v = valor.map { "'\($0)'" } ?? "null"
        web?.evaluateJavaScript("comando('\(nome)', \(v))")
    }

    /// Volta a mostrar um Markdown (ao descartar alterações).
    func repor(_ markdown: String) {
        guard let json = try? JSONEncoder().encode(markdown), let literal = String(data: json, encoding: .utf8) else { return }
        web?.evaluateJavaScript("renderMarkdown(\(literal), false)")
    }

    func markdown() async throws -> String {
        guard let web else { throw CocoaError(.featureUnsupported) }
        return try await web.evaluateJavaScript("obterMarkdown()") as? String ?? ""
    }
}

/// Mostra Markdown com KaTeX num WKWebView. Os assets vêm da pasta `Web` do bundle (sem CDN).
struct NotesWebView: NSViewRepresentable {
    var markdown: String
    var emStreaming = false
    /// Para editar: sem controlador, a vista é só de leitura.
    var controlador: ControladorNotas?
    /// Chamado ao clicar num `[mm:ss]` (segundos).
    var aoClicarTimestamp: ((Double) -> Void)?
    /// Aspeto alternativo da página (classe no `<html>`), por exemplo "conversa" para o painel das perguntas.
    var modo: String?
    /// Texto a realçar e mostrar (vindo da pesquisa global): o primeiro destes que existir na página.
    var realcar: [String] = []

    func makeCoordinator() -> Coordenador { Coordenador() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        for nome in ["timestamp", "alterado", "formato"] {
            config.userContentController.add(context.coordinator, name: nome)
        }
        if let modo {
            config.userContentController.addUserScript(WKUserScript(
                source: "document.documentElement.classList.add('\(modo)')", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        controlador?.web = web
        if let pasta = Bundle.main.url(forResource: "Web", withExtension: nil) {
            web.loadFileURL(pasta.appending(path: "notes.html"), allowingReadAccessTo: pasta)
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.aoClicarTimestamp = aoClicarTimestamp
        context.coordinator.controlador = controlador
        context.coordinator.realcar(realcar)
        // Durante a edição o documento é o que está no ecrã; não o substituir.
        if controlador?.editando != true {
            context.coordinator.mostrar(markdown, emStreaming: emStreaming)
        }
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordenador) {
        for nome in ["timestamp", "alterado", "formato"] {
            web.configuration.userContentController.removeScriptMessageHandler(forName: nome)
        }
    }

    @MainActor
    final class Coordenador: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var aoClicarTimestamp: ((Double) -> Void)?
        weak var controlador: ControladorNotas?
        /// Textos pedidos para realçar, e os que já foram procurados na página.
        private var termosPedidos: [String] = []
        private var realcado: [String]?
        private var carregado = false
        private var mostrado: String?
        private var pendente: (String, Bool)?
        private var ultimoRender = Date.distantPast
        private var agendado = false

        func mostrar(_ markdown: String, emStreaming: Bool) {
            guard markdown != mostrado else { return }
            pendente = (markdown, emStreaming)
            guard carregado else { return }
            // Durante o streaming re-renderizar a cada pedaço seria pesado: no máximo 3 vezes por segundo.
            let espera = emStreaming ? max(0, 0.33 - Date.now.timeIntervalSince(ultimoRender)) : 0
            if espera == 0 {
                renderPendente()
            } else if !agendado {
                agendado = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(espera))
                    self?.agendado = false
                    self?.renderPendente()
                }
            }
        }

        private func renderPendente() {
            guard let (markdown, emStreaming) = pendente, let web else { return }
            pendente = nil
            mostrado = markdown
            ultimoRender = .now
            guard let json = try? JSONEncoder().encode(markdown), let literal = String(data: json, encoding: .utf8) else { return }
            web.evaluateJavaScript("renderMarkdown(\(literal), \(emStreaming))") { [weak self] _, _ in
                // O realce perde-se ao renderizar de novo.
                self?.realcado = nil
                self?.aplicarRealce()
            }
        }

        /// Procura o texto na página (como o ⌘F), realçando e mostrando a primeira ocorrência.
        func realcar(_ termos: [String]) {
            guard termos != termosPedidos else { return }
            termosPedidos = termos
            realcado = nil
            aplicarRealce()
        }

        private func aplicarRealce() {
            guard !termosPedidos.isEmpty, termosPedidos != realcado, carregado, pendente == nil, web != nil else { return }
            realcado = termosPedidos
            procurar(termosPedidos[...])
        }

        /// Tenta cada texto até um existir na página.
        private func procurar(_ termos: ArraySlice<String>) {
            guard let termo = termos.first, let web else { return }
            let config = WKFindConfiguration()
            config.caseSensitive = false
            config.wraps = true
            web.find(termo, configuration: config) { [weak self] r in
                if !r.matchFound { self?.procurar(termos.dropFirst()) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            carregado = true
            renderPendente()
        }

        /// Links externos abrem no browser; a página não navega.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
            return .cancel
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "alterado":
                controlador?.registarAlteracao()
            case "formato":
                guard let d = message.body as? [String: Any] else { return }
                let novo = ControladorNotas.Formato(negrito: d["negrito"] as? Bool ?? false,
                                                    italico: d["italico"] as? Bool ?? false,
                                                    bloco: d["bloco"] as? String ?? "p")
                if controlador?.formato != novo { controlador?.formato = novo }
            default:
                if let segundos = message.body as? Double { aoClicarTimestamp?(segundos) }
                else if let segundos = message.body as? Int { aoClicarTimestamp?(Double(segundos)) }
            }
        }
    }
}
