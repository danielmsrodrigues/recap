#if os(macOS)
import SwiftUI

/// Pede o nome e converte o curso da raiz para o novo formato de pastas. Só acontece ao carregar no botão.
struct ConverterCursoSheet: View {
    @Environment(Biblioteca.self) private var biblioteca
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var direto
    @Environment(\.dismiss) private var dismiss
    var aoAcabar: () -> Void = {}

    @State private var nome = ""
    @State private var aConverter = false
    @State private var erro: String?

    /// Uma aula a processar ou em direto escreve na pasta atual: não se muda a meio.
    private var ocupada: Bool { fila.jobs.contains(where: \.ativo) || direto.ativa }
    private var porAcabar: ConversorCurso.Registo? { biblioteca.conversaoPorAcabar }

    private var pronto: Bool {
        !aConverter && !ocupada && (porAcabar != nil || !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(porAcabar == nil ? "Converter para o novo formato de pastas" : "Acabar a conversão")
                .font(.title3.bold())
            if let porAcabar {
                Text("A conversão de \"\(porAcabar.nome)\" ficou a meio. As cadeiras que faltam estão em \"O meu curso\" e nada se perdeu.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("As cadeiras passam para a pasta do curso, ao lado dos outros cursos. Os apontamentos, as perguntas e as ligações ficam iguais: na app, só muda o nome do curso no seletor.")
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Nome do curso", text: $nome, prompt: Text("ex.: Mestrado em Gestão"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(aConverter)
            }
            Label("Antes de converter, deixa o iCloud acabar de sincronizar e fecha o Recap no iPhone e no iPad. Se parar a meio, nada se perde e podes continuar aqui.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if ocupada {
                Text("Espera que a aula em curso acabe.").font(.callout).foregroundStyle(.orange)
            }
            if let erro {
                Text(erro).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if aConverter { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(aConverter)
                Button(aConverter ? "A converter…" : porAcabar == nil ? "Converter" : "Continuar") { converter() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!pronto)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(aConverter)
        .onAppear { if nome.isEmpty { nome = biblioteca.cursos.first(where: \.naRaiz)?.meta.nome ?? "" } }
    }

    private func converter() {
        aConverter = true
        erro = nil
        Task {
            defer { aConverter = false }
            do {
                let ficaram = try await biblioteca.converterCursoDaRaiz(nome: nome)
                fila.removerSemPasta()
                if ficaram.isEmpty {
                    dismiss()
                    aoAcabar()
                } else {
                    erro = "Ficaram \(ficaram.count) ficheiro(s) por mudar, porque já existiam no destino: \(ficaram.prefix(3).joined(separator: ", ")). Resolve-os no Finder e carrega em Continuar."
                }
            } catch {
                self.erro = error.localizedDescription
            }
        }
    }
}
#endif
