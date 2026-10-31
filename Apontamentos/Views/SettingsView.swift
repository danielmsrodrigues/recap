import SwiftUI

/// Geral (pasta, organização, curso e língua) · Claude (motor, modelo, prompt) · Transcrição · Slides.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Geral", systemImage: "gearshape") { GeralSettings() }
            Tab("Claude", systemImage: "sparkles") { ClaudeSettings() }
            Tab("Transcrição", systemImage: "waveform") { TranscricaoSettings() }
            Tab("Slides", systemImage: "rectangle.on.rectangle") { SlidesSettings() }
        }
        .frame(width: 640)
    }
}

// MARK: Geral

private struct GeralSettings: View {
    @Environment(Definicoes.self) private var definicoes
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var direto
    @State private var escolher = false
    /// A pasta escolhida, à espera de saber se as aulas vão para lá.
    @State private var nova: URL?
    @State private var erro: String?

    /// Uma aula a processar ou em direto escreve na pasta atual: não se troca a meio.
    private var ocupada: Bool { fila.jobs.contains(where: \.ativo) || direto.ativa }

    var body: some View {
        @Bindable var definicoes = definicoes
        Form {
            Section {
                TextField("Curso", text: $definicoes.contextoCurso, prompt: Text("ex.: licenciatura em Ciência de Dados, 1.º ano, numa universidade espanhola"), axis: .vertical)
                    .lineLimit(1...3)
                Picker("Língua das aulas", selection: $definicoes.idiomaAulas) {
                    ForEach(IdiomaAula.allCases) { Text($0.nome).tag($0) }
                }
                Picker("Língua dos apontamentos", selection: $definicoes.linguaApontamentos) {
                    ForEach(LinguaApontamentos.allCases) { Text($0.nome).tag($0) }
                }
            } header: {
                Text("O teu curso")
            } footer: {
                Text("O curso diz ao Claude para quem escreve. A língua das aulas é a em que o professor fala: o Whisper transcreve nela. Os apontamentos, as respostas, os exercícios e a ficha da cadeira saem na língua dos apontamentos.")
            }

            Section {
                LabeledContent("Pasta") {
                    Text((library.raiz.path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Escolher…") { escolher = true }
                    Button("Pasta por defeito") { pedir(Disco.raizPorDefeito) }
                        .help((Disco.raizPorDefeito.path as NSString).abbreviatingWithTildeInPath)
                        .disabled(library.raiz.mesmoCaminho(Disco.raizPorDefeito))
                    Spacer()
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.raiz]) }
                }
                .disabled(ocupada)
                if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            } header: {
                Text("Pasta das aulas")
            } footer: {
                Text(ocupada
                     ? "Espera que a aula em curso acabe para mudar de pasta."
                     : "Na pasta Recap do iCloud Drive, as aulas aparecem sozinhas no iPhone e no iPad. Essa pasta é criada quando abres o Recap no iPhone ou no iPad; depois, o Início do Mac propõe mudar as aulas para lá. Os vídeos originais ficam onde estão.")
            }

            Section {
                Picker("Organização", selection: Binding(get: { definicoes.organizacao }, set: {
                    definicoes.organizacao = $0
                    library.organizacao = $0
                })) {
                    ForEach(OrganizacaoCurso.allCases) { o in
                        Text(o == .anoESemestre ? "Por ano e \(library.nomePeriodo)" : o.nome).tag(o)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Calendário", selection: Binding(get: { definicoes.iniciosPeriodos }, set: {
                    definicoes.iniciosPeriodos = $0
                    library.iniciosPeriodos = $0
                })) {
                    ForEach(CalendarioLetivo.opcoes, id: \.self) { Text($0.nome).tag($0.inicios) }
                }
                Stepper("Duração do curso: \(definicoes.duracaoCurso) \(definicoes.duracaoCurso == 1 ? "ano" : "anos")",
                        value: Binding(get: { definicoes.duracaoCurso }, set: {
                            definicoes.duracaoCurso = $0
                            library.duracaoCurso = $0
                        }), in: 1...8)
            } header: {
                Text("Barra lateral")
            } footer: {
                Text("Por defeito, o ano e o \(library.nomePeriodo) vêm das datas das aulas (\(CalendarioLetivo.descricao(definicoes.iniciosPeriodos))). Num curso de um ano ou sem semestres, escolhe \"Só por ano\" ou \"Sem divisão\". Os semestres escolhidos à mão em cada cadeira não se perdem.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $escolher, allowedContentTypes: [.folder]) { resultado in
            if case .success(let url) = resultado { pedir(url) }
        }
        .confirmationDialog("Mover as aulas para a pasta nova?", isPresented: Binding(get: { nova != nil }, set: { if !$0 { nova = nil } }), presenting: nova) { url in
            Button("Mover as aulas") { mudar(para: url, mover: true) }
            Button("Usar a pasta sem mover") { mudar(para: url, mover: false) }
            Button("Cancelar", role: .cancel) {}
        } message: { url in
            Text("As \(library.cadeiras.count) cadeiras de \((library.raiz.path as NSString).abbreviatingWithTildeInPath) passam para \((url.path as NSString).abbreviatingWithTildeInPath). Sem mover, o Recap passa a ler só a pasta nova e as aulas atuais ficam onde estão.")
        }
    }

    private func pedir(_ url: URL) {
        guard !url.mesmoCaminho(library.raiz) else { return }
        if library.cadeiras.isEmpty { mudar(para: url, mover: false) } else { nova = url }
    }

    private func mudar(para url: URL, mover: Bool) {
        do {
            try library.mudarRaiz(para: url, mover: mover)
            definicoes.pastaAulas = url.mesmoCaminho(Disco.raizPorDefeito) ? "" : url.standardizedFileURL.path
            erro = nil
        } catch {
            erro = error.localizedDescription
        }
    }
}

// MARK: Claude

private struct ClaudeSettings: View {
    @Environment(Definicoes.self) private var definicoes
    @State private var versaoClaude: String?
    @State private var chave = ""
    @State private var mensagem: String?
    @State private var entrada = ""
    @State private var saida = ""
    @State private var editarPrompt = false

    var body: some View {
        @Bindable var definicoes = definicoes
        Form {
            Section {
                Picker("Por onde", selection: $definicoes.motor) {
                    ForEach(MotorTipo.allCases) { Text($0.nome).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(definicoes.motor == .claudeCode
                     ? "Usa o Claude Code instalado neste Mac e a tua subscrição (Pro/Max): sem custos à parte, conta para os limites de utilização."
                     : "Usa a API da Anthropic, paga por utilização com créditos à parte da subscrição.")
            }

            Section {
                Toggle("Responder às perguntas feitas no iPad e no iPhone", isOn: $definicoes.responderPedidos)
            } footer: {
                Text("Com a pasta das aulas no iCloud Drive, o Recap do iPad e do iPhone pode pedir ao Mac as respostas, os exercícios e as ligações. O Mac responde enquanto o Recap estiver aberto, pelo mesmo motor daqui.")
            }

            if definicoes.motor == .claudeCode {
                Section {
                    LabeledContent("Claude Code") {
                        if let url = definicoes.claudeCode {
                            Text("\(versaoClaude ?? "…") · \(url.path)").foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("Não encontrado").foregroundStyle(.red)
                        }
                    }
                    TextField("Caminho do claude", text: $definicoes.caminhoClaude, prompt: Text("automático"))
                } footer: {
                    Text("Se ainda não fizeste login, abre o Terminal, corre claude e entra com a tua conta.")
                }
                .task(id: definicoes.claudeCode) {
                    versaoClaude = nil
                    if let url = definicoes.claudeCode { versaoClaude = await ClaudeCodeClient.versao(url) }
                }
            } else {
                apiSecao
                precosSecao
            }

            Section {
                Picker("Modelo", selection: $definicoes.modeloClaude) {
                    ForEach(Definicoes.modelosClaude, id: \.id) { Text($0.nome).tag($0.id) }
                    // Um modelo escrito à mão numa versão anterior continua escolhido até se mudar no menu.
                    if !Definicoes.modelosClaude.contains(where: { $0.id == definicoes.modeloClaude }) {
                        Text(definicoes.modeloClaude).tag(definicoes.modeloClaude)
                    }
                }
                Picker("Esforço", selection: $definicoes.esforco) {
                    ForEach(Esforco.allCases) { Text($0.nome).tag($0) }
                }
                LabeledContent("Instruções dos apontamentos") {
                    Button("Editar…") { editarPrompt = true }
                }
            } header: {
                Text("Modelo")
            } footer: {
                Text("Mais esforço dá apontamentos mais cuidados, mas gasta mais tokens de saída. \"Alto\" é o valor por defeito do Sonnet 5.5. As instruções são o prompt de sistema que o Claude recebe para escrever os apontamentos.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: carregarPrecos)
        .onChange(of: definicoes.modeloClaude) { carregarPrecos() }
        .sheet(isPresented: $editarPrompt) { PromptSheet() }
    }

    @ViewBuilder private var apiSecao: some View {
        Section {
            if definicoes.temChaveAPI {
                LabeledContent("Chave API") {
                    HStack {
                        Text("Guardada no Porta-chaves").foregroundStyle(.secondary)
                        Button("Remover", role: .destructive) {
                            do { try definicoes.apagarChaveAPI(); mensagem = nil } catch { mensagem = error.localizedDescription }
                        }
                    }
                }
            } else {
                SecureField("Chave API", text: $chave, prompt: Text("sk-ant-…"))
                Button("Guardar no Porta-chaves") {
                    do {
                        try definicoes.guardarChaveAPI(chave)
                        chave = ""
                        mensagem = "Chave guardada."
                    } catch {
                        mensagem = error.localizedDescription
                    }
                }
                .disabled(chave.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let mensagem { Text(mensagem).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text("Anthropic")
        } footer: {
            Text("Cria uma chave em platform.claude.com → API Keys. Fica só no Porta-chaves deste Mac.")
        }
    }

    @ViewBuilder private var precosSecao: some View {
        Section {
            TextField("Entrada (USD por milhão de tokens)", text: $entrada)
            TextField("Saída (USD por milhão de tokens)", text: $saida)
            HStack {
                Button("Repor preços oficiais") {
                    definicoes.precosPersonalizados[definicoes.modeloClaude] = nil
                    carregarPrecos()
                }
                Spacer()
                Button("Guardar preços") { guardarPrecos() }
            }
        } header: {
            Text("Preços de \(definicoes.modeloClaude)")
        } footer: {
            Text("Usados só para mostrar o custo estimado. Fonte: platform.claude.com/docs/en/about-claude/pricing.")
        }
    }

    private func carregarPrecos() {
        let p = definicoes.tabelaPrecos.preco(para: definicoes.modeloClaude)
        entrada = p.map { $0.entrada.formatted() } ?? ""
        saida = p.map { $0.saida.formatted() } ?? ""
    }

    private func guardarPrecos() {
        guard let e = Double(entrada.replacingOccurrences(of: ",", with: ".")),
              let s = Double(saida.replacingOccurrences(of: ",", with: "."))
        else { return }
        // A cache segue as proporções da tabela oficial (escrita 1,25×; leitura 0,05× no Sonnet 5.5).
        let base = TabelaPrecos.oficial[definicoes.modeloClaude]
        definicoes.precosPersonalizados[definicoes.modeloClaude] = Preco(
            entrada: e, saida: s,
            escritaCache: e * 1.25,
            leituraCache: base.map { e * $0.leituraCache / $0.entrada } ?? e * 0.1)
    }
}

/// O prompt de sistema dos apontamentos, editável. Grava ao fechar.
private struct PromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var guardado = ""
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instruções dos apontamentos").font(.title2.bold())
            Text("O prompt de sistema que o Claude recebe em cada geração. `{{contexto}}` e `{{idioma}}` são substituídos pelo curso e pela língua das Definições. Fica em \(PromptStore.url.path).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $texto)
                .font(.body.monospaced())
                .frame(minHeight: 380)
                .border(.separator)
            if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Repor original") {
                    do { try PromptStore.repor(); carregar() } catch { erro = error.localizedDescription }
                }
                Button("Abrir no editor") { NSWorkspace.shared.open(PromptStore.url) }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar") { guardar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(texto == guardado)
            }
        }
        .padding(20)
        .frame(width: 720)
        .onAppear(perform: carregar)
    }

    private func carregar() {
        texto = PromptStore.ler()
        guardado = texto
    }

    private func guardar() {
        do {
            try PromptStore.guardar(texto)
            dismiss()
        } catch {
            erro = error.localizedDescription
        }
    }
}

// MARK: Transcrição

private struct TranscricaoSettings: View {
    @Environment(Definicoes.self) private var definicoes
    @State private var descarregados: Set<WhisperModelo> = []
    @State private var progresso: [WhisperModelo: Double] = [:]
    @State private var erro: String?
    private let store = ModelStore()

    var body: some View {
        @Bindable var definicoes = definicoes
        Form {
            Section {
                Picker("Modelo do Whisper", selection: $definicoes.modeloWhisper) {
                    ForEach(WhisperModelo.allCases) { Text($0.nome).tag($0) }
                }
                ForEach(WhisperModelo.allCases) { modelo in
                    LabeledContent {
                        if let p = progresso[modelo] {
                            ProgressView(value: p).frame(width: 140)
                        } else if descarregados.contains(modelo) {
                            HStack {
                                Text("Descarregado").foregroundStyle(.secondary)
                                Button("Apagar") { apagar(modelo) }
                            }
                        } else {
                            Button("Descarregar") { Task { await descarregar(modelo) } }
                        }
                    } label: {
                        Text(modelo.nome)
                        Text(modelo.descricao)
                    }
                }
                if let erro { Text(erro).foregroundStyle(.red).font(.callout) }
            } footer: {
                Text("O modelo é descarregado na primeira transcrição, se ainda não estiver aqui. Fica em \(store.base.path). A língua das aulas escolhe-se em Geral.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: atualizar)
    }

    private func atualizar() {
        descarregados = Set(WhisperModelo.allCases.filter(store.estaDescarregado))
    }

    private func descarregar(_ modelo: WhisperModelo) async {
        progresso[modelo] = 0
        defer { progresso[modelo] = nil; atualizar() }
        do {
            _ = try await store.descarregar(modelo) { p in
                Task { @MainActor in progresso[modelo] = p }
            }
            erro = nil
        } catch {
            erro = "Falhou o download: \(error.localizedDescription)"
        }
    }

    private func apagar(_ modelo: WhisperModelo) {
        do { try store.apagar(modelo) } catch { erro = error.localizedDescription }
        atualizar()
    }
}

// MARK: Slides

private struct SlidesSettings: View {
    @Environment(Definicoes.self) private var definicoes

    var body: some View {
        @Bindable var definicoes = definicoes
        Form {
            Section {
                LabeledContent("Sensibilidade") {
                    HStack {
                        Slider(value: $definicoes.slidesLimiar, in: 0.2...0.9, step: 0.05)
                        Text(definicoes.slidesLimiar.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 40)
                    }
                }
                Text("Distância mínima entre frames para contar como outro slide. Mais baixo apanha mudanças pequenas (e mais duplicados); mais alto junta slides parecidos. Por defeito: 0,45.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Analisar a cada \(definicoes.slidesIntervalo.formatted()) s", value: $definicoes.slidesIntervalo, in: 1...10, step: 1)
                Stepper("Máximo de \(definicoes.slidesMaximo) slides por aula", value: $definicoes.slidesMaximo, in: 5...100, step: 5)
                Button("Repor valores por defeito") {
                    let p = ConfigSlides()
                    definicoes.slidesLimiar = p.limiar
                    definicoes.slidesIntervalo = p.intervalo
                    definicoes.slidesMaximo = p.maximo
                }
            } footer: {
                Text("A zona da câmara do professor define-se por cadeira, em Editar cadeira… (no menu … da cadeira).")
            }
        }
        .formStyle(.grouped)
    }
}
