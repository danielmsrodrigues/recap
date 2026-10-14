import SwiftUI

/// Perguntar à aula: conversa sobre a aula, com as respostas baseadas na transcrição, nos slides e nos apontamentos.
struct PerguntasView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void

    @State private var texto = ""
    @State private var perguntas: [PerguntaAula] = []
    @State private var confirmarApagar = false
    @FocusState private var focado: Bool

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(aula, .pergunta) }

    private static let sugestoes = [
        "Resume a aula em 3 frases",
        "Qual foi a parte mais difícil? Explica-a de forma simples",
        "Houve avisos de exames ou entregas?",
        "Que perguntas podem sair no exame sobre esta matéria?",
    ]

    private var podeEnviar: Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && emCurso == nil && definicoes.faltaParaGerar == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider()
            if perguntas.isEmpty && emCurso == nil {
                vazio
            } else {
                NotesWebView(markdown: conversa, emStreaming: emCurso != nil, aoClicarTimestamp: aoClicarTimestamp, modo: "conversa")
            }
            if let erro = estudo.erro(aula, .pergunta) {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
            campo
        }
        .background(.background)
        .task(id: estudo.versao) { perguntas = Disco.lerPerguntas(aula.pasta) }
        .confirmationDialog("Apagar a conversa desta aula?", isPresented: $confirmarApagar) {
            Button("Apagar", role: .destructive) { estudo.apagarPerguntas(aula) }
        }
    }

    private var cabecalho: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Perguntas").font(.headline)
                Text(aula.meta.titulo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !perguntas.isEmpty {
                Button("Nova conversa", systemImage: "square.and.pencil") { confirmarApagar = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(emCurso != nil)
                    .help("Apagar esta conversa e começar outra")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                    Button { enviar(s) } label: {
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

    private var campo: some View {
        HStack(spacing: 6) {
            TextField("Pergunta sobre esta aula…", text: $texto)
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
        var md = perguntas.map { Self.bloco($0.pergunta) + $0.resposta }.joined(separator: "\n\n")
        if let emCurso, let pergunta = emCurso.pergunta {
            md += (md.isEmpty ? "" : "\n\n") + Self.bloco(pergunta)
                + (emCurso.texto.isEmpty ? "<div class=\"a-pensar\"><span></span><span></span><span></span></div>" : emCurso.texto)
        }
        return md
    }

    private static func bloco(_ pergunta: String) -> String {
        let escapada = pergunta.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<div class=\"pergunta\">\(escapada)</div>\n\n"
    }

    private func enviar(_ texto: String) {
        let pergunta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pergunta.isEmpty, emCurso == nil, definicoes.faltaParaGerar == nil else { return }
        estudo.perguntar(pergunta, sobre: aula)
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
            if let emCurso, !emCurso.texto.isEmpty {
                NotesWebView(markdown: emCurso.texto, emStreaming: true, aoClicarTimestamp: aoClicarTimestamp)
            } else if emCurso != nil {
                ContentUnavailableView("A criar exercícios…", systemImage: "hourglass",
                                       description: Text("O texto aparece aqui à medida que chega."))
                    .frame(maxHeight: .infinity)
            } else if let markdown {
                NotesWebView(markdown: markdown, aoClicarTimestamp: aoClicarTimestamp)
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
                Button("Outros exercícios", systemImage: "arrow.clockwise") { estudo.gerarExercicios(aula) }
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
                Button("Criar exercícios") { estudo.gerarExercicios(aula) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
