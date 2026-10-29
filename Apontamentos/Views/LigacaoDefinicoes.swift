import SwiftUI

/// "Abrir Definições…": no Mac é a janela das Definições; no iOS a folha das definições, aberta pela vista principal.
struct LigacaoDefinicoes: View {
    var body: some View {
        #if os(macOS)
        SettingsLink { Text("Abrir Definições…") }
        #else
        Button("Abrir Definições…") { NotificationCenter.default.post(name: .abrirDefinicoes, object: nil) }
        #endif
    }
}

extension Notification.Name {
    /// Pedido para abrir as Definições (no iOS não há `SettingsLink`).
    static let abrirDefinicoes = Notification.Name("abrirDefinicoes")
}
