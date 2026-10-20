import SwiftUI

/// Editar uma cadeira (nome, semestre, glossário e câmara do professor), ou criar uma nova (`cadeira` nil).
struct CadeiraSheet: View {
    @Environment(Library.self) private var library
    @Environment(Definicoes.self) private var definicoes
    @Environment(\.dismiss) private var dismiss
    let cadeira: Cadeira?
    /// A pasta mudou de nome: quem tem a aula aberta acerta a seleção.
    var aoRenomear: ((_ antiga: URL, _ nova: URL) -> Void)?

    @State private var nome = ""
    @State private var glossario = ""
    @State private var regiao: RegiaoIgnorar = .automatica
    /// nil = deduzido da data das aulas.
    @State private var semestre: Semestre?
    @State private var erro: String?

    private var nomeLimpo: String { nome.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cadeira == nil ? "Nova cadeira" : "Editar cadeira").font(.title2.bold())
            Form {
                TextField("Nome", text: $nome, prompt: Text("ex.: Álgebra Linear"))
                if let cadeira, library.organizacao != .nenhuma {
                    Picker(library.rotuloPeriodo, selection: $semestre) {
                        Text("Automático (\(cadeira.meta.semestre == nil ? library.nome(cadeira.semestre) : "pela data das aulas"))").tag(Semestre?.none)
                        Divider()
                        ForEach(library.opcoesSemestre(cadeira), id: \.self) { s in
                            Text(library.nome(s)).tag(Optional(s))
                        }
                    }
                }
                Picker("Câmara do professor", selection: $regiao) {
                    ForEach(RegiaoIgnorar.allCases) { Text($0.nome).tag($0) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            Text("Glossário").font(.headline)
            Text("Um termo por linha, em \(definicoes.idiomaAulas.nomeNoPrompt), como o professor o diz. Podes acrescentar a tradução: `autovalor = valor próprio`. Os termos ajudam o Whisper a reconhecê-los (só cabem cerca de 30) e o Claude a traduzi-los.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $glossario)
                .font(.body.monospaced())
                .frame(minHeight: 200)
                .border(.separator)
            Text("A câmara do professor é a zona do ecrã que se ignora ao procurar slides nos vídeos desta cadeira.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button(cadeira == nil ? "Criar" : "Guardar") { guardar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(nomeLimpo.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            guard let cadeira else { return }
            nome = cadeira.nome
            glossario = cadeira.meta.glossario
            regiao = cadeira.meta.regiaoIgnorar
            semestre = cadeira.meta.semestre
        }
    }

    private func guardar() {
        do {
            var meta = cadeira?.meta ?? CadeiraMeta()
            meta.glossario = glossario
            meta.regiaoIgnorar = regiao
            meta.semestre = semestre
            if let cadeira {
                var atual = cadeira
                if nomeLimpo != cadeira.nome {
                    let nova = try library.renomearCadeira(cadeira, para: nomeLimpo)
                    aoRenomear?(cadeira.pasta, nova)
                    guard let renomeada = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(nova) }) else { dismiss(); return }
                    atual = renomeada
                }
                try library.guardarCadeira(meta, cadeira: atual)
            } else {
                let pasta = try library.criarCadeira(nome: nomeLimpo)
                if let nova = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(pasta) }) {
                    try library.guardarCadeira(meta, cadeira: nova)
                }
            }
            dismiss()
        } catch {
            erro = error.localizedDescription
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
                Section(library.nome(grupo.semestre)) {
                    ForEach(grupo.cadeiras) { Text($0.nome).tag($0.nome) }
                }
            }
        }
    }
}
