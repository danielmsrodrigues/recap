import SwiftUI

/// Ir para um momento da transcrição. O `id` deixa repetir o mesmo momento (clicar duas vezes no mesmo `[mm:ss]`).
struct SaltoTempo: Equatable {
    var segundos: Double
    var id = UUID()
}

struct TranscricaoView: View {
    let transcricao: Transcricao
    /// Momento a mostrar (um `[mm:ss]` clicado, um resultado da pesquisa).
    var irPara: SaltoTempo?
    @State private var pesquisa = ""
    @State private var destacado: Int?

    private var segmentos: [(Int, Segmento)] {
        let indexados = Array(transcricao.segmentos.enumerated())
        let termo = pesquisa.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return indexados }
        return indexados.filter { $0.1.texto.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Pesquisar na transcrição", text: $pesquisa)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Text("\(transcricao.segmentos.count) segmentos · \(transcricao.modelo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Copiar tudo", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcricao.textoComTimestamps, forType: .string)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                List(segmentos, id: \.0) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Timestamp.format(s.inicio))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tint)
                        if s.orador == .aluno {
                            Text("Aluno")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .background(.quaternary, in: .capsule)
                                .help("Identificado pela voz como um aluno (pode falhar)")
                        }
                        Text(s.texto)
                            .foregroundStyle(s.orador == .aluno ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(i == destacado ? Color.accentColor.opacity(0.18) : nil)
                    .id(i)
                }
                .listStyle(.inset)
                .task(id: irPara) {
                    guard let irPara else { return }
                    // Sem filtro: o segmento tem de estar na lista para se poder ir até ele.
                    pesquisa = ""
                    let i = transcricao.segmentos.lastIndex { $0.inicio <= irPara.segundos + 0.5 } ?? 0
                    destacado = i
                    try? await Task.sleep(for: .milliseconds(100))
                    withAnimation { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }
}
