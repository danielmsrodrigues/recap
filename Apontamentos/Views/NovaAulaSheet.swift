import SwiftUI

/// Pede a cadeira, o título e a data de um vídeo largado na janela.
struct NovaAulaSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let video: URL
    /// Quantos vídeos faltam depois deste (para o texto do botão).
    let restantes: Int
    let aoConfirmar: (_ cadeira: String, _ titulo: String, _ data: Date, _ gerarApontamentos: Bool) -> Void

    @AppStorage("ultimaCadeira") private var ultimaCadeira = ""
    @AppStorage("gerarApontamentos") private var gerarApontamentos = true
    @State private var dados = DadosAula()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(video.lastPathComponent, systemImage: "film")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Form {
                FormularioAula(dados: $dados)
                Toggle("Gerar apontamentos depois de transcrever", isOn: $gerarApontamentos)
            }
            .formStyle(.grouped)

            HStack {
                if restantes > 0 {
                    Text(restantes == 1 ? "Mais 1 vídeo a seguir" : "Mais \(restantes) vídeos a seguir").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Saltar este vídeo", role: .cancel) { dismiss() }
                Button("Adicionar à fila") {
                    ultimaCadeira = dados.nomeCadeira
                    aoConfirmar(dados.nomeCadeira, dados.tituloLimpo, dados.data, gerarApontamentos)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!dados.valido)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: preencher)
    }

    private func preencher() {
        dados.escolherCadeira(library: library, ultima: ultimaCadeira)
        dados.titulo = video.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let valores = try? video.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        dados.data = valores?.creationDate ?? valores?.contentModificationDate ?? .now
    }
}
