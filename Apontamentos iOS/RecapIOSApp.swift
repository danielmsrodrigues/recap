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
            VStack(spacing: 14) {
                Text("A mesma pasta do iCloud Drive que o Recap usa no Mac (Definições → Aulas).")
                // O seletor abre em "Recentes" e o Explorar começa em "No iPhone": sem isto, ninguém dá com o iCloud Drive.
                VStack(alignment: .leading, spacing: 6) {
                    Label("Toca em **Explorar**, em baixo.", systemImage: "1.circle")
                    Label("Se estiveres em \"No iPhone\", volta atrás com **‹**, em cima à esquerda.", systemImage: "2.circle")
                    Label("Abre **iCloud Drive → Documents → Recap → Aulas**.", systemImage: "3.circle")
                    Label("Dentro de Aulas, toca em **Abrir**.", systemImage: "4.circle")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let e = erro ?? pasta.erro {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                }
            }
        } actions: {
            Button("Escolher pasta…") { aEscolher = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(isPresented: $aEscolher, allowedContentTypes: [.folder]) { resultado in
            do { try pasta.escolher(resultado.get()) } catch { erro = error.localizedDescription }
        }
    }
}
