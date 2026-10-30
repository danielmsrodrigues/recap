import SwiftUI

/// Perguntar à cadeira inteira, ao lado de "Sobre a cadeira". As respostas citam a aula e o minuto; clicar leva lá.
struct PerguntasCadeiraView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    @Environment(Navegacao.self) private var navegacao
    let cadeira: Cadeira

    @State private var texto = ""
    @State private var perguntas: [PerguntaAula] = []
    @State private var confirmarApagar = false
    @FocusState private var focado: Bool

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(cadeira) }

    private static let sugestoes = [
        "Que temas já foram dados, e em que aulas?",
        "O que é que os professores disseram que sai no exame?",
        "Explica-me o tema mais difícil até agora, com um exemplo",
        "Faz-me 5 perguntas de exame sobre a matéria toda",
    ]

    private var podeEnviar: Bool {
        !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && emCurso == nil && definicoes.faltaParaGerar == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if perguntas.isEmpty && emCurso == nil {
                vazio
            } else {
                HStack {
                    Text(perguntas.count == 1 ? "1 pergunta" : "\(perguntas.count) perguntas").foregroundStyle(.secondary)
                    Spacer()
                    Button("Nova conversa", systemImage: "square.and.pencil") { confirmarApagar = true }
                        .buttonStyle(.borderless)
                        .disabled(emCurso != nil)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                // Um [mm:ss] solto não diz de que aula é: só os links das respostas levam a algum lado.
                NotesWebView(markdown: conversa, emStreaming: emCurso != nil, modo: "conversa", aoClicarSeccao: { ligacao in
                    if let destino = Estudo.destino(ligacao, aulas: cadeira.aulas) { navegacao.destino = destino }
                })
            }
            if let erro = estudo.erro(cadeira) {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
            campo
        }
        .background(.background)
        .task(id: estudo.versao) { perguntas = Disco.lerPerguntasCadeira(cadeira.pasta) }
        .confirmationDialog("Apagar a conversa sobre esta cadeira?", isPresented: $confirmarApagar) {
            Button("Apagar", role: .destructive) { estudo.apagarPerguntas(cadeira) }
        }
    }

    private var conversa: String {
        var md = perguntas.map { Self.bolha($0.pergunta) + $0.resposta }.joined(separator: "\n\n")
        if let emCurso, let pergunta = emCurso.pergunta {
            md += (md.isEmpty ? "" : "\n\n") + Self.bolha(pergunta)
                + (emCurso.texto.isEmpty ? "<div class=\"a-pensar\"><span></span><span></span><span></span></div>" : emCurso.texto)
        }
        return md
    }

    private static func bolha(_ pergunta: String) -> String {
        let seguro = pergunta.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return "<div class=\"pergunta\">\(seguro)</div>\n\n"
    }

    private var vazio: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "books.vertical").font(.system(size: 30)).foregroundStyle(.tint)
            Text("Pergunta o que quiseres sobre a cadeira").font(.headline).multilineTextAlignment(.center)
            Text("As respostas vêm dos apontamentos de todas as aulas e da ficha, e dizem de que aula vem cada coisa, com o minuto.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.sugestoes, id: \.self) { s in
                    Button { enviar(s) } label: {
                        Text(s).font(.callout).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(emCurso != nil || definicoes.faltaParaGerar != nil)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var campo: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pergunta sobre a cadeira…", text: $texto, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($focado)
                .onSubmit { enviar(texto) }
            if emCurso != nil {
                Button("Parar", systemImage: "stop.circle.fill") { estudo.cancelar(cadeira) }
                    .labelStyle(.iconOnly)
            } else {
                Button("Enviar", systemImage: "arrow.up.circle.fill") { enviar(texto) }
                    .labelStyle(.iconOnly)
                    .disabled(!podeEnviar)
            }
        }
        .font(.title3)
        .padding(12)
    }

    private func enviar(_ pergunta: String) {
        let p = pergunta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, emCurso == nil else { return }
        texto = ""
        estudo.perguntar(p, aCadeira: cadeira)
    }
}
