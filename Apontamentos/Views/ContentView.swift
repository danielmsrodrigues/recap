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
    /// A lista do meio (escolhida na barra lateral).
    @State private var filtro: FiltroAulas = .inicio
    /// nil = o semestre mais recente. Não fica guardado: ao abrir, a app mostra sempre o semestre em curso.
    @State private var semestre: Semestre?
    @State private var aviso = AvisoRevista()

    static let extensoes: Set<String> = ["mp4", "mov", "m4v", "mkv"]
    static let tiposVideo: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie] + [UTType(filenameExtension: "mkv")].compactMap { $0 }

    private var barraLateral: some View {
        BarraLateral(filtro: $filtro, semestre: $semestre, aEditarCadeira: $aEditarCadeira, aoAbrirAula: { selecao = $0 }) {
            criarCadeira = true
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }

    /// Três colunas, como no Notas e no Mail: as listas e as cadeiras, as aulas, a aula.
    private var tresColunas: some View {
        NavigationSplitView {
            barraLateral
        } content: {
            Group {
                if filtro == .exame {
                    // Os avisos de exame do semestre; um clique abre a aula nesse minuto.
                    ListaPistasExame(cadeiras: library.cadeiras(no: semestre))
                        .navigationTitle("Sai no exame")
                        .toolbar { ToolbarItem { BotaoTranscrever { configurarDireto = true } } }
                } else {
                    ListaAulas(filtro: filtro, semestre: semestre, selecao: $selecao, pesquisa: $pesquisa) { configurarDireto = true }
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 440)
        } detail: {
            if let selecao, selecao.lastPathComponent == FichaCadeira.fichaMD,
               let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(selecao.deletingLastPathComponent()) }) {
                FichaComPerguntas(cadeira: cadeira).id(cadeira.pasta)
                    .navigationSplitViewColumnWidth(min: 600, ideal: 1000)
            } else if let selecao, let aula = library.aula(em: selecao) {
                AulaComPainel(aula: aula)
                    .navigationSplitViewColumnWidth(min: 600, ideal: 1000)
            } else {
                Inicio(semestre: semestre, aCaptar: direto.ativa,
                       aoTranscrever: { configurarDireto = true }, aoEscolherVideo: { importar = true },
                       aoAbrir: { selecao = $0 }, aoVerPorRever: { filtro = .porRever })
                    .navigationSplitViewColumnWidth(min: 520, ideal: 900)
            }
        }
    }

    var body: some View {
        Group {
            if filtro == .calendario {
                // Duas colunas: o mês ocupa o lugar da lista e da aula, como no design. Clicar numa aula abre-a.
                NavigationSplitView {
                    barraLateral
                } detail: {
                    CalendarioView(aoTranscrever: { configurarDireto = true }) { pasta in
                        // A aula que já estava escolhida não muda a seleção: sai-se do calendário à mão.
                        if selecao.map({ $0.mesmoCaminho(pasta) }) == true { filtro = .todas } else { selecao = pasta }
                    }
                        .navigationSplitViewColumnWidth(min: 700, ideal: 1100)
                }
            } else {
                tresColunas
            }
        }
        // Sem mínimo, a lista do meio podia ficar com a janela toda e o Início, espremido, com uma letra por linha.
        .frame(minWidth: 1000, minHeight: 600)
        // "Início" fecha a aula; uma cadeira abre "Sobre a cadeira", como no design.
        .onChange(of: filtro) { _, novo in
            switch novo {
            case .inicio: selecao = nil
            case .cadeira(let pasta):
                // Com uma aula desta cadeira aberta (por exemplo, depois de lhe mudar o nome), fica a aula.
                if !(selecao?.path.hasPrefix(pasta.path + "/") ?? false) { selecao = FichaCadeira.url(pasta) }
            default: break
            }
        }
        // Uma aula aberta pela pesquisa, por um link ou pelo calendário: sai do Início ou do calendário, e o semestre
        // passa a ser o dela.
        .onChange(of: selecao) { _, nova in
            guard let nova else { return }
            if filtro == .inicio || filtro == .calendario { filtro = .todas }
            if let cadeira = library.cadeiras.first(where: { nova.path.hasPrefix($0.pasta.path + "/") }),
               cadeira.semestre != (semestre ?? library.semestres.first) {
                semestre = cadeira.semestre
            }
        }
        .overlay(alignment: .bottom) {
            if let atual = aviso.atual {
                VistaAvisoRevista(aviso: atual) { proxima in
                    aviso.fechar()
                    selecao = proxima.pasta
                } aoDesfazer: {
                    do { try aviso.desfazer(library) } catch { erro = error.localizedDescription }
                }
                .frame(maxWidth: 560)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(aviso)
        .imagemEmGrande(navegacao)
        // Depois de uma atualização, uma vez: o que há de novo.
        .modifier(ComNovidades())
        // Num Mac novo (ou se faltar o Claude Code ou o modelo), o assistente abre sozinho.
        .sheet(isPresented: $preparar) { PreparacaoView() }
        .onAppear { if PreparacaoView.faltaAlgo(definicoes) { preparar = true } }
        .onReceive(NotificationCenter.default.publisher(for: .abrirPreparacao)) { _ in preparar = true }
        .modifier(AvisosAtualizacao(ocupado: direto.ativa || fila.jobs.contains(where: \.ativo)))
        // Aulas antigas com "Sobre a cadeira" nos apontamentos, ou que ainda não entraram na ficha da cadeira.
        .task { fichas.atualizarTodas() }
        // O iPad e o iPhone leem a pasta pelo iCloud Drive: o que muda lá aparece aqui sem voltar à app.
        .task { library.vigiar() }
        .onChange(of: PartilhaDefinicoes(definicoes: definicoes.partilhadas, raiz: library.raiz), initial: true) { _, p in
            try? DefinicoesPartilhadas.escrever(p.definicoes, raiz: p.raiz)
        }
        .task {
            #if DEBUG
            // `APONTAMENTOS_ATUALIZAR=1`: procura e instala logo (teste da atualização de ponta a ponta).
            if ProcessInfo.processInfo.environment["APONTAMENTOS_ATUALIZAR"] == "1" {
                await atualizador.procurar()
                await atualizador.instalar()
            }
            // `APONTAMENTOS_ATUALIZACAO_PROCURAR=1`: só procura a versão nova, para testar o aviso e o botão "Atualizar agora".
            if ProcessInfo.processInfo.environment["APONTAMENTOS_ATUALIZACAO_PROCURAR"] == "1" {
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
        // O menu Ficheiro: Transcrever em direto (⇧⌘L), Importar vídeo (⌘O) e Nova cadeira.
        .onReceive(NotificationCenter.default.publisher(for: .transcreverEmDireto)) { _ in configurarDireto = true }
        .onReceive(NotificationCenter.default.publisher(for: .importarVideo)) { _ in importar = true }
        .onReceive(NotificationCenter.default.publisher(for: .novaCadeira)) { _ in criarCadeira = true }
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
            }
        }
        .sheet(item: $aEditarCadeira) { cadeira in
            CadeiraSheet(cadeira: cadeira) { antiga, nova in
                // A aula aberta e a cadeira escolhida mudaram de pasta com a cadeira: a seleção e a lista acompanham.
                if let s = selecao, s.path.hasPrefix(antiga.path + "/") {
                    selecao = nova.appending(path: s.lastPathComponent, directoryHint: .isDirectory)
                }
                if case .cadeira(let pasta) = filtro, pasta.mesmoCaminho(antiga) { filtro = .cadeira(nova) }
            }
        }
        .sheet(isPresented: $criarCadeira) { CadeiraSheet(cadeira: nil) }
        .sheet(isPresented: $configurarDireto) { ConfigDiretoSheet() }
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
            // `APONTAMENTOS_CALENDARIO=1`: abre o calendário.
            if ProcessInfo.processInfo.environment["APONTAMENTOS_CALENDARIO"] == "1" { filtro = .calendario }
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

/// Sem aula aberta: o dia, o que falta rever, e as duas maneiras de juntar uma aula (em direto, ou largando o vídeo
/// em qualquer sítio da janela).
private struct Inicio: View {
    @Environment(Library.self) private var library
    let semestre: Semestre?
    let aCaptar: Bool
    let aoTranscrever: () -> Void
    let aoEscolherVideo: () -> Void
    let aoAbrir: (URL) -> Void
    let aoVerPorRever: () -> Void

    var body: some View {
        let porRever = Revisao.porRever(library.cadeiras(no: semestre))
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    let dia = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_PT")))
                    Text(dia.prefix(1).uppercased() + dia.dropFirst())
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(porRever.isEmpty ? "Está tudo revisto" : porRever.count == 1 ? "Tens 1 aula por rever" : "Tens \(porRever.count) aulas por rever")
                        .font(.largeTitle.bold())
                }
                // Lado a lado: a coluna tem largura mínima, por isso cabem sempre.
                HStack(alignment: .top, spacing: 12) { cartoes }
                if !porRever.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Por rever").font(.title3.bold())
                            Spacer()
                            Button("Ver todas", action: aoVerPorRever).buttonStyle(.link)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(porRever.prefix(5).enumerated()), id: \.element.id) { i, aula in
                                if i > 0 { Divider().padding(.leading, 31) }
                                Button { aoAbrir(aula.pasta) } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 2).fill(library.cor(aula.cadeira)).frame(width: 7, height: 7)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(aula.meta.titulo).lineLimit(1)
                                            Text("\(aula.cadeira) · Aula \(library.numeroDaAula(aula)) · \(DataAula.curta(aula.meta.data))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        // Sem botões nesta vista: o espaço fica à direita e o "Transcrever" da lista não foge para a ponta da janela.
        .toolbar { ToolbarSpacer(.flexible) }
    }

    /// O cartão "Transcrever em direto" e o de largar o vídeo.
    @ViewBuilder private var cartoes: some View {
        Button(action: aoTranscrever) {
            VStack(alignment: .leading, spacing: 6) {
                Label(aCaptar ? "Já há uma aula em direto" : "Transcrever em direto…", systemImage: "record.circle")
                    .font(.title3.bold())
                Text("Ouve a aula ao vivo ou uma gravação no browser e escreve os apontamentos no fim.")
                    .font(.callout).opacity(0.85)
                Text("⇧⌘L").font(.caption).opacity(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(18)
            .background(Color.accentColor, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(aCaptar)
        VStack(alignment: .leading, spacing: 6) {
            Text("Tens o vídeo da aula?").font(.title3.bold())
            HStack(spacing: 4) {
                Text("Larga-o aqui ou").foregroundStyle(.secondary)
                Button("escolhe o ficheiro…", action: aoEscolherVideo).buttonStyle(.link)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}

/// A aula com o painel das perguntas à direita. Vive numa vista própria para o arrasto da divisória
/// só redesenhar isto, e não a janela inteira.
private struct AulaComPainel: View {
    let aula: Aula
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    @AppStorage("mostrarEstudo") private var mostrarEstudo = true
    @AppStorage("larguraPerguntas") private var larguraGuardada = 320.0
    /// A largura durante o arrasto; só no fim é gravada (gravar a cada pixel escrevia nas preferências dezenas de vezes por segundo).
    @State private var aArrastar: Double?

    var body: some View {
        // Uma divisão feita à mão e não o .inspector do SwiftUI: com a barra sempre visível em ecrã inteiro,
        // o inspector entrava num ciclo de layout e a app fechava. (O HSplitView abria o painel largo demais.)
        HStack(spacing: 0) {
            AulaDetailView(aula: aula).id(aula.pasta)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            if mostrarEstudo {
                // Com três colunas, um painel largo (até 620 antes) já não cabia e o macOS escondia a barra lateral.
                let largura = min(aArrastar ?? larguraGuardada, DivisoriaPainel.limites.upperBound)
                DivisoriaPainel(largura: Binding(get: { largura }, set: { aArrastar = $0 })) {
                    if let final = aArrastar { larguraGuardada = final }
                    aArrastar = nil
                }
                PainelEstudo(aula: aula) { segundos in
                    navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos)
                } aoClicarSeccao: { ligacao in
                    navegacao.destino = estudo.destino(ligacao, aPartirDe: aula)
                } aoAbrirAula: { pasta in
                    navegacao.destino = DestinoAula(pasta: pasta, separador: .apontamentos)
                }
                .id(aula.pasta)
                .frame(width: largura)
                .frame(maxHeight: .infinity)
                .clipped()
            }
        }
    }
}

/// Divisória arrastável à esquerda do painel das perguntas.
private struct DivisoriaPainel: View {
    @Binding var largura: Double
    let aoTerminar: () -> Void
    @State private var inicio: Double?
    static let limites = 260.0...460.0

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
    /// Ficheiro → Transcrever em direto…, Importar vídeo…, Nova cadeira…
    static let transcreverEmDireto = Notification.Name("transcreverEmDireto")
    static let importarVideo = Notification.Name("importarVideo")
    static let novaCadeira = Notification.Name("novaCadeira")
    /// Editar → Procurar em todas as aulas (⌥⌘F): o cursor vai para o campo no topo da lista.
    static let procurarEmTodasAsAulas = Notification.Name("procurarEmTodasAsAulas")
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
                     ? "Versão \(versao) (tens a \(Atualizador.versaoAtual)). Há uma aula em direto ou a processar: atualiza quando terminar, em Recap → Procurar atualizações…"
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

/// O que o iPad e o iPhone precisam de saber das Definições, e onde o escrever.
private struct PartilhaDefinicoes: Equatable {
    var definicoes: DefinicoesPartilhadas
    var raiz: URL
}

/// "Sobre a cadeira" com o painel Perguntar à cadeira ao lado (escondido e mostrado pelo botão da barra).
private struct FichaComPerguntas: View {
    let cadeira: Cadeira
    @AppStorage("perguntarCadeira") private var mostrar = true

    var body: some View {
        HStack(spacing: 0) {
            FichaCadeiraView(cadeira: cadeira)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            if mostrar {
                Divider()
                PerguntasCadeiraView(cadeira: cadeira)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $mostrar) {
                    Label("Perguntar à cadeira", systemImage: "bubble.left.and.text.bubble.right")
                }
                .help("Perguntas sobre a cadeira inteira: todas as aulas e a ficha")
            }
        }
    }
}
