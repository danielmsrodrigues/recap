import SwiftUI

/// O que se pode fazer à aula aberta, para os menus Aula e Ver da barra de menus. Cada ação é nil quando não
/// está disponível (sem apontamentos, a gerar, a editar…), e o item do menu fica desativado.
struct ComandosAula {
    var editar: (() -> Void)?
    var gerarApontamentos: (() -> Void)? = nil
    /// Já há apontamentos: o item pede confirmação.
    var temApontamentos: Bool
    var extrairSlides: (() -> Void)? = nil
    var guardarPDF: (() -> Void)? = nil
    var guardarMarkdown: (() -> Void)? = nil
    var revista: Bool
    var marcarRevista: (Bool) -> Void
    /// nil no iOS.
    var mostrarNoFinder: (() -> Void)? = nil
    var separador: Binding<SeparadorAula>
    /// Os separadores que esta aula tem (uma aula em direto sem slides não tem o de Slides).
    var separadores: [SeparadorAula]
}

extension FocusedValues {
    @Entry var comandosAula: ComandosAula?
}

/// Menu Aula: tudo o que a toolbar da aula faz, também acessível pelo teclado e com a toolbar escondida.
struct MenuAula: Commands {
    var body: some Commands {
        CommandMenu("Aula") { ItensMenuAula() }
    }
}

private struct ItensMenuAula: View {
    @FocusedValue(\.comandosAula) private var c

    var body: some View {
        Button("Editar apontamentos") { c?.editar?() }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(c?.editar == nil)
        Divider()
        Button(c?.temApontamentos == true ? "Gerar apontamentos de novo…" : "Gerar apontamentos") { c?.gerarApontamentos?() }
            .disabled(c?.gerarApontamentos == nil)
        Button("Extrair slides de novo") { c?.extrairSlides?() }
            .disabled(c?.extrairSlides == nil)
        Divider()
        Button("Guardar PDF…") { c?.guardarPDF?() }
            .disabled(c?.guardarPDF == nil)
        Button("Guardar Markdown…") { c?.guardarMarkdown?() }
            .disabled(c?.guardarMarkdown == nil)
        Divider()
        Toggle("Revista", isOn: Binding(get: { c?.revista ?? false }, set: { c?.marcarRevista($0) }))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(c == nil)
        #if os(macOS)
        Button("Mostrar no Finder") { c?.mostrarNoFinder?() }
            .disabled(c?.mostrarNoFinder == nil)
        #endif
    }
}

/// Menu Ver: os separadores da aula (⌘1, ⌘2, ⌘3) e o painel Estudo (⌥⌘P).
struct MenuVer: Commands {
    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ItensMenuVer()
            Divider()
        }
    }
}

private struct ItensMenuVer: View {
    @FocusedValue(\.comandosAula) private var c
    @AppStorage("mostrarEstudo") private var mostrarEstudo = true

    var body: some View {
        ForEach(Array(SeparadorAula.allCases.enumerated()), id: \.element) { i, s in
            Toggle(s.rawValue, isOn: Binding(get: { c?.separador.wrappedValue == s }, set: { if $0 { c?.separador.wrappedValue = s } }))
                .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                .disabled(c?.separadores.contains(s) != true)
        }
        Divider()
        Toggle("Painel Estudo", isOn: $mostrarEstudo)
            .keyboardShortcut("p", modifiers: [.command, .option])
    }
}
