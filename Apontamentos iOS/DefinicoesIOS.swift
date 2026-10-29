import SwiftUI

/// As definições do iPad e do iPhone. As do curso (línguas, contexto, organização) vêm do Mac
/// (`_recap/definicoes.json`); aqui fica só o que é deste dispositivo: a pasta e o acesso ao Claude.
struct DefinicoesIOS: View {
    @Environment(Library.self) private var library
    @Environment(Definicoes.self) private var definicoes
    @Environment(PastaAulas.self) private var pasta
    @Environment(\.dismiss) private var dismiss
    @State private var mudarPasta = false
    @State private var chave = ""
    @State private var erro: String?

    var body: some View {
        @Bindable var definicoes = definicoes
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Pasta", value: library.raiz.lastPathComponent)
                    Button("Escolher outra pasta…") { mudarPasta = true }
                } header: {
                    Text("Aulas")
                } footer: {
                    Text("A pasta do iCloud Drive onde o Recap do Mac guarda as aulas.")
                }

                Section {
                    Picker("Modelo", selection: $definicoes.modeloClaude) {
                        ForEach(Definicoes.modelosClaude, id: \.id) { Text($0.nome).tag($0.id) }
                    }
                    if definicoes.temChaveAPI {
                        LabeledContent("Chave da API", value: "Guardada")
                        Button("Apagar a chave", role: .destructive) {
                            do { try definicoes.apagarChaveAPI() } catch { erro = error.localizedDescription }
                        }
                    } else {
                        SecureField("Chave da API (sk-ant-…)", text: $chave)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Guardar a chave") {
                            do {
                                try definicoes.guardarChaveAPI(chave.trimmingCharacters(in: .whitespacesAndNewlines))
                                chave = ""
                            } catch { erro = error.localizedDescription }
                        }
                        .disabled(chave.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let erro { Text(erro).foregroundStyle(.red) }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("As perguntas, os exercícios e as ligações pedem-se à API da Anthropic, paga à parte. A chave fica só neste dispositivo.")
                }
            }
            .navigationTitle("Definições")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .fileImporter(isPresented: $mudarPasta, allowedContentTypes: [.folder]) { resultado in
                do { try pasta.escolher(resultado.get()) } catch { erro = error.localizedDescription }
            }
        }
    }
}
