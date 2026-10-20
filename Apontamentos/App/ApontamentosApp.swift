import SwiftUI

@main
struct ApontamentosApp: App {
    @State private var library: Library
    @State private var definicoes: Definicoes
    @State private var fila: ProcessingQueue
    @State private var direto = SessaoDireto()
    @State private var estudo: Estudo
    @State private var fichas: Fichas
    @State private var navegacao = Navegacao()
    @State private var atualizador = Atualizador()

    init() {
        let definicoes = Definicoes()
        let library = Library(raiz: definicoes.raizAulas, organizacao: definicoes.organizacao)
        _library = State(initialValue: library)
        _definicoes = State(initialValue: definicoes)
        let fichas = Fichas(library: library, definicoes: definicoes)
        _fichas = State(initialValue: fichas)
        _fila = State(initialValue: ProcessingQueue(runner: PipelineRunner(library: library, definicoes: definicoes, fichas: fichas)))
        _estudo = State(initialValue: Estudo(library: library, definicoes: definicoes))
        // O painel Estudo abre sempre ao arrancar; fechá-lo só vale até sair da app.
        UserDefaults.standard.set(true, forKey: "mostrarEstudo")
    }

    var body: some Scene {
        Window("Recap", id: "principal") {
            ContentView()
                // Em ecrã inteiro, a barra de ferramentas fica sempre visível (por defeito só aparecia ao passar o rato no topo).
                .windowToolbarFullScreenVisibility(.visible)
                .environment(library)
                .environment(definicoes)
                .environment(fila)
                .environment(direto)
                .environment(estudo)
                .environment(fichas)
                .environment(navegacao)
                .environment(atualizador)
        }

        Window("Em direto", id: "direto") {
            DiretoView()
                .environment(direto)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.topTrailing)

        // Ícone na barra de menus só enquanto uma aula está a ser captada: vê-se mesmo com o Chrome à frente.
        MenuBarExtra(isInserted: Binding(get: { direto.ativa }, set: { _ in })) {
            DiretoMenu()
                .environment(direto)
        } label: {
            // Numa view própria: o tempo muda a cada instante e assim não refaz a cena nem o menu.
            RotuloDireto()
                .environment(direto)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .textEditing) { ComandoProcurar() }
            MenuAula()
            MenuVer()
            CommandGroup(after: .appSettings) {
                Button("Preparar o Recap…") { NotificationCenter.default.post(name: .abrirPreparacao, object: nil) }
                Button("Procurar atualizações…") { Task { await atualizador.procurar() } }
            }
        }

        Settings {
            SettingsView()
                .environment(definicoes)
                .environment(library)
                .environment(fila)
                .environment(direto)
        }
    }
}
