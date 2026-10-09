import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var direto
    @Environment(Navegacao.self) private var navegacao
    @State private var pesquisa = ""
    /// Painel das perguntas à aula, à direita.
    @AppStorage("mostrarPerguntas") private var mostrarPerguntas = true
    @AppStorage("larguraPerguntas") private var larguraPerguntas = 320.0

    @State private var selecao: URL?
    @State private var videosPendentes: [URL] = []
    @State private var atual: VideoPendente?
    @State private var aEditarCadeira: Cadeira?
    @State private var aArrastar = false
    @State private var importar = false
    @State private var erro: String?
    @State private var configurarDireto = false
    @State private var criarCadeira = false
    @State private var nomeCadeira = ""

    static let extensoes: Set<String> = ["mp4", "mov", "m4v", "mkv"]
    static let tiposVideo: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie] + [UTType(filenameExtension: "mkv")].compactMap { $0 }

    var body: some View {
        NavigationSplitView {
            Group {
                if pesquisa.trimmingCharacters(in: .whitespaces).isEmpty {
                    SidebarView(selecao: $selecao, aEditarCadeira: $aEditarCadeira)
                } else {
                    ResultadosPesquisaView(termo: pesquisa)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            .searchable(text: $pesquisa, placement: .sidebar, prompt: "Pesquisar em todas as aulas")
        } detail: {
            if let selecao, let aula = library.aula(em: selecao) {
                // Uma divisão feita à mão e não o .inspector do SwiftUI: com a barra sempre visível em ecrã inteiro,
                // o inspector entrava num ciclo de layout e a app fechava. (O HSplitView abria o painel largo demais.)
                HStack(spacing: 0) {
                    AulaDetailView(aula: aula).id(aula.pasta)
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    if mostrarPerguntas {
                        DivisoriaPainel(largura: $larguraPerguntas)
                        PerguntasView(aula: aula) { segundos in
                            navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos)
                        }
                        .id(aula.pasta)
                        .frame(width: larguraPerguntas)
                        .frame(maxHeight: .infinity)
                    }
                }
            } else {
                DropZoneView { importar = true }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        // Resultados da pesquisa e links entre aulas: a aula abre e trata do resto (separador, momento, realce).
        .onChange(of: navegacao.destino) { _, destino in
            // O URL canónico da aula: o do link pode vir noutra normalização Unicode e a lista não o reconhecia.
            if let destino, !(selecao?.mesmoCaminho(destino.pasta) ?? false) { selecao = library.aula(em: destino.pasta)?.pasta ?? destino.pasta }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu("Adicionar", systemImage: "plus") {
                    Button("Transcrever em direto…") { configurarDireto = true }.keyboardShortcut("l", modifiers: [.command, .shift])
                    Button("Importar vídeo…") { importar = true }.keyboardShortcut("o")
                    Button("Nova cadeira…") { nomeCadeira = ""; criarCadeira = true }
                }
                .help("Importar vídeos de aulas ou criar uma cadeira")
            }
            // Em ecrã inteiro a barra de menus do Mac esconde-se; assim as definições continuam à mão.
            ToolbarItem(placement: .navigation) {
                SettingsLink { Label("Definições", systemImage: "gearshape") }
                    .help("Definições (⌘,)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            receber(urls)
            return true
        } isTargeted: { aArrastar = $0 }
        .overlay {
            if aArrastar {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(.tint.opacity(0.06), in: .rect(cornerRadius: 14))
                    .overlay { Label("Larga para adicionar à fila", systemImage: "film.stack").font(.title2) }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .fileImporter(isPresented: $importar, allowedContentTypes: Self.tiposVideo, allowsMultipleSelection: true) { resultado in
            if case .success(let urls) = resultado { receber(urls) }
        }
        .sheet(item: $atual, onDismiss: avancar) { pendente in
            NovaAulaSheet(video: pendente.url, restantes: videosPendentes.count) { cadeira, titulo, data, gerar in
                Task { await criar(video: pendente.url, cadeira: cadeira, titulo: titulo, data: data, gerar: gerar) }
            } aoSaltar: {}
        }
        .sheet(item: $aEditarCadeira) { CadeiraSheet(cadeira: $0) }
        .sheet(isPresented: $configurarDireto) { ConfigDiretoSheet() }
        .alert("Nova cadeira", isPresented: $criarCadeira) {
            TextField("Nome", text: $nomeCadeira, prompt: Text("ex.: Álgebra Lineal"))
            Button("Criar") {
                let nome = nomeCadeira.trimmingCharacters(in: .whitespaces)
                guard !nome.isEmpty else { return }
                do { try library.criarCadeira(nome: nome) } catch { erro = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Não foi possível adicionar o vídeo", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") { erro = nil }
        } message: { Text($0) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.recarregar()
        }
        #if DEBUG
        // `APONTAMENTOS_IMPORTAR="<vídeo>|<cadeira>|<título>|<0/1 gerar apontamentos>"`: o mesmo que confirmar a folha.
        .task {
            // `APONTAMENTOS_SELECIONAR="<título>"`: abre essa aula (capturas de ecrã sem clicar).
            if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECIONAR"] {
                selecao = library.cadeiras.flatMap(\.aulas).first { $0.meta.titulo == titulo }?.pasta
            }
            // `APONTAMENTOS_PESQUISA="<texto>"`: pesquisa em todas as aulas.
            if let texto = ProcessInfo.processInfo.environment["APONTAMENTOS_PESQUISA"] { pesquisa = texto }
            // `APONTAMENTOS_DIRETO=1`: abre a folha "Transcrever em direto".
            if ProcessInfo.processInfo.environment["APONTAMENTOS_DIRETO"] == "1" { configurarDireto = true }
            // `APONTAMENTOS_DIRETO_AUTO="<início do título da janela>|<segundos>"`: capta essa janela e descarta no fim
            // (para medir a memória durante uma captação; usar com `APONTAMENTOS_RAIZ` numa pasta temporária).
            let auto = ProcessInfo.processInfo.environment["APONTAMENTOS_DIRETO_AUTO"]?.components(separatedBy: "|") ?? []
            if auto.count == 2, let segundos = Double(auto[1]),
               let fonte = try? await CapturaAudio.fontes().first(where: { $0.tituloJanela.hasPrefix(auto[0]) }) {
                await direto.comecar(fonte: fonte, cadeira: "Teste", titulo: "Medição", data: .now, velocidade: 1,
                                     gerarApontamentos: false, capturarSlides: true, library: library, fila: fila)
                try? await Task.sleep(for: .seconds(segundos))
                await direto.descartar()
            }
            let partes = ProcessInfo.processInfo.environment["APONTAMENTOS_IMPORTAR"]?.components(separatedBy: "|") ?? []
            guard partes.count == 4 else { return }
            await criar(video: URL(fileURLWithPath: partes[0]), cadeira: partes[1], titulo: partes[2], data: .now, gerar: partes[3] == "1")
        }
        #endif
    }

    private func receber(_ urls: [URL]) {
        let videos = urls.filter { Self.extensoes.contains($0.pathExtension.lowercased()) }
        let ignorados = urls.count - videos.count
        if ignorados > 0 {
            erro = "Só são aceites vídeos .mp4, .mov, .m4v ou .mkv (\(ignorados) ficheiro(s) ignorado(s))."
        }
        videosPendentes.append(contentsOf: videos)
        if atual == nil { avancar() }
    }

    private func avancar() {
        guard atual == nil, !videosPendentes.isEmpty else { return }
        atual = VideoPendente(url: videosPendentes.removeFirst())
    }

    private func criar(video: URL, cadeira: String, titulo: String, data: Date, gerar: Bool) async {
        do {
            // Antes de criar a pasta, confirma que o macOS consegue ler o vídeo (os .mkv costumam falhar).
            try await VideoResolver.comAcesso(video) { try await AudioExtractor.validar(video) }
            let pasta = try library.criarAula(cadeira: cadeira, titulo: titulo, data: data, video: video)
            fila.adicionar(Job(pastaAula: pasta, titulo: titulo, video: video, gerarApontamentos: gerar))
            if selecao == nil { selecao = pasta }
        } catch {
            erro = "\(video.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

private struct VideoPendente: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct DropZoneView: View {
    let aoEscolher: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Larga aqui a gravação de uma aula").font(.title2)
            Text("Vídeos .mp4, .mov ou .mkv. Podes largar vários; são processados um de cada vez.")
                .foregroundStyle(.secondary)
            Button("Escolher vídeo…", action: aoEscolher)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(24)
        }
    }
}

/// Divisória arrastável à esquerda do painel das perguntas (a largura fica guardada).
private struct DivisoriaPainel: View {
    @Binding var largura: Double
    @State private var inicio: Double?
    static let limites = 260.0...620.0

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(.rect)
            .onHover { dentro in
                if dentro { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        let base = inicio ?? largura
                        inicio = base
                        // Arrastar para a esquerda alarga o painel.
                        largura = min(Self.limites.upperBound, max(Self.limites.lowerBound, base - g.translation.width))
                    }
                    .onEnded { _ in inicio = nil }
            )
    }
}
