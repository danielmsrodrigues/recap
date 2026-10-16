import SwiftUI

/// Resultados da pesquisa global, na barra lateral, agrupados por aula.
struct ResultadosPesquisaView: View {
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    let termo: String

    @State private var resultados: [ResultadoPesquisa] = []
    @State private var aProcurar = false

    private var palavras: [String] { termo.split(whereSeparator: \.isWhitespace).map(String.init) }

    /// Por aula, pela ordem dos resultados (as mais recentes primeiro).
    private var grupos: [(pasta: URL, resultados: [ResultadoPesquisa])] {
        var ordem: [URL] = []
        var porAula: [URL: [ResultadoPesquisa]] = [:]
        for r in resultados {
            if porAula[r.pasta] == nil { ordem.append(r.pasta) }
            porAula[r.pasta, default: []].append(r)
        }
        return ordem.map { ($0, porAula[$0] ?? []) }
    }

    var body: some View {
        List {
            if resultados.isEmpty {
                Text(aProcurar ? "A procurar…" : "Nada encontrado em nenhuma aula.")
                    .foregroundStyle(.secondary)
            }
            ForEach(grupos, id: \.pasta) { grupo in
                Section {
                    ForEach(grupo.resultados) { r in
                        Button { abrir(r) } label: { linha(r) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    if let r = grupo.resultados.first {
                        Text("\(r.titulo) · \(r.cadeira)").lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .task(id: "\(termo)#\(library.versao)") {
            // Espera que se pare de escrever.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            aProcurar = true
            let aulas = library.cadeiras.flatMap(\.aulas).map {
                Pesquisa.AulaRef(pasta: $0.pasta, titulo: $0.meta.titulo, cadeira: $0.cadeira, data: $0.meta.data)
            }
            let fichas = library.cadeiras.map { Pesquisa.FichaRef(url: FichaCadeira.url($0.pasta), cadeira: $0.nome) }
            let encontrados = await Pesquisa.procurar(termo, em: aulas, fichas: fichas)
            guard !Task.isCancelled else { return }
            resultados = encontrados
            aProcurar = false
        }
    }

    private func linha(_ r: ResultadoPesquisa) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch r.onde {
            case .titulo: Image(systemName: "textformat").foregroundStyle(.secondary)
            case .apontamentos: Image(systemName: "doc.text").foregroundStyle(.secondary)
            case .ficha: Image(systemName: "info.circle").foregroundStyle(.secondary)
            case .transcricao(let t):
                Text(Timestamp.format(t)).font(.caption.monospacedDigit()).foregroundStyle(.tint)
            }
            Text(realcado(r.trecho)).font(.callout).lineLimit(3)
        }
        .contentShape(.rect)
        .help(ajuda(r.onde))
    }

    private func ajuda(_ onde: ResultadoPesquisa.Onde) -> String {
        switch onde {
        case .titulo: "Título da aula"
        case .apontamentos: "Nos apontamentos"
        case .ficha: "Na ficha da cadeira"
        case .transcricao: "Na transcrição"
        }
    }

    private func realcado(_ texto: String) -> AttributedString {
        var a = AttributedString(texto)
        for r in Pesquisa.realces(texto, palavras) {
            if let ra = Range(r, in: a) { a[ra].inlinePresentationIntent = .stronglyEmphasized }
        }
        return a
    }

    private func abrir(_ r: ResultadoPesquisa) {
        switch r.onde {
        case .titulo:
            navegacao.destino = DestinoAula(pasta: r.pasta, separador: .apontamentos)
        case .apontamentos:
            // Tal como está escrito (com acentos), para o realce encontrar o texto na página.
            navegacao.destino = DestinoAula(pasta: r.pasta, separador: .apontamentos, termos: Pesquisa.termosParaRealcar(r.trecho, palavras))
        case .transcricao(let t):
            navegacao.destino = DestinoAula(pasta: r.pasta, separador: .transcricao, tempo: t)
        case .ficha:
            navegacao.destino = DestinoAula(pasta: r.pasta, separador: .apontamentos, termos: Pesquisa.termosParaRealcar(r.trecho, palavras))
        }
    }
}
