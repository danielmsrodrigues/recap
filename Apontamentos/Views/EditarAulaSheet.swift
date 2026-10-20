import SwiftUI

/// Muda o título, a data ou a cadeira de uma aula (a pasta acompanha).
struct EditarAulaSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let aula: Aula
    let aoGuardar: (URL) -> Void

    @State private var dados = DadosAula()
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editar aula").font(.headline)
            Form {
                FormularioAula(dados: $dados)
            }
            .formStyle(.grouped)
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar") {
                    do {
                        let nova = try library.editarAula(aula, titulo: dados.tituloLimpo, data: dados.data, cadeira: dados.nomeCadeira)
                        aoGuardar(nova)
                        dismiss()
                    } catch {
                        erro = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!dados.valido)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            dados.titulo = aula.meta.titulo
            dados.data = aula.meta.data
            dados.cadeira = aula.cadeira
        }
    }
}
