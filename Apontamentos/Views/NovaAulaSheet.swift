import SwiftUI

/// Pede a cadeira, o título e a data de um vídeo largado na janela.
struct NovaAulaSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let video: URL
    /// Quantos vídeos faltam depois deste (para o texto do botão).
    let restantes: Int
    let aoConfirmar: (_ cadeira: String, _ titulo: String, _ data: Date, _ gerarApontamentos: Bool) -> Void
    let aoSaltar: () -> Void

    private static let novaCadeiraTag = "\u{0}nova"
    @AppStorage("ultimaCadeira") private var ultimaCadeira = ""
    @AppStorage("gerarApontamentos") private var gerarApontamentos = true
    @State private var cadeira = ""
    @State private var novaCadeira = ""
    @State private var titulo = ""
    @State private var data = Date.now

    private var nomeCadeira: String {
        (cadeira == Self.novaCadeiraTag ? novaCadeira : cadeira).trimmingCharacters(in: .whitespaces)
    }

    private var valido: Bool {
        !nomeCadeira.isEmpty && !titulo.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(video.lastPathComponent, systemImage: "film")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Form {
                Picker("Cadeira", selection: $cadeira) {
                    OpcoesCadeira()
                    if !library.cadeiras.isEmpty { Divider() }
                    Text("Nova cadeira…").tag(Self.novaCadeiraTag)
                }
                if cadeira == Self.novaCadeiraTag {
                    TextField("Nome da cadeira", text: $novaCadeira, prompt: Text("ex.: Álgebra Lineal"))
                }
                TextField("Título da aula", text: $titulo)
                DatePicker("Data", selection: $data, displayedComponents: .date)
                Toggle("Gerar apontamentos depois de transcrever", isOn: $gerarApontamentos)
            }
            .formStyle(.grouped)

            HStack {
                if restantes > 0 {
                    Text("Mais \(restantes) vídeo(s) a seguir").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Saltar este vídeo", role: .cancel) { aoSaltar(); dismiss() }
                Button("Adicionar à fila") {
                    ultimaCadeira = nomeCadeira
                    aoConfirmar(nomeCadeira, titulo.trimmingCharacters(in: .whitespaces), data, gerarApontamentos)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valido)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: preencher)
    }

    private func preencher() {
        if library.cadeira(nome: ultimaCadeira) != nil { cadeira = ultimaCadeira }
        else if let primeira = library.cadeirasPorSemestre.first?.cadeiras.first { cadeira = primeira.nome }
        else { cadeira = Self.novaCadeiraTag }

        titulo = video.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
        let valores = try? video.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        data = valores?.creationDate ?? valores?.contentModificationDate ?? .now
    }
}
