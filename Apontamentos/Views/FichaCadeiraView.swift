import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// "Sobre a cadeira": a ficha que junta o que as aulas disseram sobre a cadeira (ver `FichaCadeira`).
struct FichaCadeiraView: View {
    let cadeira: Cadeira
    @Environment(Fichas.self) private var fichas
    @Environment(Navegacao.self) private var navegacao
    @Environment(Library.self) private var library
    /// O livro da cadeira (PDF) está a ser feito.
    @State private var aFazerLivro = false

    @State private var ficha: String?
    @State private var controlador = ControladorNotas()
    @State private var estadoEdicao = ""
    @State private var original: String?
    @State private var erro: String?
    @State private var escolherPrograma = false
    @State private var temPrograma = false
    @State private var procurando = false
    @State private var termoProcura = ""
    @State private var pedidosProcura = 0
    /// Texto a realçar (resultado da pesquisa em todas as aulas).
    @State private var realce: [String] = []
    /// A guía de estudio aberta no Quick Look (no iOS; no Mac abre na Pré-visualização).
    @State private var guiaAberta: URL?

    var body: some View {
        VStack(spacing: 0) {
            if controlador.editando {
                BarraFormatacao(controlador: controlador, estado: estadoEdicao,
                                aoDescartar: { Task { await descartarEdicao() } },
                                aoConcluir: { Task { await concluirEdicao() } })
                Divider()
            }
            if procurando {
                BarraProcura(controlador: controlador, termo: $termoProcura, rotulo: "Procurar na ficha",
                             pedidosFoco: pedidosProcura, aoFechar: fecharProcura)
                Divider()
            }
            estado
            // O progresso do programa, só com guia e fora da edição.
            if temPrograma && !controlador.editando {
                ProgressoGuiaView(cadeira: cadeira)
                Divider()
            }
            if let ficha {
                NotesWebView(markdown: ficha, controlador: controlador, realcar: controlador.editando ? [] : realce)
            } else {
                ContentUnavailableView {
                    Label("Ainda sem informação sobre a cadeira", systemImage: "info.circle")
                } description: {
                    Text("A apresentação, a avaliação, as datas e os avisos que o professor der nas aulas juntam-se aqui, numa só ficha que vai crescendo de aula para aula. Para começar já com o essencial, junta a guia de estudo da cadeira.")
                } actions: {
                    #if os(macOS)
                    Button("Juntar a guia de estudo (PDF)…") { escolherPrograma = true }
                        .disabled(fichas.aAtualizar(cadeira) != nil)
                    #endif
                }
            }
        }
        .quickLookPreview($guiaAberta)
        .navigationTitle(FichaCadeira.tituloSeccao)
        .navigationSubtitle(cadeira.nome)
        .toolbar {
            ToolbarItemGroup {
                // Juntar, trocar e remover a guía passa por gerar a ficha com o Claude: faz-se no Mac.
                #if os(macOS)
                Menu("Guia de estudo", systemImage: "doc.text") {
                    if temPrograma {
                        Button("Abrir a guia") { NSWorkspace.shared.open(FichaCadeira.urlPrograma(cadeira.pasta)) }
                        Button("Trocar a guia…") { escolherPrograma = true }
                        Divider()
                        Button("Remover a guia", role: .destructive) { removerPrograma() }
                    } else {
                        Button("Juntar a guia de estudo (PDF)…") { escolherPrograma = true }
                    }
                }
                .labelStyle(.titleAndIcon)
                .disabled(controlador.editando || fichas.aAtualizar(cadeira) != nil)
                Button(aFazerLivro ? "A fazer o livro…" : "Livro da cadeira (PDF)…", systemImage: "book") { fazerLivro() }
                    .help("Um PDF com a ficha, todas as aulas por ordem e o glossário, para estudar sem ecrã")
                    .disabled(aFazerLivro || !cadeira.aulas.contains(where: \.temApontamentos))
                #else
                if temPrograma {
                    Button("Guia de estudo", systemImage: "doc.text") { guiaAberta = FichaCadeira.urlPrograma(cadeira.pasta) }
                        .disabled(controlador.editando)
                }
                #endif
                Button("Editar", systemImage: "pencil") { comecarEdicao() }
                    .labelStyle(.titleAndIcon)
                    .disabled(ficha == nil || controlador.editando || fichas.aAtualizar(cadeira) != nil)
            }
        }
        .focusedSceneValue(\.procurarNosApontamentos, ficha == nil ? nil : AcaoProcurar {
            procurando = true
            pedidosProcura += 1
        })
        .task(id: navegacao.destino) {
            guard let d = navegacao.destino, d.pasta.mesmoCaminho(FichaCadeira.url(cadeira.pasta)) else { return }
            navegacao.destino = nil
            if !controlador.editando { realce = d.termos }
        }
        .task(id: fichas.versao) {
            let copias = ConflitosICloud.resolver(FichaCadeira.url(cadeira.pasta))
            if !copias.isEmpty {
                erro = "A ficha foi mudada noutro dispositivo ao mesmo tempo. Ficou a versão mais recente; a outra está na pasta da cadeira, em \(copias.map(\.lastPathComponent).joined(separator: ", "))."
            }
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
                erro = "Não foi possível juntar a guia: \(error.localizedDescription)"
            }
        }
        .onDisappear {
            // O que se escreveu há menos de 1,5 s ainda não foi gravado automaticamente.
            let pasta = cadeira.pasta
            controlador.gravarJa { try FichaCadeira.escreverFicha($0, em: pasta) }
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

    private func fecharProcura() {
        guard procurando else { return }
        procurando = false
        controlador.limparProcura()
    }

    #if os(macOS)
    /// Pergunta onde guardar e faz o PDF (as partes uma a uma, com o aspeto dos apontamentos).
    private func fazerLivro() {
        let painel = NSSavePanel()
        painel.nameFieldStringValue = "\(cadeira.nome) — livro da cadeira.pdf"
        painel.allowedContentTypes = [.pdf]
        guard painel.runModal() == .OK, let destino = painel.url else { return }
        aFazerLivro = true
        Task {
            defer { aFazerLivro = false }
            do {
                try await LivroCadeira.exportar(cadeira, library: library, para: destino)
                NSWorkspace.shared.activateFileViewerSelecting([destino])
            } catch {
                erro = "Não foi possível fazer o livro da cadeira: \(error.localizedDescription)"
            }
        }
    }
    #endif

    private func removerPrograma() {
        do {
            try FichaCadeira.removerPrograma(em: cadeira.pasta)
            temPrograma = false
        } catch {
            erro = "Não foi possível remover a guia: \(error.localizedDescription)"
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
