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
            } else if pasta.aProcurar {
                ProgressView("A abrir a pasta Recap do iCloud Drive…")
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
            Label(pasta.semICloud ? "Liga o iCloud Drive" : "Escolhe a pasta das aulas", systemImage: pasta.semICloud ? "icloud.slash" : "folder")
        } description: {
            VStack(spacing: 14) {
                if pasta.semICloud {
                    Text("Com o iCloud Drive ligado (Definições → o teu nome → iCloud → Drive), o Recap encontra sozinho a pasta Recap com as aulas do Mac. Também podes escolher outra pasta.")
                } else {
                    Text("A mesma pasta do iCloud Drive que o Recap usa no Mac (Definições → Aulas).")
                }
                // O seletor abre em "Recentes" e o Explorar começa em "No iPhone": sem isto, ninguém dá com o iCloud Drive.
                VStack(alignment: .leading, spacing: 6) {
                    Label("Toca em **Explorar**, em baixo.", systemImage: "1.circle")
                    Label("Se estiveres em \"No iPhone\", volta atrás com **‹**, em cima à esquerda.", systemImage: "2.circle")
                    Label("Abre a pasta das aulas no **iCloud Drive** (por exemplo **Recap**).", systemImage: "3.circle")
                    Label("Dentro dela, toca em **Abrir**.", systemImage: "4.circle")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let e = erro ?? pasta.erro {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                }
            }
        } actions: {
            if pasta.semICloud {
                Button("Tentar outra vez") { Task { await pasta.usarPastaRecap() } }
                    .buttonStyle(.borderedProminent)
                Button("Escolher pasta…") { aEscolher = true }
            } else {
                Button("Escolher pasta…") { aEscolher = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .fileImporter(isPresented: $aEscolher, allowedContentTypes: [.folder]) { resultado in
            do { try pasta.escolher(resultado.get()) } catch { erro = error.localizedDescription }
        }
    }
}
