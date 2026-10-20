import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var direto
    @Environment(Navegacao.self) private var navegacao
    @Environment(Fichas.self) private var fichas
    @State private var pesquisa = ""
    @State private var preparar = false
    @Environment(Definicoes.self) private var definicoes
    @Environment(Atualizador.self) private var atualizador
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
            if let selecao, selecao.lastPathComponent == FichaCadeira.fichaMD,
               let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(selecao.deletingLastPathComponent()) }) {
                FichaCadeiraView(cadeira: cadeira).id(cadeira.pasta)
            } else if let selecao, let aula = library.aula(em: selecao) {
                AulaComPainel(aula: aula)
            } else {
                EcraInicial(aCaptar: direto.ativa, aoTranscrever: { configurarDireto = true }, aoEscolherVideo: { importar = true })
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        // Num Mac novo (ou se faltar o Claude Code ou o modelo), o assistente abre sozinho.
        .sheet(isPresented: $preparar) { PreparacaoView() }
        .onAppear { if PreparacaoView.faltaAlgo(definicoes) { preparar = true } }
        .onReceive(NotificationCenter.default.publisher(for: .abrirPreparacao)) { _ in preparar = true }
        .modifier(AvisosAtualizacao(ocupado: direto.ativa || fila.jobs.contains(where: \.ativo)))
        // Aulas antigas com "Sobre a cadeira" nos apontamentos, ou que ainda não entraram na ficha da cadeira.
        .task { fichas.atualizarTodas() }
        .task {
            #if DEBUG
            // `APONTAMENTOS_ATUALIZAR=1`: procura e instala logo (teste da atualização de ponta a ponta).
            if ProcessInfo.processInfo.environment["APONTAMENTOS_ATUALIZAR"] == "1" {
                await atualizador.procurar()
                await atualizador.instalar()
            }
            // `APONTAMENTOS_PROCURAR=1`: só procura, para testar o aviso e o botão "Atualizar agora".
            if ProcessInfo.processInfo.environment["APONTAMENTOS_PROCURAR"] == "1" {
                await atualizador.procurar()
            }
            #else
            await atualizador.procurarSeForAltura()
            #endif
        }
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
            definicoes.esquecerClaudeCode()
        }
        #if DEBUG
        // `APONTAMENTOS_IMPORTAR="<vídeo>|<cadeira>|<título>|<0/1 gerar apontamentos>"`: o mesmo que confirmar a folha.
        .task {
            // `APONTAMENTOS_SELECIONAR="<título>"`: abre essa aula, ou a ficha da cadeira com esse nome (capturas de ecrã sem clicar).
            if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECIONAR"] {
                selecao = library.cadeiras.flatMap(\.aulas).first { $0.meta.titulo == titulo }?.pasta
                    ?? library.cadeira(nome: titulo).map { FichaCadeira.url($0.pasta) }
            }
            // `APONTAMENTOS_REGENERAR="<título>"`: regenera os apontamentos dessa aula (o mesmo que o botão Regenerar).
            if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_REGENERAR"],
               let aula = library.cadeiras.flatMap(\.aulas).first(where: { $0.meta.titulo == titulo }) {
                selecao = aula.pasta
                fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: nil,
                                   gerarApontamentos: true, soApontamentos: true))
            }
            // `APONTAMENTOS_PREPARAR=1`: abre o assistente "Preparar o Recap".
            if ProcessInfo.processInfo.environment["APONTAMENTOS_PREPARAR"] == "1" { preparar = true }
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

/// Sem aula aberta: transcrever em direto é a ação principal; importar um vídeo fica em segundo plano
/// (largar um vídeo em qualquer sítio da janela continua a funcionar).
private struct EcraInicial: View {
    let aCaptar: Bool
    let aoTranscrever: () -> Void
    let aoEscolherVideo: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("Transcrever uma aula").font(.title.bold())
            Text("O Recap ouve a aula enquanto dá, ao vivo ou numa gravação no browser, e escreve os apontamentos no fim.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button(action: aoTranscrever) {
                Label(aCaptar ? "Já há uma aula a ser captada" : "Transcrever em direto…", systemImage: "record.circle")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(aCaptar)
            .padding(.top, 6)
            Text("⇧⌘L").font(.caption).foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Text("Tens o vídeo da aula? Larga-o aqui ou")
                Button("escolhe o ficheiro…", action: aoEscolherVideo).buttonStyle(.link)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 22)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A aula com o painel das perguntas à direita. Vive numa vista própria para o arrasto da divisória
/// só redesenhar isto, e não a janela inteira.
private struct AulaComPainel: View {
    let aula: Aula
    @Environment(Navegacao.self) private var navegacao
    @AppStorage("mostrarPerguntas") private var mostrarPerguntas = true
    @AppStorage("larguraPerguntas") private var larguraGuardada = 320.0
    /// A largura durante o arrasto; só no fim é gravada (gravar a cada pixel escrevia nas preferências dezenas de vezes por segundo).
    @State private var aArrastar: Double?

    var body: some View {
        // Uma divisão feita à mão e não o .inspector do SwiftUI: com a barra sempre visível em ecrã inteiro,
        // o inspector entrava num ciclo de layout e a app fechava. (O HSplitView abria o painel largo demais.)
        HStack(spacing: 0) {
            AulaDetailView(aula: aula).id(aula.pasta)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            if mostrarPerguntas {
                let largura = aArrastar ?? larguraGuardada
                DivisoriaPainel(largura: Binding(get: { largura }, set: { aArrastar = $0 })) {
                    if let final = aArrastar { larguraGuardada = final }
                    aArrastar = nil
                }
                PerguntasView(aula: aula) { segundos in
                    navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos)
                } aoClicarSeccao: { ligacao in
                    navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .apontamentos, seccao: ligacao)
                }
                .id(aula.pasta)
                .frame(width: largura)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Divisória arrastável à esquerda do painel das perguntas.
private struct DivisoriaPainel: View {
    @Binding var largura: Double
    let aoTerminar: () -> Void
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
                    .onEnded { _ in inicio = nil; aoTerminar() }
            )
    }
}

extension Notification.Name {
    /// Recap → Preparar o Recap…
    static let abrirPreparacao = Notification.Name("abrirPreparacao")
}

/// Os avisos do atualizador: versão nova, a instalar, já atualizado, erro.
private struct AvisosAtualizacao: ViewModifier {
    @Environment(Atualizador.self) private var atualizador
    /// Há uma captação ou um processamento em curso: atualizar agora perdia-o.
    let ocupado: Bool

    private var disponivel: String? { if case .disponivel(let v) = atualizador.estado { v } else { nil } }
    private var mensagem: String? {
        switch atualizador.estado {
        case .emDia: "O Recap está atualizado (versão \(Atualizador.versaoAtual))."
        case .falhou(let m): m
        default: nil
        }
    }
    private var aInstalar: Bool { if case .aInstalar = atualizador.estado { true } else { false } }

    func body(content: Content) -> some View {
        content
            .alert("Há uma versão nova do Recap", isPresented: Binding(get: { disponivel != nil }, set: { if !$0 { atualizador.dispensar() } }),
                   presenting: disponivel) { _ in
                Button("Atualizar agora") { Task { await atualizador.instalar() } }.disabled(ocupado)
                Button("Mais tarde", role: .cancel) { atualizador.dispensar() }
            } message: { versao in
                Text(ocupado
                     ? "Versão \(versao) (tens a \(Atualizador.versaoAtual)). Há uma aula a ser captada ou processada: atualiza quando terminar, em Recap → Procurar atualizações…"
                     : "Versão \(versao) (tens a \(Atualizador.versaoAtual)). O Recap fecha, atualiza-se e volta a abrir. As tuas aulas não são tocadas.")
            }
            .alert("Atualizações", isPresented: Binding(get: { mensagem != nil }, set: { if !$0 { atualizador.dispensar() } }), presenting: mensagem) { _ in
                Button("OK") { atualizador.dispensar() }
            } message: { Text($0) }
            .alert("O macOS não deixou o Recap atualizar-se",
                   isPresented: Binding(get: { atualizador.estado == .semPermissao }, set: { if !$0 { atualizador.dispensar() } })) {
                Button("Abrir Definições") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                    atualizador.dispensar()
                }
                Button("OK", role: .cancel) { atualizador.dispensar() }
            } message: {
                Text("Em Definições do Sistema → Privacidade e Segurança → Gestão de apps, ativa o Recap e volta a tentar em Recap → Procurar atualizações… Continuas na versão \(Atualizador.versaoAtual).")
            }
            .overlay {
                if aInstalar {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("A atualizar o Recap…")
                    }
                    .padding(28)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
    }
}
