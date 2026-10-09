import SwiftUI

/// Definições de uma cadeira: o glossário que entra no prompt do Whisper e do Claude.
struct CadeiraSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let cadeira: Cadeira
    @State private var glossario = ""
    @State private var regiao: RegiaoIgnorar = .automatica
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cadeira.nome).font(.title2.bold())
            Text("Glossário").font(.headline)
            Text("Um termo por linha, em espanhol, como o professor o diz. Podes acrescentar a tradução: `autovalor = valor próprio`. Os termos ajudam o Whisper a reconhecê-los (só cabem cerca de 30) e o Claude a traduzi-los.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $glossario)
                .font(.body.monospaced())
                .frame(minHeight: 240)
                .border(.separator)
            Picker("Câmara do professor (ignorar nos slides)", selection: $regiao) {
                ForEach(RegiaoIgnorar.allCases) { Text($0.nome).tag($0) }
            }
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([cadeira.pasta]) }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar") {
                    do {
                        try library.guardarCadeira(CadeiraMeta(glossario: glossario, regiaoIgnorar: regiao), cadeira: cadeira)
                        dismiss()
                    } catch {
                        erro = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            glossario = cadeira.meta.glossario
            regiao = cadeira.meta.regiaoIgnorar
        }
    }
}
