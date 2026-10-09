import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Geração", systemImage: "sparkles") { GeracaoSettings() }
            Tab("Transcrição", systemImage: "waveform") { TranscricaoSettings() }
            Tab("Slides", systemImage: "rectangle.on.rectangle") { SlidesSettings() }
            Tab("Prompt", systemImage: "text.quote") { PromptSettings() }
        }
        .frame(width: 640)
    }
}

// MARK: Geração

private struct GeracaoSettings: View {
    @Environment(Definicoes.self) private var definicoes
    @State private var versaoClaude: String?
    @State private var chave = ""
    @State private var mensagem: String?
    @State private var entrada = ""
    @State private var saida = ""

    var body: some View {
        @Bindable var definicoes = definicoes
        Form {
            Section {
                Picker("Motor", selection: $definicoes.motor) {
                    ForEach(MotorTipo.allCases) { Text($0.nome).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(definicoes.motor == .claudeCode
                     ? "Usa o Claude Code instalado neste Mac e a tua subscrição (Pro/Max): sem custos à parte, conta para os limites de utilização."
                     : "Usa a API da Anthropic, paga por utilização com créditos à parte da subscrição.")
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

            Section("Modelo") {
                TextField("Modelo", text: $definicoes.modeloClaude, prompt: Text(Definicoes.modeloClaudePorDefeito))
                Picker("Esforço", selection: $definicoes.esforco) {
                    ForEach(Esforco.allCases) { Text($0.nome).tag($0) }
                }
                Text("Mais esforço dá apontamentos mais cuidados, mas gasta mais tokens de saída. \"Alto\" é o valor por defeito do Sonnet 5.5.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: carregarPrecos)
        .onChange(of: definicoes.modeloClaude) { carregarPrecos() }
    }

    @ViewBuilder private var apiSecao: some View {
        Section {
            if definicoes.temChaveAPI {
                LabeledContent("Chave API") {
                    HStack {
                        Text("Guardada na Keychain").foregroundStyle(.secondary)
                        Button("Remover", role: .destructive) {
                            do { try definicoes.apagarChaveAPI(); mensagem = nil } catch { mensagem = error.localizedDescription }
                        }
                    }
                }
            } else {
                SecureField("Chave API", text: $chave, prompt: Text("sk-ant-…"))
                Button("Guardar na Keychain") {
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
            Text("Cria uma chave em platform.claude.com → API Keys. Fica só na Keychain deste Mac.")
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
                Text("O modelo é descarregado na primeira transcrição, se ainda não estiver aqui. Fica em \(store.base.path).")
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
                Text("A zona da câmara do professor define-se por cadeira, no glossário (ícone de livro na barra lateral).")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Prompt

private struct PromptSettings: View {
    @State private var texto = ""
    @State private var guardado = ""
    @State private var erro: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt de sistema enviado ao Claude em cada geração. Fica em \(PromptStore.url.path).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
                Button("Descartar") { texto = guardado }.disabled(texto == guardado)
                Button("Guardar") {
                    do { try PromptStore.guardar(texto); guardado = texto; erro = nil } catch { erro = error.localizedDescription }
                }
                .keyboardShortcut("s")
                .disabled(texto == guardado)
            }
        }
        .padding(20)
        .onAppear(perform: carregar)
    }

    private func carregar() {
        texto = PromptStore.ler()
        guardado = texto
    }
}
