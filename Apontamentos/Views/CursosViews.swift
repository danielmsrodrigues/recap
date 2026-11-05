import SwiftUI

/// O curso aberto, com os outros no menu. Só aparece com mais de um curso: quem tem um não vê diferença.
struct SeletorCurso: View {
    @Environment(Biblioteca.self) private var biblioteca

    var body: some View {
        if biblioteca.cursos.count > 1 {
            let aDecorrer = biblioteca.cursos.filter { !$0.concluido }
            let concluidos = biblioteca.cursos.filter(\.concluido)
            Menu {
                ForEach(aDecorrer) { opcao($0) }
                if !concluidos.isEmpty {
                    Menu("Concluídos") {
                        ForEach(concluidos) { opcao($0) }
                    }
                }
                Divider()
                Button("Ver todos os cursos…") { NotificationCenter.default.post(name: .abrirCursos, object: nil) }
            } label: {
                Label(biblioteca.cursoAtivo.nome, systemImage: "graduationcap")
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .fixedSize()
            #endif
            .help("Mudar de curso")
            .task(id: biblioteca.cursos) { biblioteca.atualizarResumos() }
        }
    }

    private func opcao(_ curso: Curso) -> some View {
        Toggle(isOn: Binding(get: { curso.id == biblioteca.cursoAtivo.id }, set: { if $0 { biblioteca.abrir(curso) } })) {
            Text(curso.nome)
            if let n = biblioteca.resumos[curso.id]?.porRever, n > 0 { Text("\(n) por rever") }
        }
    }
}

/// Os cursos a decorrer e os concluídos. Abrir um muda toda a vista para esse curso.
struct CatalogoCursosView: View {
    @Environment(Biblioteca.self) private var biblioteca
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var verNovo = false
    @State private var verConverter = false
    @State private var aRenomear: Curso?
    @State private var novoNome = ""
    @State private var erro: String?
    #endif

    var body: some View {
        let aDecorrer = biblioteca.cursos.filter { !$0.concluido }
        let concluidos = biblioteca.cursos.filter(\.concluido)
        NavigationStack {
            List {
                if let falta = biblioteca.cursoEmFalta {
                    Label("\"\(falta)\" ainda não chegou a este aparelho. Abre sozinho quando chegar.", systemImage: "icloud.and.arrow.down")
                        .foregroundStyle(.secondary)
                }
                if !aDecorrer.isEmpty {
                    Section("A decorrer") { ForEach(aDecorrer) { linha($0) } }
                }
                if !concluidos.isEmpty {
                    Section("Concluídos") { ForEach(concluidos) { linha($0) } }
                }
            }
            .navigationTitle("Cursos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) { Button("Novo curso…") { verNovo = true } }
                #endif
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 420)
        .sheet(isPresented: $verNovo) { NovoCursoSheet { dismiss() } }
        .sheet(isPresented: $verConverter) { ConverterCursoSheet { dismiss() } }
        .alert("Mudar o nome do curso", isPresented: Binding(get: { aRenomear != nil }, set: { if !$0 { aRenomear = nil } }), presenting: aRenomear) { curso in
            TextField("Nome", text: $novoNome)
            Button("Guardar") { tentar { try biblioteca.renomear(curso, para: novoNome) } }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Muda só o nome que aparece no Recap. A pasta no disco fica como está.")
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") {}
        } message: { Text($0) }
        #endif
        .task { biblioteca.atualizarResumos() }
    }

    private func linha(_ curso: Curso) -> some View {
        HStack(spacing: 8) {
            Button {
                biblioteca.abrir(curso)
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: curso.concluido ? "checkmark.seal" : "graduationcap")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(curso.nome).font(.headline).lineLimit(2)
                        if let resumo = biblioteca.resumos[curso.id] {
                            Text(Self.texto(resumo)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if curso.id == biblioteca.cursoAtivo.id {
                        Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Aberto")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            if curso.naRaiz {
                Button(biblioteca.conversaoPorAcabar == nil ? "Converter…" : "Continuar a conversão…") { verConverter = true }
                    .help("Passa as cadeiras para a pasta do curso, ao lado dos outros. Na app, fica tudo igual.")
            }
            Menu {
                acoes(curso)
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("Mais")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            #endif
        }
        #if os(macOS)
        .contextMenu { acoes(curso) }
        #endif
    }

    #if os(macOS)
    @ViewBuilder private func acoes(_ curso: Curso) -> some View {
        Button("Mudar o nome…") {
            novoNome = curso.nome
            aRenomear = curso
        }
        Button(curso.concluido ? "Voltar a pôr a decorrer" : "Marcar como concluído") {
            tentar { try biblioteca.definirConcluido(!curso.concluido, curso: curso) }
        }
        Divider()
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([curso.pasta]) }
    }

    private func tentar(_ acao: () throws -> Void) {
        do { try acao() } catch { erro = error.localizedDescription }
    }
    #endif

    /// "3 cadeiras · 14 aulas · 2 por rever · última a 1 out."
    static func texto(_ r: ResumoCurso) -> String {
        var partes = [r.cadeiras == 1 ? "1 cadeira" : "\(r.cadeiras) cadeiras",
                      r.aulas == 1 ? "1 aula" : "\(r.aulas) aulas"]
        if r.porRever > 0 { partes.append("\(r.porRever) por rever") }
        if let d = r.ultimaAula { partes.append("última a \(DataAula.curta(d))") }
        return partes.joined(separator: " · ")
    }
}
