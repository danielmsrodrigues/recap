import SwiftUI
import UniformTypeIdentifiers

/// As três secções do painel Estudo: todas pedem ao Claude algo sobre a aula aberta.
enum SeccaoEstudo: String, CaseIterable, Identifiable {
    case perguntas = "Perguntas"
    case exercicios = "Exercícios"
    case ligacoes = "Ligações"
    var id: String { rawValue }
}

/// O painel à direita da aula: perguntas, exercícios e ligações com as outras aulas.
struct PainelEstudo: View {
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void
    var aoClicarSeccao: (LigacaoSeccao) -> Void
    var aoAbrirAula: (URL) -> Void
    @AppStorage("seccaoEstudo") private var seccaoGuardada = SeccaoEstudo.perguntas.rawValue

    private var seccao: Binding<SeccaoEstudo> {
        Binding(get: { SeccaoEstudo(rawValue: seccaoGuardada) ?? .perguntas }, set: { seccaoGuardada = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Secção", selection: seccao) {
                ForEach(SeccaoEstudo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            switch seccao.wrappedValue {
            case .perguntas: PerguntasView(aula: aula, aoClicarTimestamp: aoClicarTimestamp, aoClicarSeccao: aoClicarSeccao)
            case .exercicios: ExerciciosView(aula: aula, aoClicarTimestamp: aoClicarTimestamp)
            case .ligacoes: LigacoesView(aula: aula, aoClicarTimestamp: aoClicarTimestamp, aoAbrirAula: aoAbrirAula)
            }
        }
        .background(.background)
    }
}

/// Perguntar à aula: conversa sobre a aula, com as respostas baseadas na transcrição, nos slides e nos apontamentos.
struct PerguntasView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void
    /// Um link para uma secção dos apontamentos numa resposta.
    var aoClicarSeccao: (LigacaoSeccao) -> Void

    @State private var texto = ""
    @State private var perguntas: [PerguntaAula] = []
    @State private var confirmarApagar = false
    @State private var erroPDF: String?
    @FocusState private var focado: Bool

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(aula, .pergunta) }
    /// Trecho selecionado nos apontamentos ou na transcrição, à espera da pergunta.
    private var citacao: CitacaoPergunta? { estudo.citacao(aula) }

    private static let sugestoes = [
        "Resume a aula em 3 frases",
        "Qual foi a parte mais difícil? Explica-a de forma simples",
        "Houve avisos de exames ou entregas?",
        "Que perguntas podem sair no exame sobre esta matéria?",
    ]

    private var podeEnviar: Bool {
        Estudo.pergunta(texto, citacao: citacao) != nil && emCurso == nil && definicoes.faltaParaGerar == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if perguntas.isEmpty && emCurso == nil {
                vazio
            } else {
                cabecalho
                Divider()
                NotesWebView(markdown: conversa, emStreaming: emCurso != nil, aoClicarTimestamp: aoClicarTimestamp, modo: "conversa",
                             aoClicarSeccao: aoClicarSeccao, aoGuardarPDF: guardarPDF)
            }
            if let erro = erroPDF ?? estudo.erro(aula, .pergunta) {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
            if let citacao { trecho(citacao) }
            campo
        }
        .background(.background)
        .task(id: estudo.versao) { perguntas = Disco.lerPerguntas(aula.pasta) }
        // Um trecho escolhido (ou o painel aberto por causa dele): o cursor vai para o campo.
        .task(id: estudo.pedidosCitacao) {
            guard citacao != nil, estudo.consumirFoco() else { return }
            try? await Task.sleep(for: .milliseconds(80))
            focado = true
        }
        #if DEBUG
        .task {
            // `APONTAMENTOS_PERGUNTAR="<pergunta>"`: faz essa pergunta à aula aberta (o mesmo que escrevê-la e carregar ↩).
            guard let p = ProcessInfo.processInfo.environment["APONTAMENTOS_PERGUNTAR"] else { return }
            try? await Task.sleep(for: .seconds(1))
            enviar(p, citacao: nil)
        }
        #endif
        .confirmationDialog("Apagar a conversa desta aula?", isPresented: $confirmarApagar) {
            Button("Apagar", role: .destructive) { estudo.apagarPerguntas(aula) }
        }
    }

    /// Só com conversa: o nome da secção já está no seletor do painel, e a aula é a que está aberta ao lado.
    private var cabecalho: some View {
        HStack {
            Text(perguntas.count == 1 ? "1 pergunta" : "\(perguntas.count) perguntas").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Nova conversa", systemImage: "square.and.pencil") { confirmarApagar = true }
                .buttonStyle(.borderless)
                .disabled(emCurso != nil)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var vazio: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkle.text.clipboard")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Pergunta o que quiseres sobre esta aula")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("As respostas vêm da transcrição, dos slides e dos apontamentos, com os minutos da aula.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.sugestoes, id: \.self) { s in
                    // As sugestões são sobre a aula toda, não sobre o trecho escolhido.
                    Button { enviar(s, citacao: nil) } label: {
                        Text(s)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(definicoes.faltaParaGerar != nil)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trecho(_ c: CitacaoPergunta) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.legenda.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(c.textoLimpo)
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Tirar o trecho", systemImage: "xmark.circle.fill") { estudo.tirarCitacao(aula) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Perguntar sem este trecho")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 26)
        .padding(.top, 10)
    }

    private var campo: some View {
        HStack(spacing: 6) {
            TextField(citacao == nil ? "Pergunta sobre esta aula…" : "Pergunta sobre o trecho (↩ para o explicar)", text: $texto)
                .textFieldStyle(.plain)
                // O .title2 do HStack é só para os ícones dos botões.
                .font(.body)
                .focused($focado)
                .onSubmit { enviar(texto) }
            if emCurso != nil {
                Button("Parar", systemImage: "stop.circle.fill") { estudo.cancelar(aula, .pergunta) }
                    .help("Parar a resposta")
            } else {
                Button("Perguntar", systemImage: "arrow.up.circle.fill") { enviar(texto) }
                    .foregroundStyle(podeEnviar ? Color.accentColor : Color.secondary)
                    .disabled(!podeEnviar)
                    .help("Perguntar (↩)")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title2)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: .capsule)
        .overlay(Capsule().strokeBorder(focado ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .padding(12)
        .font(.body)
    }

    /// A conversa toda num só documento (uma vista web em vez de uma por resposta).
    private var conversa: String {
        var md = perguntas.enumerated().map { i, p in
            Self.bloco(p.pergunta, p.citacao) + p.resposta
                + (p.documentoPDF == nil ? "" : "\n\n<div class=\"guardar-pdf\"><button data-resposta=\"\(i)\">Guardar PDF…</button></div>")
        }.joined(separator: "\n\n")
        if let emCurso, let pergunta = emCurso.pergunta {
            md += (md.isEmpty ? "" : "\n\n") + Self.bloco(pergunta, emCurso.citacao)
                + (emCurso.texto.isEmpty ? "<div class=\"a-pensar\"><span></span><span></span><span></span></div>" : emCurso.texto)
        }
        return md
    }

    /// A pergunta numa bolha, com o trecho citado por cima (o `[mm:ss]` da legenda fica clicável).
    private static func bloco(_ pergunta: String, _ citacao: CitacaoPergunta?) -> String {
        let trecho = citacao.map {
            "<div class=\"citacao\"><span class=\"origem\">\(html($0.legenda))</span>\(html($0.textoLimpo))</div>"
        } ?? ""
        return "<div class=\"pergunta\">\(trecho)\(html(pergunta))</div>\n\n"
    }

    private static func html(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Guarda em PDF uma resposta pedida assim, com o nome do seu título, e abre-o.
    private func guardarPDF(_ indice: Int) {
        guard perguntas.indices.contains(indice), let documento = perguntas[indice].documentoPDF else { return }
        let painel = NSSavePanel()
        painel.nameFieldStringValue = Disco.nomeDePasta(TituloAula.tema(documento) ?? aula.meta.titulo) + ".pdf"
        painel.allowedContentTypes = [.pdf]
        guard painel.runModal() == .OK, let destino = painel.url else { return }
        erroPDF = nil
        Task {
            do {
                try await ExportadorPDF.exportar(markdown: documento, pastaAula: aula.pasta, para: destino)
                NSWorkspace.shared.open(destino)
            } catch {
                erroPDF = "Não foi possível guardar o PDF: \(error.localizedDescription)"
            }
        }
    }

    private func enviar(_ texto: String) { enviar(texto, citacao: citacao) }

    private func enviar(_ texto: String, citacao: CitacaoPergunta?) {
        guard let pergunta = Estudo.pergunta(texto, citacao: citacao), emCurso == nil, definicoes.faltaParaGerar == nil else { return }
        estudo.perguntar(pergunta, sobre: aula, citacao: citacao)
        self.texto = ""
    }
}

/// Exercícios extra da aula, gerados a pedido (`exercicios.md`).
struct ExerciciosView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void

    @State private var markdown: String?

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(aula, .exercicios) }

    var body: some View {
        VStack(spacing: 0) {
            if markdown != nil || emCurso != nil {
                barra
                Divider()
            }
            // A mesma vista web para o texto a chegar e para o guardado (ver AulaDetailView).
            if let texto = emCurso?.texto.isEmpty == false ? emCurso?.texto : (emCurso == nil ? markdown : nil) {
                NotesWebView(markdown: texto, emStreaming: emCurso != nil, aoClicarTimestamp: aoClicarTimestamp)
            } else if emCurso != nil {
                ContentUnavailableView("A criar exercícios…", systemImage: "hourglass",
                                       description: Text("O texto aparece aqui à medida que chega."))
                    .frame(maxHeight: .infinity)
            } else {
                vazio.frame(maxHeight: .infinity)
            }
        }
        .task(id: estudo.versao) { markdown = Disco.lerTexto(Disco.exerciciosMD, em: aula.pasta) }
    }

    private var barra: some View {
        HStack {
            if let erro = estudo.erro(aula, .exercicios) {
                Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                Text("Clica em \"Ver resolução\" depois de tentares cada exercício.").foregroundStyle(.secondary)
            }
            Spacer()
            if emCurso != nil {
                Button("Parar", systemImage: "stop.circle") { estudo.cancelar(aula, .exercicios) }
            } else {
                Button("Gerar outros", systemImage: "arrow.clockwise") { estudo.gerarExercicios(aula) }
                    .disabled(definicoes.faltaParaGerar != nil)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var vazio: some View {
        ContentUnavailableView {
            Label("Exercícios para treinar", systemImage: "pencil.and.list.clipboard")
        } description: {
            Text(estudo.erro(aula, .exercicios) ?? "Exercícios parecidos com os da aula, do mais fácil ao mais difícil, com a resolução escondida até a abrires. Só usam matéria desta aula.")
        } actions: {
            if definicoes.faltaParaGerar != nil {
                SettingsLink { Text("Abrir Definições…") }
            } else {
                Button("Gerar exercícios") { estudo.gerarExercicios(aula) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
