import SwiftUI

/// O progresso do programa, em "Sobre a cadeira" (só com guia): uma linha com "Vistos N de M temas" e a barra;
/// aberta, cada tema e subtema da guia com o seu estado e as aulas onde apareceu.
struct ProgressoGuiaView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Library.self) private var library
    let cadeira: Cadeira
    @State private var aberto = false
    @State private var temas: [ProgressoGuia.Tema] = []

    var body: some View {
        let principais = temas.filter { !$0.subtema }
        let vistos = principais.filter { $0.estado == .vista }.count
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $aberto) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(temas) { linha($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
                procura
            } label: {
                HStack(spacing: 10) {
                    Text(ProgressoGuia.resumo(temas)).font(.callout.weight(.semibold))
                    ProgressView(value: Double(vistos), total: Double(max(principais.count, 1)))
                        .frame(maxWidth: 180)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .task(id: [estudo.versao, library.versao]) { calcular() }
    }

    private func calcular() {
        guard let indice = ProgressoGuia.indiceGuardado(cadeira.pasta) else { temas = []; return }
        let aulas = cadeira.aulas.compactMap { a in Disco.lerSeccoesGuia(a.pasta).map { (a, $0) } }
        temas = ProgressoGuia.calcular(indice, aulas: aulas)
    }

    private func linha(_ t: ProgressoGuia.Tema) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch t.estado {
                case .vista: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .emCurso: Image(systemName: "circle.lefthalf.filled").foregroundStyle(.orange)
                case .porVer: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(t.estado == .vista ? "Visto" : t.estado == .emCurso ? "Em curso" : "Por ver")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(t.seccao.id) \(ProgressoGuia.titulo(t.seccao.titulo))")
                    .fontWeight(t.subtema ? .regular : .semibold)
                Text(t.aulas.isEmpty ? "Ainda não dado: estuda-se pela guia (p. \(t.seccao.paginaInicio)–\(t.seccao.paginaFim))"
                     : t.aulas.map { "Aula \(library.numeroDaAula($0))" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, t.subtema ? 18 : 0)
    }

    /// As aulas gravadas antes disto ainda não dizem que secções deram: no Mac, vê-se nelas.
    @ViewBuilder private var procura: some View {
        let porVer = estudo.aulasSemSeccoesGuia(cadeira)
        if let p = estudo.procuraGuia[cadeira.pasta] {
            HStack(spacing: 8) {
                ProgressView(value: Double(p.feitas), total: Double(max(p.total, 1)))
                Text("A ver as aulas anteriores: \(p.feitas) de \(p.total)").font(.caption).monospacedDigit()
            }
        } else if !porVer.isEmpty {
            #if os(macOS)
            Button(porVer.count == 1 ? "Ver 1 aula anterior" : "Ver as \(porVer.count) aulas anteriores") { estudo.procurarSeccoesGuia(cadeira) }
            #else
            Text("Há \(porVer.count) aulas anteriores por ver: faz-se no Mac, em \"Sobre a cadeira\".").font(.caption).foregroundStyle(.secondary)
            #endif
            if let erro = estudo.erroGuia[cadeira.pasta] {
                Text(erro).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
