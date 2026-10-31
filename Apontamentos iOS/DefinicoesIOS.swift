import SwiftUI

/// As definições do iPad e do iPhone. As do curso (línguas, contexto, organização) vêm do Mac (`_recap/definicoes.json`);
/// aqui fica só o que é deste dispositivo: a pasta e por onde se chega ao Claude (com o motor "Mac", o modelo é o do Mac).
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
                    LabeledContent("Pasta", value: pasta.naPastaRecap ? "Recap no iCloud Drive" : library.raiz.lastPathComponent)
                    if !pasta.naPastaRecap {
                        Button("Usar a pasta Recap do iCloud Drive") { Task { await pasta.usarPastaRecap() } }
                    }
                    Button("Escolher outra pasta…") { mudarPasta = true }
                    if let e = pasta.erro { Text(e).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Aulas")
                } footer: {
                    Text("A pasta Recap do iCloud Drive é a mesma no Mac, no iPhone e no iPad: as aulas aparecem sozinhas em todos.")
                }

                Section {
                    NavigationLink("Sobre o Recap") { SobreView() }
                } footer: {
                    Text("Versão \(Novidades.atual): o que veio com cada versão.")
                }

                Section {
                    Picker("Por onde", selection: $definicoes.motor) {
                        ForEach(MotorTipo.allCases) { Text($0.nome).tag($0) }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text(definicoes.motor == .mac
                         ? "As perguntas, os exercícios e as ligações vão para o Recap do Mac, que responde com o Claude Code e a tua subscrição. O Mac tem de estar ligado, com o Recap aberto."
                         : "As perguntas, os exercícios e as ligações pedem-se à API da Anthropic, paga à parte.")
                }

                Section {
                    if definicoes.motor == .api {
                        Picker("Modelo", selection: $definicoes.modeloClaude) {
                            ForEach(Definicoes.modelosClaude, id: \.id) { Text($0.nome).tag($0.id) }
                        }
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
                    Text("API da Anthropic")
                } footer: {
                    Text(definicoes.motor == .mac
                         ? "Opcional: com uma chave, quando o Mac não responde podes pedir pela API. A chave fica só neste dispositivo."
                         : "A chave fica só neste dispositivo.")
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
