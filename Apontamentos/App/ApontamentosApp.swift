import SwiftUI

@main
struct ApontamentosApp: App {
    @State private var library: Library
    @State private var definicoes: Definicoes
    @State private var fila: ProcessingQueue
    @State private var direto = SessaoDireto()
    @State private var estudo: Estudo
    @State private var navegacao = Navegacao()
    @State private var atualizador = Atualizador()

    init() {
        let library = Library(raiz: Self.raiz)
        let definicoes = Definicoes()
        _library = State(initialValue: library)
        _definicoes = State(initialValue: definicoes)
        _fila = State(initialValue: ProcessingQueue(runner: PipelineRunner(library: library, definicoes: definicoes)))
        _estudo = State(initialValue: Estudo(library: library, definicoes: definicoes))
        // O painel das perguntas abre sempre ao arrancar; fechá-lo só vale até sair da app.
        UserDefaults.standard.set(true, forKey: "mostrarPerguntas")
    }

    /// Em DEBUG, `APONTAMENTOS_RAIZ` troca `~/Aulas` por outra pasta (testes manuais sem tocar nas aulas reais).
    private static var raiz: URL {
        #if DEBUG
        if let p = ProcessInfo.processInfo.environment["APONTAMENTOS_RAIZ"] { return URL(fileURLWithPath: p) }
        #endif
        return Disco.raizPorDefeito
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
            CommandGroup(after: .appSettings) {
                Button("Preparar o Recap…") { NotificationCenter.default.post(name: .abrirPreparacao, object: nil) }
                Button("Procurar atualizações…") { Task { await atualizador.procurar() } }
            }
        }

        Settings {
            SettingsView()
                .environment(definicoes)
        }
    }
}
