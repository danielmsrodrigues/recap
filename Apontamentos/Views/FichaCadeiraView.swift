import SwiftUI
import UniformTypeIdentifiers

/// "Sobre a cadeira": a ficha que junta o que as aulas disseram sobre a cadeira (ver `FichaCadeira`).
struct FichaCadeiraView: View {
    let cadeira: Cadeira
    @Environment(Fichas.self) private var fichas

    @State private var ficha: String?
    @State private var controlador = ControladorNotas()
    @State private var estadoEdicao = ""
    @State private var original: String?
    @State private var erro: String?
    @State private var escolherPrograma = false
    @State private var temPrograma = false

    var body: some View {
        VStack(spacing: 0) {
            if controlador.editando {
                BarraFormatacao(controlador: controlador, estado: estadoEdicao,
                                aoDescartar: { Task { await descartarEdicao() } },
                                aoConcluir: { Task { await concluirEdicao() } })
                Divider()
            }
            estado
            if let ficha {
                NotesWebView(markdown: ficha, controlador: controlador)
            } else {
                ContentUnavailableView {
                    Label("Ainda sem informação sobre a cadeira", systemImage: "info.circle")
                } description: {
                    Text("A apresentação, a avaliação, as datas e os avisos que o professor der nas aulas juntam-se aqui, numa só ficha que vai crescendo de aula para aula. Para começar já com o essencial, junta o programa da cadeira.")
                } actions: {
                    Button("Juntar o programa (PDF)…") { escolherPrograma = true }
                        .disabled(fichas.aAtualizar(cadeira) != nil)
                }
            }
        }
        .navigationTitle(FichaCadeira.tituloSeccao)
        .navigationSubtitle(cadeira.nome)
        .toolbar {
            ToolbarItemGroup {
                Menu("Programa", systemImage: "doc.text") {
                    if temPrograma {
                        Button("Abrir o programa") { NSWorkspace.shared.open(FichaCadeira.urlPrograma(cadeira.pasta)) }
                        Button("Trocar o programa…") { escolherPrograma = true }
                        Divider()
                        Button("Remover o programa", role: .destructive) { removerPrograma() }
                    } else {
                        Button("Juntar o programa (PDF)…") { escolherPrograma = true }
                    }
                }
                .labelStyle(.titleAndIcon)
                .help("O programa oficial da cadeira (planificação, guia): a ficha começa por ele")
                .disabled(controlador.editando || fichas.aAtualizar(cadeira) != nil)
                Button("Editar", systemImage: "pencil") { comecarEdicao() }
                    .labelStyle(.titleAndIcon)
                    .help("Corrigir ou acrescentar à ficha; as aulas seguintes juntam-se ao que escreveres")
                    .disabled(ficha == nil || controlador.editando || fichas.aAtualizar(cadeira) != nil)
            }
        }
        .task(id: fichas.versao) {
            if !controlador.editando { ficha = FichaCadeira.lerFicha(cadeira.pasta) }
            temPrograma = FichaCadeira.temPrograma(cadeira.pasta)
        }
        .fileImporter(isPresented: $escolherPrograma, allowedContentTypes: [.pdf]) { r in
            guard case .success(let url) = r else { return }
            let acedeu = url.startAccessingSecurityScopedResource()
            defer { if acedeu { url.stopAccessingSecurityScopedResource() } }
            do {
                try FichaCadeira.juntarPrograma(url, em: cadeira.pasta)
                temPrograma = true
                fichas.atualizar(nomeCadeira: cadeira.nome)
            } catch {
                erro = "Não foi possível juntar o programa: \(error.localizedDescription)"
            }
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    @ViewBuilder private var estado: some View {
        if let aula = fichas.aAtualizar(cadeira) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(aula.isEmpty ? "A atualizar a ficha…" : "A juntar \(aula) à ficha…")
                Spacer()
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
        } else if let e = fichas.erro(cadeira) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Não foi possível atualizar a ficha: \(e)").lineLimit(2)
                Spacer()
                Button("Tentar de novo") { fichas.atualizar(nomeCadeira: cadeira.nome) }
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
        }
    }

    private func removerPrograma() {
        do {
            try FichaCadeira.removerPrograma(em: cadeira.pasta)
            temPrograma = false
        } catch {
            erro = "Não foi possível remover o programa: \(error.localizedDescription)"
        }
    }

    // MARK: Edição (como nos apontamentos: grava sozinha pouco depois de cada alteração)

    private func comecarEdicao() {
        original = ficha
        estadoEdicao = "Guarda automaticamente"
        controlador.aoGravar = { await gravar() }
        controlador.definirEdicao(true)
    }

    private func gravar() async {
        guard controlador.editando, controlador.alterado else { return }
        controlador.alterado = false
        do {
            try FichaCadeira.escreverFicha(try await controlador.markdown(), em: cadeira.pasta)
            estadoEdicao = "Guardado às \(Date.now.formatted(date: .omitted, time: .shortened))"
        } catch {
            estadoEdicao = "Não foi possível guardar"
            erro = "Não foi possível guardar: \(error.localizedDescription)"
        }
    }

    private func concluirEdicao() async {
        if controlador.alterado, let md = try? await controlador.markdown() {
            try? FichaCadeira.escreverFicha(md, em: cadeira.pasta)
        }
        controlador.definirEdicao(false)
        ficha = FichaCadeira.lerFicha(cadeira.pasta)
    }

    private func descartarEdicao() async {
        controlador.definirEdicao(false)
        guard let original else { return }
        try? FichaCadeira.escreverFicha(original, em: cadeira.pasta)
        ficha = original
        controlador.repor(original)
    }
}
