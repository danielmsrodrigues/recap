import SwiftUI

/// Procurar nos apontamentos abertos (⌘F), por cima da página: realça as ocorrências e anda entre elas (↩ / ⇧↩, ⌘G / ⇧⌘G).
struct BarraProcura: View {
    let controlador: ControladorNotas
    @Binding var termo: String
    var rotulo = "Procurar nos apontamentos"
    /// Cada pedido de ⌘F (com a barra já aberta) volta a pôr o cursor no campo.
    var pedidosFoco: Int
    let aoFechar: () -> Void

    @FocusState private var focado: Bool

    private var resultado: String {
        let p = controlador.procura
        if termo.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return p.total == 0 ? "Sem resultados" : "\(p.atual + 1) de \(p.total)"
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(rotulo, text: $termo)
                    .textFieldStyle(.plain)
                    .focused($focado)
                    .onKeyPress(.return, phases: .down) { tecla in
                        controlador.andarProcura(tecla.modifiers.contains(.shift) ? -1 : 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        aoFechar()
                        return .handled
                    }
                Text(resultado)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(controlador.procura.total == 0 ? .red : .secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focado ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3)))
            .frame(maxWidth: 360)

            ControlGroup {
                Button("Anterior", systemImage: "chevron.left") { controlador.andarProcura(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .help("Ocorrência anterior (⇧⌘G)")
                Button("Seguinte", systemImage: "chevron.right") { controlador.andarProcura(1) }
                    .keyboardShortcut("g", modifiers: .command)
                    .help("Ocorrência seguinte (⌘G)")
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            .disabled(controlador.procura.total == 0)

            Spacer(minLength: 0)
            // "Fechar" e não "Concluído": a editar, a barra de formatação já tem um "Concluído".
            Button("Fechar", action: aoFechar)
                .fixedSize()
                .help("Fechar a procura (esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .onAppear { focado = true }
        .onChange(of: pedidosFoco) { focado = true }
        .onChange(of: termo, initial: true) { controlador.procurar(termo) }
    }
}

/// A ação "Procurar" (⌘F) da página aberta (apontamentos de uma aula ou ficha da cadeira), para o menu Editar.
struct AcaoProcurar {
    let executar: () -> Void
}

extension FocusedValues {
    @Entry var procurarNosApontamentos: AcaoProcurar?
}

/// Editar ▸ Procurar… (⌘F), ativo quando há apontamentos ou uma ficha da cadeira abertos.
struct ComandoProcurar: View {
    @FocusedValue(\.procurarNosApontamentos) private var procurar

    var body: some View {
        Button("Procurar…") { procurar?.executar() }
            .keyboardShortcut("f")
            .disabled(procurar == nil)
    }
}
