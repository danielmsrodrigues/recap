import SwiftUI

/// Muda o título, a data ou a cadeira de uma aula (a pasta acompanha).
struct EditarAulaSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let aula: Aula
    let aoGuardar: (URL) -> Void

    @State private var titulo = ""
    @State private var data = Date.now
    @State private var cadeira = ""
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editar aula").font(.headline)
            Form {
                TextField("Título", text: $titulo)
                DatePicker("Data", selection: $data, displayedComponents: .date)
                Picker("Cadeira", selection: $cadeira) {
                    ForEach(library.cadeiras) { Text($0.nome).tag($0.nome) }
                }
            }
            .formStyle(.grouped)
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar") {
                    do {
                        let nova = try library.editarAula(aula, titulo: titulo.trimmingCharacters(in: .whitespaces), data: data, cadeira: cadeira)
                        aoGuardar(nova)
                        dismiss()
                    } catch {
                        erro = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            titulo = aula.meta.titulo
            data = aula.meta.data
            cadeira = aula.cadeira
        }
    }
}
