import Foundation

/// O que a guía de estudio traz para os apontamentos de uma aula: o texto das secções que a aula explicou ou
/// remeteu para a guía, e só o nome e a página das que mencionou (para a referência no fim das caixas 👀).
struct GuiaDaAula: Sendable, Equatable {
    enum Categoria: String, Sendable {
        /// O professor deu a matéria: a guía entra só no que falta.
        case explicada
        /// O professor mandou estudá-la pela guía: entra completa, com as tabelas.
        case remetida
    }

    struct Parte: Sendable, Equatable {
        var seccao: SeccaoGuia
        var categoria: Categoria
        /// As páginas da secção, cada uma precedida de "[p. N]" (ver `GuiaEstudo.texto`).
        var texto: String
    }

    var partes: [Parte]
    var mencionadas: [SeccaoGuia]
    /// Explicadas ou remetidas que não couberam em `maxCaracteres` (estão também em `mencionadas`, sem texto).
    var semEspaco: [SeccaoGuia] = []

    /// Texto da guía num pedido, no máximo (cerca de 15 mil tokens). O que não cabe fica só com o nome e a página.
    static let maxCaracteres = 60_000

    /// As partes pela ordem do índice, até `maxCaracteres`: primeiro as remetidas (precisam do texto todo), depois as
    /// explicadas (só lhes falta o que o professor não disse). As mencionadas também pela ordem do índice.
    /// nil se a aula não tocou nenhuma secção.
    static func montar(_ indice: IndiceGuia, paginas: [String], selecao: SelecaoGuia) -> GuiaDaAula? {
        // Uma secção nas duas listas conta como remetida (como em `SeccoesDaAula`).
        let categorias = Dictionary(selecao.explicadas.map { ($0, Categoria.explicada) } + selecao.remetidas.map { ($0, .remetida) },
                                    uniquingKeysWith: { _, remetida in remetida })
        var partes: [(posicao: Int, parte: Parte)] = []
        var mencionadas = Set(selecao.mencionadas)
        var total = 0
        var semEspaco: [Int] = []
        let ordem = categorias.keys.sorted { (categorias[$0] == .remetida ? 0 : 1, $0) < (categorias[$1] == .remetida ? 0 : 1, $1) }
        for i in ordem where indice.seccoes.indices.contains(i) {
            let s = indice.seccoes[i]
            let texto = GuiaEstudo.texto(s, indice: indice, paginas: paginas)
            if total + texto.count <= maxCaracteres {
                partes.append((i, Parte(seccao: s, categoria: categorias[i]!, texto: texto)))
                mencionadas.remove(i)
                total += texto.count
            } else {
                mencionadas.insert(i)
                semEspaco.append(i)
            }
        }
        let outras = mencionadas.sorted().filter { indice.seccoes.indices.contains($0) }.map { indice.seccoes[$0] }
        guard !partes.isEmpty || !outras.isEmpty else { return nil }
        return GuiaDaAula(partes: partes.sorted { $0.posicao < $1.posicao }.map(\.parte), mencionadas: outras,
                          semEspaco: semEspaco.sorted().map { indice.seccoes[$0] })
    }

    /// As páginas impressas que os apontamentos podem citar: as das partes e as das mencionadas.
    var paginasPermitidas: Set<Int> {
        (partes.map(\.seccao) + mencionadas).reduce(into: []) { r, s in r.formUnion(s.paginaInicio...max(s.paginaInicio, s.paginaFim)) }
    }

    /// Os ids das secções que os apontamentos podem citar (as enviadas, com ou sem texto).
    var idsPermitidos: Set<String> { Set((partes.map(\.seccao) + mencionadas).map(\.id)) }

    /// O bloco de texto da guía para um pedido ao Claude (apontamentos ou explicações 💡).
    func blocoParaPedido() -> String {
        var texto = "Guía de estudio da cadeira (material oficial). Cada página vem marcada com o número impresso, [p. N]: é esse que se cita."
        if !partes.isEmpty {
            texto += "\n\nSecções que esta aula explicou (categoria=\"explicada\") ou que o professor mandou estudar pela guía (categoria=\"remetida\"):"
            for p in partes {
                let s = p.seccao
                let paginas = s.paginaFim > s.paginaInicio ? "\(s.paginaInicio)–\(s.paginaFim)" : "\(s.paginaInicio)"
                texto += "\n\n<seccao id=\"\(Self.atributo(s.id))\" titulo=\"\(Self.atributo(s.titulo))\" paginas=\"\(paginas)\" categoria=\"\(p.categoria.rawValue)\">\n\(p.texto)\n</seccao>"
            }
        }
        if !mencionadas.isEmpty {
            texto += "\n\nOutras secções tocadas pela aula, sem texto (servem só para referências como `→ Guia <secção>, p. N`):\n"
                + mencionadas.map { "- \($0.id) \($0.titulo) (p. \($0.paginaInicio))" }.joined(separator: "\n")
        }
        return texto
    }

    /// Aspas dentro de um atributo partiriam a etiqueta.
    private static func atributo(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }
}
