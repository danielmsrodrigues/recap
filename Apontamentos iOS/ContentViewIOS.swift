import SwiftUI

/// A janela do iPad e do iPhone: as mesmas cadeiras, aulas e ficha da cadeira do Mac, sem a captura.
/// No iPhone a divisão fica em pilha; o painel Estudo é um inspector (no iPhone, uma folha).
struct ContentViewIOS: View {
    @State private var library: Library
    @State private var definicoes: Definicoes
    @State private var estudo: Estudo
    @State private var fichas: Fichas
    @State private var navegacao = Navegacao()
    @State private var selecao: URL?
    @State private var pesquisa = ""
    @State private var aEditarCadeira: Cadeira?
    @State private var verDefinicoes = false
    @Environment(\.scenePhase) private var fase

    init(raiz: URL) {
        let definicoes = Definicoes()
        if let p = DefinicoesPartilhadas.ler(raiz: raiz) { definicoes.aplicar(p) }
        let library = Library(raiz: raiz, organizacao: definicoes.organizacao,
                              iniciosPeriodos: definicoes.iniciosPeriodos, duracaoCurso: definicoes.duracaoCurso)
        _definicoes = State(initialValue: definicoes)
        _library = State(initialValue: library)
        _estudo = State(initialValue: Estudo(library: library, definicoes: definicoes))
        _fichas = State(initialValue: Fichas(library: library, definicoes: definicoes))
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if pesquisa.trimmingCharacters(in: .whitespaces).isEmpty {
                    SidebarView(selecao: $selecao, aEditarCadeira: $aEditarCadeira)
                } else {
                    ResultadosPesquisaView(termo: pesquisa)
                }
            }
            .navigationTitle("Aulas")
            .searchable(text: $pesquisa, placement: .sidebar, prompt: "Procurar em todas as aulas")
            .refreshable { atualizar() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Definições", systemImage: "gearshape") { verDefinicoes = true }
                }
            }
        } detail: {
            if let selecao, selecao.lastPathComponent == FichaCadeira.fichaMD,
               let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(selecao.deletingLastPathComponent()) }) {
                FichaCadeiraView(cadeira: cadeira).id(cadeira.pasta)
                    .navigationBarTitleDisplayMode(.inline)
            } else if let selecao, let aula = library.aula(em: selecao) {
                AulaComPainelIOS(aula: aula).id(aula.pasta)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Escolhe uma aula", systemImage: "book",
                                       description: Text("As aulas gravadas no Mac aparecem aqui pelo iCloud Drive."))
            }
        }
        .imagemEmGrande(navegacao)
        .environment(library)
        .environment(definicoes)
        .environment(estudo)
        .environment(fichas)
        .environment(navegacao)
        .task { library.vigiar() }
        .onChange(of: fase) { if fase == .active { atualizar() } }
        // Resultados da pesquisa e links entre aulas: a aula abre e trata do resto (separador, momento, realce).
        .onChange(of: navegacao.destino) { _, destino in
            if let destino, !(selecao?.mesmoCaminho(destino.pasta) ?? false) { selecao = library.aula(em: destino.pasta)?.pasta ?? destino.pasta }
        }
        .onReceive(NotificationCenter.default.publisher(for: .abrirDefinicoes)) { _ in verDefinicoes = true }
        #if DEBUG
        .task {
            // `APONTAMENTOS_SELECIONAR="<título>"`, como no Mac: abre essa aula, ou a ficha da cadeira com esse nome.
            if let titulo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECIONAR"] {
                selecao = library.cadeiras.flatMap(\.aulas).first { $0.meta.titulo == titulo }?.pasta
                    ?? library.cadeira(nome: titulo).map { FichaCadeira.url($0.pasta) }
            }
            if ProcessInfo.processInfo.environment["APONTAMENTOS_ESTUDO"] == "1" { UserDefaults.standard.set(true, forKey: "mostrarEstudo") }
        }
        #endif
        .sheet(item: $aEditarCadeira) { cadeira in
            CadeiraSheet(cadeira: cadeira) { antiga, nova in
                if let s = selecao, s.path.hasPrefix(antiga.path + "/") {
                    selecao = nova.appending(path: s.lastPathComponent, directoryHint: .isDirectory)
                }
            }
            .environment(library)
            .environment(definicoes)
        }
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

/// A aula com o painel Estudo (perguntas, exercícios, ligações) num inspector: ao lado no iPad, numa folha no iPhone.
private struct AulaComPainelIOS: View {
    let aula: Aula
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    /// O valor inicial vem do `register(defaults:)` da app (aberto no iPad, fechado no iPhone).
    @AppStorage("mostrarEstudo") private var mostrarEstudo = false

    var body: some View {
        AulaDetailView(aula: aula)
            .inspector(isPresented: $mostrarEstudo) {
                PainelEstudo(aula: aula) { segundos in
                    navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos)
                } aoClicarSeccao: { ligacao in
                    navegacao.destino = estudo.destino(ligacao, aPartirDe: aula)
                } aoAbrirAula: { pasta in
                    navegacao.destino = DestinoAula(pasta: pasta, separador: .apontamentos)
                }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 560)
            }
    }
}
