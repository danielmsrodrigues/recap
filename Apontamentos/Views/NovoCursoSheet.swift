#if os(macOS)
import SwiftUI

/// Criar um curso. Nada do que já existe muda de sítio: o curso novo fica na sua pasta e as cadeiras atuais ficam onde
/// estão. A língua das aulas não vem preenchida: errada, uma transcrição fica assim para sempre.
struct NovoCursoSheet: View {
    @Environment(Biblioteca.self) private var biblioteca
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    var aoCriar: () -> Void = {}

    @State private var nome = ""
    @State private var nomeDaRaiz = ""
    @State private var idioma: IdiomaAula?
    @State private var contexto = ""
    @State private var preferencias = DefinicoesPartilhadas.porDefeito
    @State private var erro: String?

    private var porNomear: Bool { biblioteca.cursoDaRaizPorNomear != nil }

    private var pronto: Bool {
        !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && idioma != nil
            && (!porNomear || !nomeDaRaiz.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nome", text: $nome, prompt: Text("ex.: Fintech360"))
                    TextField("Para o Claude", text: $contexto, prompt: Text("ex.: curso de especialização em Fintech, em inglês"), axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Língua das aulas", selection: $idioma) {
                        Text("Escolhe…").tag(IdiomaAula?.none)
                        Divider()
                        ForEach(IdiomaAula.allCases) { Text($0.nome).tag(Optional($0)) }
                    }
                    Picker("Língua dos apontamentos", selection: $preferencias.lingua) {
                        ForEach(LinguaApontamentos.allCases) { Text($0.nome).tag($0) }
                    }
                } header: {
                    Text("O curso novo")
                } footer: {
                    Text("A língua das aulas é a em que o professor fala: o Whisper transcreve nela.")
                }

                if porNomear {
                    Section {
                        TextField("Nome", text: $nomeDaRaiz, prompt: Text("ex.: Mestrado em Gestão"))
                    } header: {
                        Text("O curso que já tens")
                    } footer: {
                        Text("As cadeiras e as aulas que já tens ficam onde estão. Com dois cursos, o nome serve para os distinguir.")
                    }
                }

                CamposOrganizacao(organizacao: $preferencias.organizacaoCurso, inicios: $preferencias.inicios, duracao: $preferencias.duracao)

                if let erro {
                    Text(erro).foregroundStyle(.red).font(.callout)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Criar curso") { criar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!pronto)
            }
            .padding(12)
        }
        .frame(width: 520, height: 620)
        .onAppear {
            preferencias = .paraCursoNovo(idioma: preferencias.idioma, como: library.preferencias)
        }
    }

    private func criar() {
        guard let idioma else { return }
        var novas = preferencias
        novas.idioma = idioma
        novas.contextoCurso = contexto.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let curso = try biblioteca.criarCurso(nome: nome, preferencias: novas, nomeDoCursoDaRaiz: porNomear ? nomeDaRaiz : nil)
            biblioteca.abrir(curso)
            dismiss()
            aoCriar()
        } catch {
            erro = error.localizedDescription
        }
    }
}
#endif
