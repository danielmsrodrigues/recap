import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Liga a barra de formatação nativa ao documento editável dentro do WKWebView.
@MainActor @Observable
final class ControladorNotas {
    struct Formato: Equatable { var negrito = false, italico = false, bloco = "p" }
    /// Ocorrências da procura na página (⌘F): quantas há e qual está selecionada (-1 sem nenhuma).
    struct Procura: Equatable { var total = 0, atual = -1 }

    @ObservationIgnored fileprivate(set) weak var web: WKWebView?
    private(set) var editando = false
    var formato = Formato()
    /// Há alterações por gravar. Não é observado: muda a cada tecla e não deve redesenhar a interface.
    @ObservationIgnored var alterado = false
    /// Chamado 1,5 s depois da última alteração (gravação automática, como no Word).
    @ObservationIgnored var aoGravar: (() async -> Void)?
    @ObservationIgnored private var gravacao: Task<Void, Never>?
    var procura = Procura()
    /// O texto procurado, para a página o voltar a procurar se ainda não estava carregada quando se pediu.
    @ObservationIgnored fileprivate(set) var termoProcura = ""

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

    /// Procura o texto na página, realçando todas as ocorrências e mostrando a primeira a partir do que está no ecrã.
    func procurar(_ termo: String) {
        termoProcura = termo
        guard let json = try? JSONEncoder().encode(termo), let literal = String(data: json, encoding: .utf8) else { return }
        web?.evaluateJavaScript("procurarTexto(\(literal), false)")
    }

    /// A ocorrência seguinte (1) ou anterior (-1), dando a volta.
    func andarProcura(_ passo: Int) {
        web?.evaluateJavaScript("andarProcura(\(passo))")
    }

    func limparProcura() {
        termoProcura = ""
        procura = Procura()
        web?.evaluateJavaScript("limparProcura()")
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
    /// Pasta da aula, de onde vêm as imagens dos slides referidas nos apontamentos.
    var pastaAula: URL?
    /// Chamado com o texto selecionado (em Markdown) ao carregar em "Perguntar" junto à seleção ou no menu de contexto.
    /// Sem ele, o botão não aparece. Decide-se ao criar a vista.
    var aoPerguntar: ((String) -> Void)?
    /// Chamado ao clicar num link para uma secção (`[Título](#ancora)`).
    var aoClicarSeccao: ((LigacaoSeccao) -> Void)?
    /// Título a mostrar e realçar por instantes (cada pedido novo, com outro id, volta a fazê-lo).
    var irParaSeccao: PedidoSeccao?
    /// Chamado com o índice da resposta ao carregar no seu "Guardar PDF…" (respostas pedidas em PDF, na conversa).
    var aoGuardarPDF: ((Int) -> Void)?

    private static let mensagens = ["timestamp", "alterado", "formato", "selecao", "perguntar", "procura", "seccao", "guardarPDF"]

    func makeCoordinator() -> Coordenador { Coordenador() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        for nome in Self.mensagens {
            config.userContentController.add(context.coordinator, name: nome)
        }
        if aoPerguntar != nil {
            config.userContentController.addUserScript(WKUserScript(
                source: "window.podePerguntar = true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if let modo {
            config.userContentController.addUserScript(WKUserScript(
                source: "document.documentElement.classList.add('\(modo)')", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        #if DEBUG
        // `APONTAMENTOS_JS_<MODO>="<js>"` (ex.: `APONTAMENTOS_JS_CONVERSA`): corre esse JS na página, para testar cliques sem rato.
        if let js = ProcessInfo.processInfo.environment["APONTAMENTOS_JS_\((modo ?? "notas").uppercased())"] {
            config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        #endif
        config.setURLSchemeHandler(context.coordinator.esquema, forURLScheme: EsquemaAula.nome)
        let web = WebNotas(frame: .zero, configuration: config)
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
        context.coordinator.aoPerguntar = aoPerguntar
        context.coordinator.aoClicarSeccao = aoClicarSeccao
        context.coordinator.aoGuardarPDF = aoGuardarPDF
        context.coordinator.controlador = controlador
        context.coordinator.realcar(realcar)
        context.coordinator.pastaAula = pastaAula
        // Durante a edição o documento é o que está no ecrã; não o substituir.
        if controlador?.editando != true {
            context.coordinator.mostrar(markdown, emStreaming: emStreaming)
        }
        context.coordinator.irPara(irParaSeccao)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordenador) {
        for nome in mensagens {
            web.configuration.userContentController.removeScriptMessageHandler(forName: nome)
        }
    }

    @MainActor
    final class Coordenador: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var aoClicarTimestamp: ((Double) -> Void)?
        var aoPerguntar: ((String) -> Void)?
        var aoClicarSeccao: ((LigacaoSeccao) -> Void)?
        var aoGuardarPDF: ((Int) -> Void)?
        weak var controlador: ControladorNotas?
        let esquema = EsquemaAula()
        var pastaAula: URL?
        /// Textos pedidos para realçar, e os que já foram procurados na página.
        private var termosPedidos: [String] = []
        private var realcado: [String]?
        private var carregado = false
        private var mostrado: String?
        private var pendente: (String, Bool)?
        private var ultimoRender = Date.distantPast
        private var agendado = false
        /// Título pedido ainda por mostrar (espera que a página esteja renderizada) e o último já mostrado.
        private var seccaoPedida: PedidoSeccao?
        private var seccaoFeita: UUID?

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
            guard let json = try? JSONEncoder().encode(markdown), let literal = String(data: json, encoding: .utf8) else { return }
            let base = pastaAula.map { esquema.base(para: $0) } ?? ""
            let primeiro = ultimoRender == .distantPast
            ultimoRender = .now
            web.evaluateJavaScript("renderMarkdown(\(literal), \(emStreaming), '\(base)')") { [weak self] _, _ in
                // A procura pedida antes de a página carregar (a página refaz sozinha as seguintes).
                if primeiro, let termo = self?.controlador?.termoProcura, !termo.isEmpty { self?.controlador?.procurar(termo) }
                // O realce perde-se ao renderizar de novo.
                self?.realcado = nil
                self?.aplicarRealce()
                self?.aplicarSeccao()
            }
        }

        /// Procura o texto na página (como o ⌘F), realçando e mostrando a primeira ocorrência.
        func realcar(_ termos: [String]) {
            guard termos != termosPedidos else { return }
            termosPedidos = termos
            realcado = nil
            aplicarRealce()
        }

        func irPara(_ pedido: PedidoSeccao?) {
            guard let pedido, pedido.id != seccaoFeita, pedido != seccaoPedida else { return }
            seccaoPedida = pedido
            aplicarSeccao()
        }

        private func aplicarSeccao() {
            guard let pedido = seccaoPedida, carregado, pendente == nil, let web else { return }
            seccaoPedida = nil
            seccaoFeita = pedido.id
            web.evaluateJavaScript("irParaSeccao(\(pedido.indice))")
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
            case "selecao":
                (web as? WebNotas)?.haSelecao = message.body as? Bool ?? false
            case "perguntar":
                if let texto = message.body as? String { aoPerguntar?(texto) }
            case "procura":
                guard let d = message.body as? [String: Any] else { return }
                let r = ControladorNotas.Procura(total: (d["total"] as? NSNumber)?.intValue ?? 0,
                                                 atual: (d["atual"] as? NSNumber)?.intValue ?? -1)
                if controlador?.procura != r { controlador?.procura = r }
            case "seccao":
                guard let d = message.body as? [String: Any], let ancora = d["ancora"] as? String else { return }
                aoClicarSeccao?(LigacaoSeccao(ancora: ancora, texto: d["texto"] as? String ?? ""))
            case "guardarPDF":
                if let i = (message.body as? NSNumber)?.intValue { aoGuardarPDF?(i) }
            default:
                if let segundos = message.body as? Double { aoClicarTimestamp?(segundos) }
                else if let segundos = message.body as? Int { aoClicarTimestamp?(Double(segundos)) }
            }
        }
    }
}

/// O WKWebView das notas, com "Perguntar sobre a seleção" no menu de contexto quando há texto selecionado.
final class WebNotas: WKWebView {
    /// A página diz quando há texto selecionado sobre o qual se pode perguntar (mensagem "selecao").
    var haSelecao = false

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard haSelecao else { return }
        let item = NSMenuItem(title: "Perguntar sobre a seleção", action: #selector(perguntarSelecao), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func perguntarSelecao() {
        evaluateJavaScript("perguntarSelecao()")
    }
}

/// Serve ao WKWebView as imagens da pasta de uma aula: `recap-aula://<id>/slides-pdf/pagina-01.jpg`.
/// Cada pasta tem o seu id, para o WebKit não mostrar de cache a imagem de outra aula com o mesmo nome.
@MainActor
final class EsquemaAula: NSObject, WKURLSchemeHandler {
    static let nome = "recap-aula"
    private var pastas: [String: URL] = [:]

    /// Início dos URLs das imagens desta pasta (termina em `/`).
    func base(para pasta: URL) -> String {
        let id = pastas.first { $0.value.mesmoCaminho(pasta) }?.key ?? {
            let novo = UUID().uuidString.lowercased()
            pastas[novo] = pasta
            return novo
        }()
        return "\(Self.nome)://\(id)/"
    }

    func webView(_ webView: WKWebView, start tarefa: any WKURLSchemeTask) {
        guard let url = tarefa.request.url, let id = url.host(), let pasta = pastas[id]?.standardizedFileURL else {
            tarefa.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let ficheiro = pasta.appending(path: String(url.path(percentEncoded: false).drop { $0 == "/" })).standardizedFileURL
        // Só ficheiros dentro da pasta da aula.
        guard ficheiro.path.hasPrefix(pasta.path + "/"), let dados = try? Data(contentsOf: ficheiro) else {
            tarefa.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let tipo = UTType(filenameExtension: ficheiro.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        tarefa.didReceive(URLResponse(url: url, mimeType: tipo, expectedContentLength: dados.count, textEncodingName: nil))
        tarefa.didReceive(dados)
        tarefa.didFinish()
    }

    func webView(_ webView: WKWebView, stop tarefa: any WKURLSchemeTask) {}
}
