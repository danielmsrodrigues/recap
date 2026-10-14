import SwiftUI
import UniformTypeIdentifiers

struct AulaDetailView: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(Definicoes.self) private var definicoes
    @Environment(Navegacao.self) private var navegacao
    let aula: Aula

    private typealias Tab = SeparadorAula

    @State private var tab: Tab = .apontamentos
    /// Painel das perguntas à aula, à direita (está na ContentView; aqui só o botão).
    @AppStorage("mostrarPerguntas") private var mostrarPerguntas = true
    /// Momento a mostrar na transcrição e texto a realçar nos apontamentos (pesquisa global, `[mm:ss]` clicado).
    @State private var salto: SaltoTempo?
    @State private var realce: [String] = []
    @State private var transcricao: Transcricao?
    @State private var apontamentos: String?
    @State private var slides: [Slide]?
    @State private var pdfProfessor: URL?
    @State private var escolherPDF = false
    @State private var estadoVideo: VideoResolver.Estado?
    @State private var confirmarRegenerar = false
    /// O PDF dos slides acabou de ser juntado (muda o texto da confirmação de regenerar).
    @State private var pdfJuntado = false
    @State private var estimativa: String?
    @State private var localizarVideo = false
    @State private var erro: String?
    @State private var controlador = ControladorNotas()
    /// Markdown no início da edição, para "Descartar alterações".
    @State private var originalEdicao: String?
    @State private var estadoEdicao = ""
    @State private var houveEdicao = false
    @State private var pdfPronto = false
    @State private var aCriarPDF = false

    private var job: Job? { fila.job(para: aula.pasta) }
    private var aGerar: Bool { job?.estado == .aCorrer && job?.estadoDe(.apontamentos).fase == .emCurso }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecalho
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider()
            conteudo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(aula.meta.titulo)
        .navigationSubtitle(aula.cadeira)
        .toolbar { barra }
        .task(id: "\(aula.pasta.path)#\(library.versao)") { carregar() }
        .task(id: navegacao.destino) { aplicarDestino() }
        #if DEBUG
        .task {
            // `APONTAMENTOS_EDITAR=1`: abre a aula já em edição (capturas de ecrã sem clicar).
            guard ProcessInfo.processInfo.environment["APONTAMENTOS_EDITAR"] == "1" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if apontamentos != nil { comecarEdicao() }
        }
        .task {
            // `APONTAMENTOS_SEPARADOR="Ligações"`: abre a aula nesse separador.
            if let nome = ProcessInfo.processInfo.environment["APONTAMENTOS_SEPARADOR"], let t = Tab(rawValue: nome) { tab = t }
        }
        #endif
        .confirmationDialog("Regenerar os apontamentos?", isPresented: $confirmarRegenerar) {
            Button("Regenerar") { gerar() }
        } message: {
            Text(avisoRegenerar)
        }
        .task(id: confirmarRegenerar) {
            if confirmarRegenerar { await estimar() } else { pdfJuntado = false }
        }
        .fileImporter(isPresented: $escolherPDF, allowedContentTypes: [.pdf]) { resultado in
            if case .success(let url) = resultado { juntarPDFProfessor(url) }
        }
        .fileImporter(isPresented: $localizarVideo, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { resultado in
            if case .success(let url) = resultado { religarVideo(url) }
        }
        .onDisappear {
            // As alterações já foram gravadas automaticamente; falta só registar que houve edição.
            if controlador.editando, houveEdicao { try? library.atualizarMeta(em: aula.pasta) { $0.editadoEm = .now } }
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") { erro = nil }
        } message: { Text($0) }
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Com o painel das perguntas aberto pode faltar largura: os separadores passam para baixo do título.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    // Largura ideal pequena: lado a lado sempre que o título caiba minimamente (o resto trunca).
                    tituloAula.frame(minWidth: 220, idealWidth: 240, maxWidth: .infinity, alignment: .leading)
                    seletor
                }
                VStack(alignment: .leading, spacing: 10) {
                    tituloAula
                    seletor
                }
            }

            if case .emFalta(let caminho) = estadoVideo {
                HStack {
                    Label {
                        Text("O vídeo original foi movido ou apagado: \(caminho). O mini-player e a extração de slides precisam dele.")
                    } icon: {
                        Image(systemName: "film.stack").foregroundStyle(.orange)
                    }
                    .font(.callout)
                    Spacer()
                    Button("Localizar vídeo…") { localizarVideo = true }
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
            }

            if let job { ProgressoJobView(job: job) }
        }
    }

    private var tituloAula: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(aula.meta.titulo).font(.title2.bold()).lineLimit(1)
            Text(subtitulo).font(.callout).foregroundStyle(.secondary).lineLimit(1).help(subtitulo)
        }
    }

    private var seletor: some View {
        Picker("Vista", selection: $tab) {
            ForEach(tabs) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        // A edição vive na vista dos apontamentos: sair dela perdia o que está no ecrã.
        .disabled(controlador.editando)
        .help(controlador.editando ? "Conclui a edição para mudar de separador" : "")
    }

    /// Aulas captadas em direto sem slides nem PDF não têm o separador Slides.
    private var tabs: [Tab] {
        aula.meta.origem == "direto" && slides == nil && pdfProfessor == nil ? Tab.allCases.filter { $0 != .slides } : Tab.allCases
    }

    private var subtitulo: String {
        var partes = [aula.cadeira, aula.meta.data.formatted(date: .long, time: .omitted)]
        if let d = aula.meta.duracao { partes.append(Timestamp.duracao(d)) }
        if let g = aula.meta.geracoes.last {
            partes.append("última geração: \(g.resumo)")
        }
        return partes.joined(separator: " · ")
    }

    // MARK: Conteúdo

    @ViewBuilder private var conteudo: some View {
        switch tab {
        case .apontamentos:
            if aGerar, let job, !job.textoEmCurso.isEmpty {
                NotesWebView(markdown: job.textoEmCurso, emStreaming: true, pastaAula: aula.pasta)
            } else if let apontamentos {
                VStack(spacing: 0) {
                    if controlador.editando {
                        BarraFormatacao(controlador: controlador, estado: estadoEdicao,
                                        aoDescartar: { Task { await descartarEdicao() } },
                                        aoConcluir: { Task { await concluirEdicao() } })
                        Divider()
                    }
                    NotesWebView(markdown: apontamentos, controlador: controlador,
                                 aoClicarTimestamp: aoClicarNosApontamentos,
                                 realcar: controlador.editando ? [] : realce, pastaAula: aula.pasta)
                }
            } else {
                vazioApontamentos
            }
        case .exercicios:
            ExerciciosView(aula: aula, aoClicarTimestamp: irParaTranscricao)
        case .ligacoes:
            LigacoesView(aula: aula, aoClicarTimestamp: irParaTranscricao) { pasta in
                navegacao.destino = DestinoAula(pasta: pasta, separador: .apontamentos)
            }
        case .slides:
            SlidesView(pasta: aula.pasta, slides: slides, pdf: pdfProfessor, podeExtrair: urlVideo != nil && job?.ativo != true) {
                try? FileManager.default.removeItem(at: aula.pasta.appending(path: Disco.slidesJSON))
                fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: urlVideo, gerarApontamentos: false))
            }
        case .transcricao:
            if let transcricao {
                TranscricaoView(transcricao: transcricao, irPara: salto)
            } else {
                ContentUnavailableView("Ainda sem transcrição", systemImage: "waveform",
                                       description: Text(job?.ativo == true ? "A transcrição está em curso." : "Esta aula ainda não foi transcrita."))
            }
        }
    }

    private var avisoRegenerar: String {
        var t = pdfJuntado ? "Os apontamentos atuais foram feitos sem este PDF. Ao regenerar, os slides entram nos tópicos certos.\n\n" : ""
        t += "Os apontamentos atuais são substituídos e ficam guardados em \(Disco.apontamentosAnteriorMD). A transcrição e os slides são reutilizados."
        if aula.meta.temEdicoesManuais { t += "\n\nAtenção: fizeste alterações à mão depois da última geração." }
        if let estimativa { t += "\n\n\(estimativa)" }
        return t
    }

    @ViewBuilder private var vazioApontamentos: some View {
        if aGerar {
            ContentUnavailableView("A gerar apontamentos…", systemImage: "text.badge.plus",
                                   description: Text("O texto aparece aqui à medida que chega."))
        } else if transcricao == nil {
            ContentUnavailableView("Ainda sem apontamentos", systemImage: "doc.text",
                                   description: Text("Os apontamentos são gerados depois da transcrição."))
        } else {
            ContentUnavailableView {
                Label("Ainda sem apontamentos", systemImage: "doc.text")
            } description: {
                Text(definicoes.faltaParaGerar ?? "A transcrição está pronta. \(estimativa ?? "")")
            } actions: {
                if definicoes.faltaParaGerar == nil {
                    Button("Gerar apontamentos") { gerar() }
                        .buttonStyle(.borderedProminent)
                        .disabled(job?.ativo == true)
                } else {
                    SettingsLink { Text("Abrir Definições…") }
                }
            }
            .task(id: aula.pasta) { await estimar() }
        }
    }

    // MARK: Barra

    @ToolbarContentBuilder private var barra: some ToolbarContent {
        ToolbarItemGroup {
            Button("Editar", systemImage: "pencil") { comecarEdicao() }
                .labelStyle(.titleAndIcon)
                .help("Editar os apontamentos diretamente, como num processador de texto")
                .disabled(apontamentos == nil || controlador.editando || aGerar)
            Button("Regenerar apontamentos", systemImage: "arrow.clockwise") { confirmarRegenerar = true }
                .help("Gerar de novo os apontamentos a partir da transcrição guardada")
                .disabled(transcricao == nil || apontamentos == nil || job?.ativo == true || definicoes.faltaParaGerar != nil || controlador.editando)
            ShareLink(item: aula.pasta.appending(path: Disco.apontamentosPDF),
                      preview: SharePreview(aula.meta.titulo, icon: Image(systemName: "doc.richtext"))) {
                Label("Partilhar PDF", systemImage: "square.and.arrow.up")
            }
            .help("Enviar o PDF para o Freeform, AirDrop (iPad/iPhone), Notas…")
            .disabled(!pdfPronto)
            Menu("Slides do professor", systemImage: "doc.richtext") {
                Button(pdfProfessor == nil ? "Juntar PDF dos slides…" : "Substituir PDF dos slides…") { escolherPDF = true }
                if pdfProfessor != nil {
                    Button("Remover PDF dos slides", role: .destructive) { removerPDFProfessor() }
                }
            }
            .help("Juntar os slides em PDF publicados pelo professor; o Claude usa-os como fonte principal")
            Menu("Exportar", systemImage: "arrow.down.doc") {
                Button("PDF…") { exportar(pdf: true) }.disabled(!pdfPronto)
                Button("Markdown (.md)…") { exportar(pdf: false) }
            }
            .help("Guardar uma cópia dos apontamentos")
            .disabled(apontamentos == nil)
            Button("Mostrar no Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([aula.pasta])
            }
            .help("Abrir a pasta da aula no Finder")
        }
        ToolbarItem {
            Toggle(isOn: $mostrarPerguntas) {
                Label("Perguntas", systemImage: "bubble.left.and.text.bubble.right")
            }
            .help("Perguntar o que quiseres sobre esta aula (⌥⌘P)")
            .keyboardShortcut("p", modifiers: [.command, .option])
        }
        ToolbarItem {
            if aula.meta.revista {
                Button { marcarRevista(false) } label: {
                    Label("Revista", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("Aula revista. Clica para voltar a marcar como por rever.")
            } else {
                Button { marcarRevista(true) } label: {
                    Label("Marcar como revista", systemImage: "checkmark.circle").labelStyle(.titleAndIcon)
                }
                .help("Já estudaste esta aula? Marca-a como revista.")
            }
        }
    }

    // MARK: Ações

    /// Durante a edição, clicar num `[mm:ss]` não muda de separador.
    private var aoClicarNosApontamentos: ((Double) -> Void)? {
        if controlador.editando { return nil }
        return { irParaTranscricao($0) }
    }

    private func irParaTranscricao(_ segundos: Double) {
        salto = SaltoTempo(segundos: segundos)
        tab = .transcricao
    }

    /// Um pedido para abrir esta aula num sítio concreto.
    private func aplicarDestino() {
        guard let d = navegacao.destino, d.pasta.mesmoCaminho(aula.pasta) else { return }
        navegacao.destino = nil
        // A meio da edição não se muda de separador (perdia-se o que está no ecrã).
        guard !controlador.editando else { return }
        tab = tabs.contains(d.separador) ? d.separador : .apontamentos
        realce = d.termos
        if let t = d.tempo { salto = SaltoTempo(segundos: t) }
    }

    private func carregar() {
        transcricao = Disco.lerTranscricao(aula.pasta)
        apontamentos = Disco.lerApontamentos(aula.pasta)
        slides = Disco.lerSlides(aula.pasta)
        pdfProfessor = Disco.urlPDFProfessor(aula.pasta)
        atualizarPDF()
        guard let ref = aula.meta.video else { estadoVideo = nil; return }
        let estado = VideoResolver.resolver(ref)
        if case .movido(let url, let novaRef) = estado {
            try? library.atualizarMeta(em: aula.pasta) { $0.video = novaRef }
            estadoVideo = .ok(url)
        } else {
            estadoVideo = estado
        }
    }

    private var urlVideo: URL? {
        if case .ok(let url) = estadoVideo { return url }
        return nil
    }

    private func gerar() {
        fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: urlVideo,
                           gerarApontamentos: true, soApontamentos: true))
    }

    private func estimar() async {
        // Só a API tem custo por pedido; com o Claude Code conta para os limites da subscrição.
        guard definicoes.motor == .api, let transcricao, let chave = KeychainStore.chaveAPI() else {
            estimativa = nil
            return
        }
        let gerador = NotesGenerator(motor: .api(AnthropicClient(chave: chave)), modelo: definicoes.modeloClaude,
                                     esforco: definicoes.esforco, precos: definicoes.tabelaPrecos)
        let contexto = ContextoAula(cadeira: aula.cadeira, titulo: aula.meta.titulo, data: aula.meta.data,
                                    glossario: library.cadeira(nome: aula.cadeira)?.meta.glossario ?? "",
                                    transcricao: transcricao)
        do {
            guard let e = try await gerador.estimar(contexto, prompt: PromptStore.ler()) else { return }
            estimativa = "Entrada: \(e.tokens.formatted()) tokens (≈ \(TabelaPrecos.formatar(e.custoEntrada))), mais a saída."
        } catch {
            estimativa = "Não foi possível estimar o custo: \(error.localizedDescription)"
        }
    }

    /// O PDF vive ao lado do Markdown (`apontamentos.pdf`) e é refeito quando o Markdown muda.
    private func atualizarPDF() {
        guard let apontamentos, !aGerar else { pdfPronto = false; return }
        if Disco.pdfAtualizado(em: aula.pasta) { pdfPronto = true; return }
        pdfPronto = false
        guard !aCriarPDF else { return }
        aCriarPDF = true
        let pasta = aula.pasta
        Task {
            defer { aCriarPDF = false }
            do {
                try await ExportadorPDF.exportar(markdown: apontamentos, pastaAula: pasta, para: pasta.appending(path: Disco.apontamentosPDF))
                pdfPronto = true
            } catch {
                erro = "Não foi possível criar o PDF: \(error.localizedDescription)"
            }
        }
    }

    private func exportar(pdf: Bool) {
        let painel = NSSavePanel()
        painel.nameFieldStringValue = Disco.nomeDePasta(aula.meta.titulo) + (pdf ? ".pdf" : ".md")
        painel.allowedContentTypes = [pdf ? .pdf : (UTType(filenameExtension: "md") ?? .plainText)]
        guard painel.runModal() == .OK, let destino = painel.url else { return }
        let origem = aula.pasta.appending(path: pdf ? Disco.apontamentosPDF : Disco.apontamentosMD)
        do {
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.copyItem(at: origem, to: destino)
        } catch {
            erro = "Não foi possível exportar: \(error.localizedDescription)"
        }
    }

    // MARK: Edição

    private func comecarEdicao() {
        tab = .apontamentos
        originalEdicao = apontamentos
        houveEdicao = false
        estadoEdicao = "Guarda automaticamente"
        controlador.aoGravar = { await gravarRascunho() }
        controlador.definirEdicao(true)
    }

    /// Grava o documento em edição (chamado pouco depois de cada alteração, como no Word).
    private func gravarRascunho() async {
        guard controlador.editando, controlador.alterado else { return }
        controlador.alterado = false
        do {
            // Só grava o ficheiro: mexer no estado da vista a meio da escrita fazia a janela redesenhar.
            let md = try await controlador.markdown()
            try Disco.escreverApontamentos(md, em: aula.pasta)
            if !houveEdicao { houveEdicao = true }
            let estado = "Guardado às \(Date.now.formatted(date: .omitted, time: .shortened))"
            if estadoEdicao != estado { estadoEdicao = estado }
        } catch {
            estadoEdicao = "Não foi possível guardar"
            erro = "Não foi possível guardar: \(error.localizedDescription)"
        }
    }

    private func concluirEdicao() async {
        if controlador.alterado, let md = try? await controlador.markdown() {
            try? Disco.escreverApontamentos(md, em: aula.pasta)
            houveEdicao = true
        }
        controlador.definirEdicao(false)
        apontamentos = Disco.lerApontamentos(aula.pasta)
        if houveEdicao { try? library.atualizarMeta(em: aula.pasta) { $0.editadoEm = .now } }
    }

    private func descartarEdicao() async {
        controlador.definirEdicao(false)
        guard let original = originalEdicao else { return }
        if houveEdicao { try? Disco.escreverApontamentos(original, em: aula.pasta) }
        apontamentos = original
        controlador.repor(original)
        houveEdicao = false
    }

    private func juntarPDFProfessor(_ url: URL) {
        let acedeu = url.startAccessingSecurityScopedResource()
        defer { if acedeu { url.stopAccessingSecurityScopedResource() } }
        do {
            try Disco.juntarPDFProfessor(url, em: aula.pasta)
            pdfProfessor = Disco.urlPDFProfessor(aula.pasta)
            let pasta = aula.pasta
            Task { await SlidesNosApontamentos.garantirPaginasEmFundo(em: pasta) }
            // Com apontamentos já feitos sem o PDF, propõe refazê-los para os slides entrarem nos tópicos.
            if apontamentos != nil, job?.ativo != true, definicoes.faltaParaGerar == nil, !controlador.editando {
                pdfJuntado = true
                confirmarRegenerar = true
            } else {
                tab = .slides
            }
        } catch {
            erro = error.localizedDescription
        }
    }

    /// Vai para o Lixo (recuperável).
    private func removerPDFProfessor() {
        guard let pdfProfessor else { return }
        do {
            try FileManager.default.trashItem(at: pdfProfessor, resultingItemURL: nil)
            SlidesNosApontamentos.apagarPaginas(em: aula.pasta)
            self.pdfProfessor = nil
        } catch {
            erro = error.localizedDescription
        }
    }

    private func marcarRevista(_ revista: Bool) {
        do { try library.definirRevista(revista, em: aula.pasta) } catch { erro = error.localizedDescription }
    }

    private func religarVideo(_ url: URL) {
        let acedeu = url.startAccessingSecurityScopedResource()
        defer { if acedeu { url.stopAccessingSecurityScopedResource() } }
        do {
            try library.atualizarMeta(em: aula.pasta) { $0.video = VideoResolver.referencia(para: url) }
        } catch {
            erro = "Não foi possível guardar o novo caminho do vídeo: \(error.localizedDescription)"
        }
    }
}
