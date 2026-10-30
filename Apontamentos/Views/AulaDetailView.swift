import SwiftUI
import UniformTypeIdentifiers

struct AulaDetailView: View {
    @Environment(Library.self) private var library
    #if os(macOS)
    @Environment(ProcessingQueue.self) private var fila
    #endif
    @Environment(Definicoes.self) private var definicoes
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    let aula: Aula

    private typealias Tab = SeparadorAula

    @State private var tab: Tab = .apontamentos
    /// Painel Estudo, à direita (está na ContentView; aqui só o botão).
    @AppStorage("mostrarEstudo") private var mostrarEstudo = true
    /// Momento a mostrar na transcrição e texto a realçar nos apontamentos (pesquisa global, `[mm:ss]` clicado).
    @State private var salto: SaltoTempo?
    @State private var realce: [String] = []
    @State private var transcricao: Transcricao?
    @State private var apontamentos: String?
    @State private var slides: [Slide]?
    /// Para a barra de capítulos: as secções dos apontamentos com momento (ver `Capitulos`).
    @State private var capitulos: [Capitulos.Capitulo] = []
    /// O aviso "Revista · Abrir próxima · Desfazer" (no Mac e no iPhone).
    @Environment(AvisoRevista.self) private var aviso: AvisoRevista?
    @State private var pdfsProfessor: [PDFProfessor] = []
    /// Outros materiais do professor (ver `Materiais`).
    @State private var materiais: [String] = []
    #if os(macOS)
    @State private var escolherMateriais = false
    @State private var estadoVideo: VideoResolver.Estado?
    @State private var confirmarRegenerar = false
    /// PDFs dos slides e outros materiais acabados de juntar (muda o texto da confirmação de regenerar).
    @State private var pdfsJuntados = 0
    @State private var materiaisJuntados = 0
    @State private var estimativa: String?
    @State private var localizarVideo = false
    #endif
    @State private var erro: String?
    @State private var controlador = ControladorNotas()
    /// Markdown no início da edição, para "Descartar alterações".
    @State private var originalEdicao: String?
    @State private var estadoEdicao = ""
    @State private var houveEdicao = false
    @State private var pdfPronto = false
    @State private var aCriarPDF = false
    #if !os(macOS)
    /// PDF criado na hora para partilhar (quando o do Mac está desatualizado).
    @State private var pdfPartilhado: FicheiroPartilhado?
    #endif
    /// Procurar nos apontamentos (⌘F).
    @State private var procurando = false
    @State private var termoProcura = ""
    @State private var pedidosProcura = 0
    /// Secção a mostrar nos apontamentos (link de uma resposta).
    @State private var irSeccao: PedidoSeccao?

    #if os(macOS)
    private var job: Job? { fila.job(para: aula.pasta) }
    private var aGerar: Bool { job?.estado == .aCorrer && job?.faseDe(.apontamentos) == .emCurso }
    /// A aula está na fila (transcrição, slides ou apontamentos).
    private var ocupada: Bool { job?.ativo == true }
    #else
    /// No iOS não se gera nada: a aula nunca está a ser processada aqui.
    private var aGerar: Bool { false }
    private var ocupada: Bool { false }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecalho
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)
            Divider()
            conteudo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(macOS)
        .toolbar { barraMac }
        #else
        // O título e o subtítulo vivem na barra, uma vez só.
        .navigationTitle(aula.meta.titulo)
        .navigationSubtitle(subtitulo)
        .toolbar { barra }
        #endif
        // A `Aula` muda quando a transcrição, os slides, os apontamentos ou os metadados mudam no disco:
        // não é preciso reler a cada alteração noutra aula.
        .task(id: aula) {
            carregar()
            #if os(macOS)
            estudo.gerarLigacoesSePreciso(aula)
            #else
            // Os slides e os PDFs só vêm do iCloud quando a aula abre (com a API, as ligações pedem-se no painel).
            Disco.descarregar(aula.pasta)
            #endif
        }
        // O iCloud trouxe mudanças desta aula (outro dispositivo): sem edição a meio, relê.
        .onChange(of: library.versao) {
            if !controlador.editando && !aGerar { carregar() }
        }
        // As notas das ligações ("🔗 Aprofundado na Aula 2") foram postas nos apontamentos.
        .onChange(of: estudo.versaoApontamentos) {
            if !controlador.editando && !aGerar { apontamentos = Disco.lerApontamentos(aula.pasta) }
        }
        .task(id: navegacao.destino) { aplicarDestino() }
        .task(id: "\(apontamentos?.hashValue ?? 0)#\(slides?.count ?? -1)#\(transcricao?.duracao ?? 0)") {
            let seccoes = SeccoesApontamentos.partir(apontamentos ?? "").seccoes
            capitulos = Capitulos.calcular(seccoes, duracao: transcricao?.duracao ?? aula.meta.duracao ?? 0,
                                           slides: (slides ?? []).map(\.inicio))
        }
        .focusedSceneValue(\.procurarNosApontamentos, apontamentos == nil || aGerar ? nil : AcaoProcurar { abrirProcura() })
        .focusedSceneValue(\.comandosAula, comandos)
        .onChange(of: tab) { if tab != .apontamentos { fecharProcura() } }
        #if DEBUG
        .task {
            // `APONTAMENTOS_EDITAR=1`: abre a aula já em edição (capturas de ecrã sem clicar).
            guard ProcessInfo.processInfo.environment["APONTAMENTOS_EDITAR"] == "1" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if apontamentos != nil { comecarEdicao() }
        }
        .task {
            // `APONTAMENTOS_SELECAO="<texto>"`: seleciona esse texto nos apontamentos (o botão "Perguntar" aparece);
            // com `APONTAMENTOS_PERGUNTAR_SELECAO=1`, pergunta logo sobre ele. A transcrição trata do seu.
            let env = ProcessInfo.processInfo.environment
            guard let alvo = env["APONTAMENTOS_SELECAO"],
                  let json = try? JSONEncoder().encode(alvo), let literal = String(data: json, encoding: .utf8) else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard tab == .apontamentos else { return }
            controlador.web?.evaluateJavaScript("window.find(\(literal))", completionHandler: nil)
            guard env["APONTAMENTOS_PERGUNTAR_SELECAO"] == "1" else { return }
            try? await Task.sleep(for: .seconds(1.5))
            controlador.web?.evaluateJavaScript("perguntarSelecao()", completionHandler: nil)
        }
        .task {
            // `APONTAMENTOS_PROCURAR="<texto>"`: abre a procura nos apontamentos com esse texto;
            // `APONTAMENTOS_PROCURAR_SEGUINTE=<n>` avança n ocorrências.
            let env = ProcessInfo.processInfo.environment
            guard let termo = env["APONTAMENTOS_PROCURAR"] else { return }
            try? await Task.sleep(for: .seconds(1.5))
            abrirProcura()
            termoProcura = termo
            for _ in 0..<(Int(env["APONTAMENTOS_PROCURAR_SEGUINTE"] ?? "") ?? 0) {
                try? await Task.sleep(for: .milliseconds(400))
                controlador.andarProcura(1)
            }
        }
        .task {
            // `APONTAMENTOS_SECCAO="<âncora>|<texto do link>"`: o mesmo que clicar nesse link no painel das perguntas.
            guard let partes = ProcessInfo.processInfo.environment["APONTAMENTOS_SECCAO"]?.components(separatedBy: "|") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .apontamentos,
                                            seccao: LigacaoSeccao(ancora: partes[0], texto: partes.count > 1 ? partes[1] : ""))
        }
        #if !os(macOS)
        .task {
            // `APONTAMENTOS_PDF="<caminho>"`: exporta os apontamentos para esse PDF (o exportador do iOS, sem tocar no ecrã).
            guard let caminho = ProcessInfo.processInfo.environment["APONTAMENTOS_PDF"] else { return }
            // Depois das vistas web da aula e do painel: como quando se toca em "Partilhar".
            try? await Task.sleep(for: .seconds(8))
            guard let apontamentos else { return }
            do { try await ExportadorPDF.exportar(markdown: apontamentos, pastaAula: aula.pasta, para: URL(fileURLWithPath: caminho)) }
            catch { erro = "PDF: \(error.localizedDescription)" }
        }
        #endif
        .task {
            // `APONTAMENTOS_SEPARADOR="Ligações"`: abre a aula nesse separador.
            if let nome = ProcessInfo.processInfo.environment["APONTAMENTOS_SEPARADOR"], let t = Tab(rawValue: nome) { tab = t }
        }
        #endif
        #if os(macOS)
        .confirmationDialog("Regenerar os apontamentos?", isPresented: $confirmarRegenerar) {
            Button("Regenerar") { gerar() }
        } message: {
            Text(avisoRegenerar)
        }
        .task(id: confirmarRegenerar) {
            if confirmarRegenerar { await estimar() } else { pdfsJuntados = 0; materiaisJuntados = 0 }
        }
        .fileImporter(isPresented: $escolherMateriais, allowedContentTypes: Anexos.tiposAceites, allowsMultipleSelection: true) { resultado in
            if case .success(let urls) = resultado, !urls.isEmpty { juntarMateriaisProfessor(urls) }
        }
        .fileImporter(isPresented: $localizarVideo, allowedContentTypes: ContentView.tiposVideo) { resultado in
            if case .success(let url) = resultado { religarVideo(url) }
        }
        #endif
        .onDisappear {
            // As alterações já foram gravadas automaticamente; falta só registar que houve edição.
            if controlador.editando, houveEdicao { try? library.atualizarMeta(em: aula.pasta) { $0.editadoEm = .now } }
            if controlador.editando { largarEdicaoNasLigacoes() }
        }
        #if !os(macOS)
        .sheet(item: $pdfPartilhado) { FolhaPartilha(ficheiro: $0) }
        #endif
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") { erro = nil }
        } message: { Text($0) }
    }

    // MARK: Cabeçalho

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if !os(macOS)
            seletor
            #endif
            if !capitulos.isEmpty {
                // Durante a edição, não muda de separador: Concluir e Descartar estão nos apontamentos.
                LinhaCapitulos(capitulos: capitulos) { if !controlador.editando { irParaTranscricao($0.inicio) } }
            }

            #if os(macOS)
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
            #endif
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

    /// Todos: mesmo uma aula captada em direto sem slides pode receber os PDFs e os materiais do professor.
    private var tabs: [Tab] { Tab.allCases }

    private var subtitulo: String {
        var partes = [aula.cadeira, aula.meta.data.formatted(date: .long, time: .omitted)]
        if let d = aula.meta.duracao { partes.append(Timestamp.duracao(d)) }
        if let gerados = aula.meta.quandoGerados { partes.append(gerados) }
        return partes.joined(separator: " · ")
    }

    /// Sem job ativo nem edição em curso: pode-se gerar, extrair e exportar.
    private var livre: Bool { !ocupada && !controlador.editando }

    /// As mesmas ações da toolbar, para os menus Aula e Ver.
    private var comandos: ComandosAula {
        #if os(macOS)
        ComandosAula(
            editar: apontamentos != nil && !controlador.editando && !aGerar ? { comecarEdicao() } : nil,
            gerarApontamentos: transcricao != nil && livre && definicoes.faltaParaGerar == nil
                ? { if apontamentos == nil { gerar() } else { confirmarRegenerar = true } } : nil,
            temApontamentos: apontamentos != nil,
            extrairSlides: urlVideo != nil && livre ? { extrairSlides() } : nil,
            guardarPDF: apontamentos != nil && pdfPronto ? { exportar(pdf: true) } : nil,
            guardarMarkdown: apontamentos != nil ? { exportar(pdf: false) } : nil,
            revista: aula.meta.revista,
            marcarRevista: { marcarRevista($0) },
            mostrarNoFinder: { NSWorkspace.shared.activateFileViewerSelecting([aula.pasta]) },
            separador: Binding(get: { tab }, set: { if !controlador.editando { tab = $0 } }),
            separadores: tabs
        )
        #else
        ComandosAula(
            editar: apontamentos != nil && !controlador.editando ? { comecarEdicao() } : nil,
            temApontamentos: apontamentos != nil,
            revista: aula.meta.revista,
            marcarRevista: { marcarRevista($0) },
            separador: Binding(get: { tab }, set: { if !controlador.editando { tab = $0 } }),
            separadores: tabs
        )
        #endif
    }

    // MARK: Conteúdo

    @ViewBuilder private var conteudo: some View {
        switch tab {
        case .apontamentos:
            // Uma só vista web para o texto a chegar e para o guardado: trocar de vista era carregar a página
            // (KaTeX incluído) outra vez ao começar e ao acabar cada geração.
            // O texto a chegar lê-se numa vista à parte: cada pedaço novo redesenhava a aula toda e a toolbar piscava.
            #if os(macOS)
            ComTextoEmCurso(job: aGerar ? job : nil) { notas($0) }
            #else
            notas(nil)
            #endif
        case .materiais:
            #if os(macOS)
            SlidesView(pasta: aula.pasta, slides: slides, pdfs: pdfsProfessor, materiais: materiais, podeExtrair: urlVideo != nil && !ocupada,
                       aoExtrair: extrairSlides, aoJuntarMateriais: { escolherMateriais = true }, aoRemoverPDF: removerPDFProfessor,
                       aoRemoverMaterial: removerMaterial)
            #else
            SlidesView(pasta: aula.pasta, slides: slides, pdfs: pdfsProfessor, materiais: materiais)
            #endif
        case .transcricao:
            if let transcricao {
                TranscricaoView(transcricao: transcricao, irPara: salto, aoPerguntar: perguntarSobre)
            } else {
                ContentUnavailableView("Ainda sem transcrição", systemImage: "waveform",
                                       description: Text(ocupada ? "A transcrição está em curso." : "Esta aula ainda não foi transcrita."))
            }
        }
    }

    /// Os apontamentos (ou o texto a chegar), com as barras de edição e de procura.
    @ViewBuilder private func notas(_ emCurso: String?) -> some View {
                if let texto = emCurso?.isEmpty == false ? emCurso : apontamentos {
                    VStack(spacing: 0) {
                        if controlador.editando {
                            BarraFormatacao(controlador: controlador, estado: estadoEdicao,
                                            aoDescartar: { Task { await descartarEdicao() } },
                                            aoConcluir: { Task { await concluirEdicao() } })
                            Divider()
                        }
                        if procurando {
                            BarraProcura(controlador: controlador, termo: $termoProcura, pedidosFoco: pedidosProcura, aoFechar: fecharProcura)
                            Divider()
                        }
                        NotesWebView(markdown: texto, emStreaming: emCurso != nil, controlador: controlador,
                                     aoClicarTimestamp: aoClicarNosApontamentos,
                                     realcar: controlador.editando ? [] : realce, pastaAula: aula.pasta,
                                     aoPerguntar: { perguntarSobre(CitacaoPergunta(texto: $0, origem: .apontamentos)) },
                                     aoClicarSeccao: irParaSeccao, irParaSeccao: irSeccao)
                    }
                } else {
                    vazioApontamentos
                }
    }

    #if os(macOS)
    private var avisoRegenerar: String {
        var t = switch (pdfsJuntados, materiaisJuntados) {
        case (0, 0): ""
        case (1, 0): "Os apontamentos atuais foram feitos sem este PDF. Ao regenerar, os slides dados na aula entram nos tópicos certos.\n\n"
        case (_, 0): "Os apontamentos atuais foram feitos sem estes PDFs. Ao regenerar, os slides dados na aula entram nos tópicos certos.\n\n"
        case (0, 1): "Os apontamentos atuais foram feitos sem este material. Ao regenerar, o que ele traz entra nos apontamentos.\n\n"
        default: "Os apontamentos atuais foram feitos sem estes materiais. Ao regenerar, o que eles trazem entra nos apontamentos.\n\n"
        }
        t += "Os apontamentos atuais são substituídos e ficam guardados em \(Disco.apontamentosAnteriorMD). A transcrição e os slides são reutilizados."
        if aula.meta.temEdicoesManuais { t += "\n\nAtenção: fizeste alterações à mão depois da última geração." }
        if let estimativa { t += "\n\n\(estimativa)" }
        return t
    }

    #endif

    @ViewBuilder private var vazioApontamentos: some View {
        #if os(macOS)
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
        #else
        ContentUnavailableView("Ainda sem apontamentos", systemImage: "doc.text",
                               description: Text(transcricao == nil ? "Esta aula ainda não foi transcrita." : "Os apontamentos geram-se no Mac."))
        #endif
    }

    // MARK: Barra

    #if os(macOS)
    /// A barra de cima da aula, como no design: o título (cadeira · data · duração por baixo), os separadores e
    /// Criar com IA ▾ · partilhar · Revista · Estudo. O painel Estudo começa por baixo dela.
    /// Editar os apontamentos está no menu Aula (⌘E).
    @ToolbarContentBuilder private var barraMac: some ToolbarContent {
        ToolbarItem {
            VStack(alignment: .leading, spacing: 1) {
                Text(aula.meta.titulo).font(.headline)
                Text(subtitulo).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.horizontal, 8)
            .help(aula.meta.titulo)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        ToolbarItem { seletor }
        ToolbarSpacer(.flexible)
        ToolbarItemGroup {
            Menu("Criar com IA", systemImage: "sparkles") {
                Section("Criar a partir desta aula") {
                    Button(apontamentos == nil ? "Gerar apontamentos" : "Refazer apontamentos…") {
                        if apontamentos == nil { gerar() } else { confirmarRegenerar = true }
                    }
                    .disabled(transcricao == nil || definicoes.faltaParaGerar != nil)
                    Button("Exercícios") { abrirEstudo(.exercicios) }
                    Button("Ligações com outras aulas") { abrirEstudo(.ligacoes) }
                }
                Divider()
                Button("Extrair slides de novo") { extrairSlides() }
                    .disabled(urlVideo == nil)
                if let g = aula.meta.geracoes.last {
                    Divider()
                    Text("Última geração: \(g.resumo)")
                }
            }
            .labelStyle(.titleAndIcon)
            .help("Criar materiais de estudo com IA a partir desta aula")
            .disabled(!livre)
            Menu("Partilhar", systemImage: "square.and.arrow.up") {
                ShareLink(item: aula.pasta.appending(path: Disco.apontamentosPDF),
                          preview: SharePreview(aula.meta.titulo, icon: Image(systemName: "doc.richtext"))) {
                    Label("Partilhar PDF…", systemImage: "square.and.arrow.up")
                }
                .disabled(!pdfPronto)
                Divider()
                Button("Guardar PDF…") { exportar(pdf: true) }.disabled(!pdfPronto)
                Button("Guardar Markdown…") { exportar(pdf: false) }
            }
            .help("Partilhar ou guardar os apontamentos")
            .disabled(apontamentos == nil)
        }
        ToolbarItem {
            if aula.meta.revista {
                Button { marcarRevista(false) } label: {
                    Label("Revista", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("Revista: clicar volta a pô-la por rever")
            } else {
                Button { marcarRevista(true) } label: {
                    Label("Marcar como revista", systemImage: "checkmark.circle").labelStyle(.titleAndIcon)
                }
            }
        }
        // O ícone de painel lateral do macOS (como no Xcode e no Pages): percebe-se que abre e fecha o painel da
        // direita, mesmo dentro do menu » com a janela estreita, onde fica o nome "Mostrar/Esconder Estudo".
        ToolbarItem {
            Button(mostrarEstudo ? "Esconder Estudo" : "Mostrar Estudo", systemImage: "sidebar.right") {
                withAnimation(.snappy) { mostrarEstudo.toggle() }
            }
            .help(mostrarEstudo ? "Esconder o painel Estudo (⌥⌘P)" : "Mostrar o painel Estudo: perguntas, exercícios e ligações (⌥⌘P)")
        }
    }
    #endif

    #if !os(macOS)
    /// No iPhone e no iPad: Editar · Partilhar ▾ | Revista | Estudo.
    @ToolbarContentBuilder private var barra: some ToolbarContent {
        ToolbarItemGroup {
            Button("Editar", systemImage: "pencil") { comecarEdicao() }
                .disabled(apontamentos == nil || controlador.editando)
            Menu("Partilhar", systemImage: "square.and.arrow.up") {
                // O PDF é feito no Mac (ao lado do Markdown); se estiver desatualizado, cria-se aqui na hora.
                if pdfPronto {
                    ShareLink(item: aula.pasta.appending(path: Disco.apontamentosPDF),
                              preview: SharePreview(aula.meta.titulo, icon: Image(systemName: "doc.richtext"))) {
                        Label("Apontamentos em PDF", systemImage: "doc.richtext")
                    }
                } else {
                    Button("Apontamentos em PDF", systemImage: "doc.richtext") { criarPDF() }
                        .disabled(aCriarPDF)
                }
                ShareLink(item: aula.pasta.appending(path: Disco.apontamentosMD),
                          preview: SharePreview(aula.meta.titulo, icon: Image(systemName: "doc.plaintext"))) {
                    Label("Apontamentos em Markdown", systemImage: "doc.plaintext")
                }
            }
            .disabled(apontamentos == nil)
        }
        ToolbarItem {
            // No iPhone a barra é estreita: só o ícone, verde quando revista.
            Button { marcarRevista(!aula.meta.revista) } label: {
                Label(aula.meta.revista ? "Revista" : "Marcar como revista",
                      systemImage: aula.meta.revista ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .tint(aula.meta.revista ? .green : nil)
        }
        ToolbarItem {
            Toggle(isOn: $mostrarEstudo) {
                Label("Estudo", systemImage: "bubble.left.and.text.bubble.right")
            }
            .help("Perguntas, exercícios e ligações desta aula (⌥⌘P)")
        }
    }
    #endif

    // MARK: Ações

    /// Durante a edição, clicar num `[mm:ss]` não muda de separador.
    private var aoClicarNosApontamentos: ((Double) -> Void)? {
        if controlador.editando { return nil }
        return { irParaTranscricao($0) }
    }

    /// Leva o trecho selecionado para o painel Estudo (e abre-o, nas perguntas), à espera da pergunta.
    private func perguntarSobre(_ citacao: CitacaoPergunta) {
        estudo.citar(citacao, em: aula)
        UserDefaults.standard.set(SeccaoEstudo.perguntas.rawValue, forKey: "seccaoEstudo")
        mostrarEstudo = true
    }

    /// Abre o painel Estudo numa secção (Criar com IA ▾).
    private func abrirEstudo(_ seccao: SeccaoEstudo) {
        UserDefaults.standard.set(seccao.rawValue, forKey: "seccaoEstudo")
        mostrarEstudo = true
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
        if let s = d.seccao { irParaSeccao(s) }
    }

    /// Mostra a secção de um link `[Título](#ancora)`. Se nenhum título lhe corresponder (apontamentos refeitos
    /// depois da resposta), procura o texto do link na página.
    private func irParaSeccao(_ ligacao: LigacaoSeccao) {
        // Link para outra aula (`#<aula>/<secção>`, nas notas das ligações).
        let destino = estudo.destino(ligacao, aPartirDe: aula)
        guard destino.pasta.mesmoCaminho(aula.pasta) else { navegacao.destino = destino; return }
        let ligacao = destino.seccao ?? ligacao
        let markdown = apontamentos ?? Disco.lerApontamentos(aula.pasta) ?? ""
        if let s = Seccoes.resolver(ligacao, em: Seccoes.lista(markdown)) {
            irSeccao = PedidoSeccao(indice: s.indice)
        } else if !ligacao.texto.isEmpty {
            realce = [ligacao.texto]
        }
    }

    private func abrirProcura() {
        tab = .apontamentos
        procurando = true
        pedidosProcura += 1
    }

    private func fecharProcura() {
        guard procurando else { return }
        procurando = false
        controlador.limparProcura()
    }

    private func carregar() {
        // Mudanças feitas ao mesmo tempo noutro dispositivo (pelo iCloud): decide-se antes de ler.
        ConflitosICloud.resolverPerguntas(aula.pasta)
        let copias = ConflitosICloud.resolver(aula.pasta.appending(path: Disco.apontamentosMD))
        if !copias.isEmpty {
            erro = "Os apontamentos foram mudados noutro dispositivo ao mesmo tempo. Ficou a versão mais recente; a outra está na pasta da aula, em \(copias.map(\.lastPathComponent).joined(separator: ", "))."
        }
        transcricao = Disco.lerTranscricao(aula.pasta)
        apontamentos = Disco.lerApontamentos(aula.pasta)
        slides = Disco.lerSlides(aula.pasta)
        pdfsProfessor = Disco.pdfsProfessor(aula.pasta, nomes: aula.meta.nomesPDFs ?? [:])
        materiais = Materiais.nomes(em: aula.pasta)
        atualizarPDF()
        #if os(macOS)
        guard let ref = aula.meta.video else { estadoVideo = nil; return }
        let estado = VideoResolver.resolver(ref)
        if case .movido(let url, let novaRef) = estado {
            try? library.atualizarMeta(em: aula.pasta) { $0.video = novaRef }
            estadoVideo = .ok(url)
        } else {
            estadoVideo = estado
        }
        #endif
    }

    #if os(macOS)
    private var urlVideo: URL? {
        if case .ok(let url) = estadoVideo { return url }
        return nil
    }

    private func gerar() {
        fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: urlVideo,
                           gerarApontamentos: true, soApontamentos: true))
    }

    /// Volta a analisar o vídeo com as definições atuais (Definições → Slides e câmara do professor da cadeira).
    private func extrairSlides() {
        try? FileManager.default.removeItem(at: aula.pasta.appending(path: Disco.slidesJSON))
        fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: urlVideo, gerarApontamentos: false))
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
            guard let e = try await gerador.estimar(contexto, prompt: definicoes.promptApontamentos(idioma: IdiomaAula(codigo: transcricao.idioma))) else { return }
            estimativa = "Entrada: \(e.tokens.formatted()) tokens (≈ \(TabelaPrecos.formatar(e.custoEntrada))), mais a saída."
        } catch {
            estimativa = "Não foi possível estimar o custo: \(error.localizedDescription)"
        }
    }

    #endif

    #if os(macOS)
    /// O PDF vive ao lado do Markdown (`apontamentos.pdf`) e é refeito quando o Markdown muda,
    /// uns segundos depois de a aula abrir, para não competir com o que está a aparecer no ecrã.
    private func atualizarPDF() {
        guard let apontamentos, !aGerar else { pdfPronto = false; return }
        if Disco.pdfAtualizado(em: aula.pasta) { pdfPronto = true; return }
        pdfPronto = false
        guard !aCriarPDF else { return }
        aCriarPDF = true
        let pasta = aula.pasta
        Task(priority: .utility) {
            defer { aCriarPDF = false }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
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
    #else
    /// No iOS o PDF não se refaz sozinho: é o que o Mac deixou, se estiver em dia com o Markdown.
    private func atualizarPDF() {
        pdfPronto = apontamentos != nil && Disco.pdfAtualizado(em: aula.pasta)
    }

    /// Um PDF dos apontamentos atuais num ficheiro temporário, para partilhar (não vai para a pasta da aula).
    private func criarPDF() {
        guard let apontamentos else { return }
        aCriarPDF = true
        let destino = FileManager.default.temporaryDirectory.appending(path: Disco.nomeDePasta(aula.meta.titulo) + ".pdf")
        Task {
            defer { aCriarPDF = false }
            do {
                try await ExportadorPDF.exportar(markdown: apontamentos, pastaAula: aula.pasta, para: destino)
                pdfPartilhado = FicheiroPartilhado(url: destino)
            } catch {
                erro = "Não foi possível criar o PDF: \(error.localizedDescription)"
            }
        }
    }
    #endif

    // MARK: Edição

    private func comecarEdicao() {
        tab = .apontamentos
        originalEdicao = apontamentos
        houveEdicao = false
        estadoEdicao = "Guarda automaticamente"
        controlador.aoGravar = { await gravarRascunho() }
        controlador.definirEdicao(true)
        estudo.pastaEmEdicao = aula.pasta
    }

    /// Acabou a edição: as notas das ligações voltam a poder mexer nestes apontamentos (e repõem-se, se se apagaram).
    private func largarEdicaoNasLigacoes() {
        if estudo.pastaEmEdicao.map(aula.pasta.mesmoCaminho) ?? false { estudo.pastaEmEdicao = nil }
        estudo.aplicarNotas(aula.cadeira)
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
            estadoEdicao = "Não foi possível guardar: \(error.localizedDescription)"
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
        largarEdicaoNasLigacoes()
    }

    private func descartarEdicao() async {
        defer { largarEdicaoNasLigacoes() }
        controlador.definirEdicao(false)
        guard let original = originalEdicao else { return }
        if houveEdicao { try? Disco.escreverApontamentos(original, em: aula.pasta) }
        apontamentos = original
        controlador.repor(original)
        houveEdicao = false
    }

    #if os(macOS)
    /// Os PDFs são os slides do professor; o resto (Excel, Word…) fica nos materiais (`Materiais`).
    /// Copiar (de um ficheiro do iCloud ainda por descarregar) e converter imagens grandes faz-se fora do fio principal.
    private func juntarMateriaisProfessor(_ urls: [URL]) {
        let pasta = aula.pasta
        Task {
            let acedeu = urls.map { $0.startAccessingSecurityScopedResource() }
            defer { for (url, sim) in zip(urls, acedeu) where sim { url.stopAccessingSecurityScopedResource() } }
            let r = await Task.detached { Self.copiarMateriais(urls, para: pasta) }.value
            if !r.pdfs.isEmpty {
                do {
                    try library.atualizarMeta(em: pasta) { meta in
                        var nomes = meta.nomesPDFs ?? [:]
                        for pdf in r.pdfs { nomes[pdf.ficheiro] = pdf.nome }
                        meta.nomesPDFs = nomes
                    }
                } catch {
                    erro = error.localizedDescription
                }
                Task { await SlidesNosApontamentos.garantirPaginasEmFundo(em: pasta) }
            }
            // A aula aberta pode já ser outra.
            guard aula.pasta.mesmoCaminho(pasta) else { return }
            pdfsProfessor = Disco.pdfsProfessor(pasta)
            materiais = Materiais.nomes(em: pasta)
            if let falha = r.erro {
                erro = falha
                return
            }
            guard !r.pdfs.isEmpty || !r.outros.isEmpty else {
                erro = urls.count == 1 ? "Este ficheiro já está nesta aula." : "Estes ficheiros já estão nesta aula."
                return
            }
            // Com apontamentos já feitos sem estes materiais, propõe refazê-los para entrarem.
            if apontamentos != nil, !ocupada, definicoes.faltaParaGerar == nil, !controlador.editando {
                pdfsJuntados = r.pdfs.count
                materiaisJuntados = r.outros.count
                confirmarRegenerar = true
            } else {
                tab = .materiais
            }
        }
    }

    /// Os PDFs juntados, os outros materiais juntados e, se algum foi recusado, porquê (o que entrou antes fica).
    nonisolated private static func copiarMateriais(_ urls: [URL], para pasta: URL)
        -> (pdfs: [PDFProfessor], outros: [String], erro: String?) {
        var pdfs: [PDFProfessor] = [], outros: [String] = []
        do {
            let soPDFs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            if !soPDFs.isEmpty { pdfs = try Disco.juntarPDFsProfessor(soPDFs, em: pasta) }
            outros = try Materiais.juntar(urls.filter { $0.pathExtension.lowercased() != "pdf" }, em: pasta)
            return (pdfs, outros, nil)
        } catch {
            return (pdfs, outros, error.localizedDescription)
        }
    }

    /// Vai para o Lixo (recuperável).
    private func removerMaterial(_ nome: String) {
        do {
            try Materiais.remover(nome, em: aula.pasta)
            materiais = Materiais.nomes(em: aula.pasta)
        } catch {
            erro = error.localizedDescription
        }
    }

    /// Vai para o Lixo (recuperável).
    private func removerPDFProfessor(_ pdf: PDFProfessor) {
        do {
            try Disco.removerPDFProfessor(pdf, em: aula.pasta)
            try? library.atualizarMeta(em: aula.pasta) { $0.nomesPDFs?[pdf.ficheiro] = nil }
            pdfsProfessor.removeAll { $0.numero == pdf.numero }
        } catch {
            erro = error.localizedDescription
        }
    }

    #endif

    /// Com o aviso "Abrir próxima" e "Desfazer" quando há quem o mostre (a janela do Mac, o iPhone).
    private func marcarRevista(_ revista: Bool) {
        do {
            if let aviso {
                try aviso.marcar(aula, revista: revista, library: library, mostrar: true)
            } else {
                try library.definirRevista(revista, em: aula.pasta)
            }
        } catch {
            erro = error.localizedDescription
        }
    }

    #if os(macOS)
    private func religarVideo(_ url: URL) {
        let acedeu = url.startAccessingSecurityScopedResource()
        defer { if acedeu { url.stopAccessingSecurityScopedResource() } }
        do {
            try library.atualizarMeta(em: aula.pasta) { $0.video = VideoResolver.referencia(para: url) }
        } catch {
            erro = "Não foi possível guardar o novo caminho do vídeo: \(error.localizedDescription)"
        }
    }
    #endif
}

#if os(macOS)
/// Lê o texto dos apontamentos a chegar (nil sem geração em curso) só no seu próprio `body`.
private struct ComTextoEmCurso<Conteudo: View>: View {
    let job: Job?
    @ViewBuilder let conteudo: (String?) -> Conteudo

    var body: some View { conteudo(job?.textoEmCurso) }
}
#endif
