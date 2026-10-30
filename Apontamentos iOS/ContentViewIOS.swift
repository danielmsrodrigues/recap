import SwiftUI

/// A janela do iPad e do iPhone: só leitura dos apontamentos, com o painel Estudo à mão. No iPhone, separadores
/// (`TelefoneView`); no iPad (e com largura de iPad), as três colunas do Mac (`TabletView`).
struct ContentViewIOS: View {
    @State private var library: Library
    @State private var definicoes: Definicoes
    @State private var estudo: Estudo
    @State private var fichas: Fichas
    @State private var navegacao = Navegacao()
    @State private var verDefinicoes = false
    /// `APONTAMENTOS_SELECIONAR="<título>"` (só em DEBUG): abre essa aula, para capturas e testes.
    @State private var inicial: URL?
    @Environment(\.scenePhase) private var fase
    @Environment(\.horizontalSizeClass) private var largura

    init(raiz: URL) {
        let definicoes = Definicoes()
        if let p = DefinicoesPartilhadas.ler(raiz: raiz) { definicoes.aplicar(p) }
        let library = Library(raiz: raiz, organizacao: definicoes.organizacao,
                              iniciosPeriodos: definicoes.iniciosPeriodos, duracaoCurso: definicoes.duracaoCurso)
        _definicoes = State(initialValue: definicoes)
        _library = State(initialValue: library)
        _estudo = State(initialValue: Estudo(library: library, definicoes: definicoes))
        _fichas = State(initialValue: Fichas(library: library, definicoes: definicoes))
        #if DEBUG
        if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECIONAR"] {
            _inicial = State(initialValue: library.cadeiras.flatMap(\.aulas).first { $0.meta.titulo == titulo }?.pasta)
        }
        #endif
    }

    var body: some View {
        Group {
            if largura == .compact {
                TelefoneView(inicial: inicial)
            } else {
                TabletView(inicial: inicial)
            }
        }
        .imagemEmGrande(navegacao)
        .environment(library)
        .environment(definicoes)
        .environment(estudo)
        .environment(fichas)
        .environment(navegacao)
        .task { library.vigiar() }
        .refreshable { atualizar() }
        .onChange(of: fase) { if fase == .active { atualizar() } }
        .onReceive(NotificationCenter.default.publisher(for: .abrirDefinicoes)) { _ in verDefinicoes = true }
        .sheet(isPresented: $verDefinicoes) {
            DefinicoesIOS()
                .environment(library)
                .environment(definicoes)
        }
    }

    /// As preferências podem ter mudado no Mac desde a última vez, e a pasta também.
    private func atualizar() {
        if let p = DefinicoesPartilhadas.ler(raiz: library.raiz) {
            definicoes.aplicar(p)
            library.duracaoCurso = definicoes.duracaoCurso
            library.organizacao = definicoes.organizacao
            library.iniciosPeriodos = definicoes.iniciosPeriodos
        }
        library.recarregar(forcar: true)
    }
}
