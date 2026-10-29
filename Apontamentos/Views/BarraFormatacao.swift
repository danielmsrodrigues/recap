import SwiftUI

/// Barra de formatação por cima dos apontamentos em edição, ao estilo de um processador de texto.
struct BarraFormatacao: View {
    let controlador: ControladorNotas
    /// "A guardar…", "Guardado", …
    let estado: String
    let aoDescartar: () -> Void
    let aoConcluir: () -> Void

    private var estilo: Binding<String> {
        Binding(
            get: { ["h1", "h2", "h3", "blockquote"].contains(controlador.formato.bloco) ? controlador.formato.bloco : "p" },
            set: { controlador.comando("formatBlock", $0) }
        )
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 8) {
            ferramentas
            Spacer(minLength: 8)
            acoes
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        #else
        // No iPhone não cabe tudo numa linha: as ferramentas deslizam e as ações ficam por baixo.
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ferramentas }.padding(.horizontal, 14)
            }
            HStack(spacing: 8) { acoes }.padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
        .background(.bar)
        #endif
    }

    @ViewBuilder private var ferramentas: some View {
            Picker("Estilo", selection: estilo) {
                Text("Texto normal").tag("p")
                Text("Título 1").tag("h1")
                Text("Título 2").tag("h2")
                Text("Título 3").tag("h3")
                Text("Definição / destaque").tag("blockquote")
            }
            .labelsHidden()
            .frame(width: 150)
            .help("Estilo do parágrafo")

            Divider().frame(height: 18)
            botao("bold", ativo: controlador.formato.negrito, ajuda: "Negrito (⌘B)") { controlador.comando("bold") }
            botao("italic", ativo: controlador.formato.italico, ajuda: "Itálico (⌘I)") { controlador.comando("italic") }
            Divider().frame(height: 18)
            botao("list.bullet", ajuda: "Lista com pontos") { controlador.comando("insertUnorderedList") }
            botao("list.number", ajuda: "Lista numerada") { controlador.comando("insertOrderedList") }
            Divider().frame(height: 18)
            Menu {
                Button("Fórmula no texto") { controlador.comando("formula", "linha") }
                Button("Fórmula em destaque (linha própria)") { controlador.comando("formula", "bloco") }
            } label: {
                Label("Fórmula", systemImage: "function")
            }
            .fixedSize()
            .help("Inserir uma fórmula. Para editar uma fórmula existente, faz duplo clique nela.")
            Divider().frame(height: 18)
            botao("arrow.uturn.backward", ajuda: "Desfazer (⌘Z)") { controlador.comando("undo") }
            botao("arrow.uturn.forward", ajuda: "Refazer (⇧⌘Z)") { controlador.comando("redo") }
    }

    @ViewBuilder private var acoes: some View {
            Text(estado).font(.caption).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1)
            #if os(iOS)
            Spacer(minLength: 8)
            #endif
            Button("Descartar", action: aoDescartar)
                .fixedSize()
                .help("Descartar as alterações feitas nesta edição")
            Button("Concluído", action: aoConcluir)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .fixedSize()
    }

    private func botao(_ simbolo: String, ativo: Bool = false, ajuda: String, acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo)
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .padding(3)
        .background(ativo ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
        .help(ajuda)
    }
}
