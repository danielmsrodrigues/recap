import SwiftUI

/// Definições de uma cadeira: o semestre e o glossário que entra no prompt do Whisper e do Claude.
struct CadeiraSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let cadeira: Cadeira
    @State private var glossario = ""
    @State private var regiao: RegiaoIgnorar = .automatica
    /// nil = deduzido da data das aulas.
    @State private var semestre: Semestre?
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cadeira.nome).font(.title2.bold())
            if library.organizacao != .nenhuma {
                Picker(library.organizacao.rotulo, selection: $semestre) {
                    Text("Automático (\(cadeira.meta.semestre == nil ? cadeira.semestre.nome : "pela data das aulas"))").tag(Semestre?.none)
                    Divider()
                    ForEach(library.organizacao.opcoes(ate: cadeira.semestre.ano), id: \.self) { s in
                        Text(s.nome).tag(Optional(s))
                    }
                }
                .fixedSize()
            }
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
                        var meta = cadeira.meta
                        meta.glossario = glossario
                        meta.regiaoIgnorar = regiao
                        meta.semestre = semestre
                        try library.guardarCadeira(meta, cadeira: cadeira)
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
            semestre = cadeira.meta.semestre
        }
    }
}

/// As opções de um seletor de cadeira, agrupadas por semestre (o mais recente primeiro). A etiqueta é o nome da cadeira.
struct OpcoesCadeira: View {
    @Environment(Library.self) private var library

    var body: some View {
        let grupos = library.cadeirasPorSemestre
        if grupos.count == 1 {
            ForEach(grupos[0].cadeiras) { Text($0.nome).tag($0.nome) }
        } else {
            ForEach(grupos, id: \.semestre) { grupo in
                Section(grupo.semestre.nome) {
                    ForEach(grupo.cadeiras) { Text($0.nome).tag($0.nome) }
                }
            }
        }
    }
}
