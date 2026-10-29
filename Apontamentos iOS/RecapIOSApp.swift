import SwiftUI

@main
struct RecapIOSApp: App {
    @State private var pasta = PastaAulas()

    var body: some Scene {
        WindowGroup {
            if let raiz = pasta.url {
                InicioIOS(raiz: raiz)
                    .id(raiz)
                    .environment(pasta)
            } else {
                EscolherPastaView()
                    .environment(pasta)
            }
        }
    }
}
