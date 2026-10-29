import SwiftUI

@main
struct RecapIOSApp: App {
    @State private var pasta = PastaAulas()

    init() {
        // O painel Estudo começa aberto no iPad (ao lado) e fechado no iPhone (é uma folha por cima da aula).
        UserDefaults.standard.register(defaults: ["mostrarEstudo": UIDevice.current.userInterfaceIdiom == .pad])
    }

    var body: some Scene {
        WindowGroup {
            if let raiz = pasta.url {
                ContentViewIOS(raiz: raiz)
                    .id(raiz)
                    .environment(pasta)
            } else {
                EscolherPastaView()
                    .environment(pasta)
            }
        }
        // Com teclado no iPad: os mesmos menus e atalhos do Mac (⌘F, ⌘1–3, ⇧⌘R, ⌥⌘P).
        .commands {
            CommandGroup(after: .textEditing) { ComandoProcurar() }
            MenuAula()
            MenuVer()
        }
    }
}

struct EscolherPastaView: View {
    @Environment(PastaAulas.self) private var pasta
    @State private var aEscolher = false
    @State private var erro: String?

    var body: some View {
        ContentUnavailableView {
            Label("Escolhe a pasta das aulas", systemImage: "folder")
        } description: {
            Text("A mesma pasta do iCloud Drive que o Recap usa no Mac (Definições → Aulas).")
            if let e = erro ?? pasta.erro { Text(e).foregroundStyle(.red) }
        } actions: {
            Button("Escolher pasta…") { aEscolher = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(isPresented: $aEscolher, allowedContentTypes: [.folder]) { resultado in
            do { try pasta.escolher(resultado.get()) } catch { erro = error.localizedDescription }
        }
    }
}
