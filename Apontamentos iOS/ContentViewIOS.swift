import SwiftUI

/// A janela do iPad e do iPhone: o que não depende do curso, à volta do curso aberto. O `.id` refaz só o conteúdo ao
/// trocar de curso, e o que estiver a caminho do Mac continua a ser seguido.
struct ContentViewIOS: View {
    @State private var biblioteca: Biblioteca
    @State private var definicoes: Definicoes
    @State private var verDefinicoes = false
    @State private var verCursos = false
    @Environment(\.scenePhase) private var fase

    init(raiz: URL) {
        let definicoes = Definicoes()
        _definicoes = State(initialValue: definicoes)
        _biblioteca = State(initialValue: Biblioteca(raiz: raiz, definicoes: definicoes))
    }

    var body: some View {
        let curso = biblioteca.ativo
        ConteudoCursoIOS(library: curso.library)
            .id(curso.id)
            // Depois de uma atualização pelo TestFlight, uma vez: o que há de novo.
            .modifier(ComNovidades())
            .environment(biblioteca)
            .environment(curso.library)
            .environment(definicoes)
            .environment(curso.estudo)
            .environment(curso.fichas)
            .task { biblioteca.vigiar() }
            .task(id: curso.id) { curso.library.vigiar() }
            // Os cursos, a pasta e as preferências do curso podem ter mudado no Mac desde a última vez.
            .onChange(of: fase) {
                guard fase == .active else { return }
                biblioteca.recarregarCursos()
                biblioteca.ativo.library.recarregar(forcar: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .abrirDefinicoes)) { _ in verDefinicoes = true }
            .onReceive(NotificationCenter.default.publisher(for: .abrirCursos)) { _ in verCursos = true }
            .sheet(isPresented: $verDefinicoes) {
                DefinicoesIOS()
                    .environment(biblioteca)
                    .environment(definicoes)
            }
            .sheet(isPresented: $verCursos) {
                CatalogoCursosView()
                    .environment(biblioteca)
            }
    }
}

/// O curso aberto: só leitura dos apontamentos, com o painel Estudo ao lado. No iPhone, separadores (`TelefoneView`);
/// no iPad, as três colunas do Mac (`TabletView`).
private struct ConteudoCursoIOS: View {
    @State private var navegacao = Navegacao()
    /// `APONTAMENTOS_SELECIONAR="<título>"` (só em DEBUG): abre essa aula, para capturas e testes.
    @State private var inicial: URL?

    init(library: Library) {
        #if DEBUG
        if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECIONAR"] {
            _inicial = State(initialValue: library.cadeiras.flatMap(\.aulas).first { $0.meta.titulo == titulo }?.pasta)
        }
        #endif
    }

    var body: some View {
        Group {
            // Pelo aparelho e não pela largura: um iPhone grande deitado, ou o iPad em Split View, mudavam de
            // vista a meio e perdia-se onde se estava. O NavigationSplitView do iPad já se recolhe quando é estreito.
            if UIDevice.current.userInterfaceIdiom == .phone {
                TelefoneView(inicial: inicial)
            } else {
                TabletView(inicial: inicial)
            }
        }
        .imagemEmGrande(navegacao)
        .environment(navegacao)
    }
}
