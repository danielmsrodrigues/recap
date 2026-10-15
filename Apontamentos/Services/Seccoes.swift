import Foundation

/// Uma ligação a uma secção dos apontamentos, como o Claude a escreve nas respostas: `[Cadeia de valor](#cadeia-de-valor)`.
struct LigacaoSeccao: Equatable, Sendable {
    /// O destino do link, com ou sem `#` (pode vir com percent-encoding).
    var ancora: String
    /// O texto do link (o título da secção, normalmente).
    var texto: String
}

/// Pedido para a vista dos apontamentos ir a um título e o realçar por instantes.
struct PedidoSeccao: Equatable, Sendable {
    /// Posição do título entre os títulos de topo do documento (a mesma ordem na página renderizada).
    var indice: Int
    var id = UUID()
}

/// As secções (títulos) dos apontamentos e as âncoras com que o Claude se refere a elas.
/// As âncoras são como as do GitHub, mas sem acentos: "Valor não é benefício [03:01]" → `valor-nao-e-beneficio`.
/// Títulos repetidos levam `-2`, `-3`… pela ordem do documento.
enum Seccoes {
    struct Seccao: Equatable, Sendable {
        /// O n-ésimo título do documento (h1…h6 fora de citações e listas).
        var indice: Int
        var nivel: Int
        /// O título sem marcas de Markdown nem `[mm:ss]`.
        var titulo: String
        var ancora: String
    }

    static func lista(_ markdown: String) -> [Seccao] {
        var seccoes: [Seccao] = []
        var usadas: [String: Int] = [:]
        var cerca: Character?
        for linha in markdown.components(separatedBy: .newlines) {
            let sem = linha.drop { $0 == " " }
            // Blocos de código (``` ou ~~~): um `#` lá dentro não é título.
            if linha.count - sem.count <= 3, let c = sem.first, c == "`" || c == "~", sem.hasPrefix(String(repeating: c, count: 3)) {
                cerca = cerca == nil ? c : (cerca == c ? nil : cerca)
                continue
            }
            guard cerca == nil, linha.count - sem.count <= 3, let (nivel, texto) = titulo(sem) else { continue }
            let limpo = limpar(texto)
            let base = ancora(limpo).isEmpty ? "seccao" : ancora(limpo)
            usadas[base, default: 0] += 1
            let n = usadas[base] ?? 1
            seccoes.append(Seccao(indice: seccoes.count, nivel: nivel, titulo: limpo, ancora: n == 1 ? base : "\(base)-\(n)"))
        }
        return seccoes
    }

    /// `## Título ##` → (2, "Título"); nil se a linha não for um título ATX.
    private static func titulo(_ linha: Substring) -> (Int, Substring)? {
        let cardinais = linha.prefix { $0 == "#" }.count
        guard (1...6).contains(cardinais) else { return nil }
        let resto = linha.dropFirst(cardinais)
        guard resto.isEmpty || resto.first == " " || resto.first == "\t" else { return nil }
        var texto = resto.trimmingCharacters(in: .whitespaces)[...]
        // Os `#` de fecho, se estiverem separados por um espaço.
        if let fim = texto.lastIndex(where: { $0 != "#" }), fim < texto.index(before: texto.endIndex), texto[fim] == " " {
            texto = texto[...fim]
        } else if texto.allSatisfy({ $0 == "#" }) {
            texto = ""
        }
        return (cardinais, Substring(texto.trimmingCharacters(in: .whitespaces)))
    }

    /// O título como se lê: sem `[mm:ss]`, sem `**`/`*`/`` ` `` e com o LaTeX simplificado.
    static func limpar(_ texto: Substring) -> String {
        let semTempos = String(texto).replacing(/\[(?:\d{1,2}:)?\d{1,3}:\d{2}\]/, with: "")
        return Pesquisa.limparMarkdown(semTempos).replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Minúsculas sem acentos, só letras e números ASCII, separados por `-`.
    static func ancora(_ texto: String) -> String {
        let dobrado = texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_PT")).lowercased()
        var s = ""
        for c in dobrado.unicodeScalars {
            if c.isASCII, CharacterSet.alphanumerics.contains(c) {
                s.unicodeScalars.append(c)
            } else if !s.isEmpty, s.last != "-" {
                s.append("-")
            }
        }
        while s.last == "-" { s.removeLast() }
        return s
    }

    /// A lista das secções para o Claude, já no formato em que as deve ligar, indentada pelo nível.
    static func indice(_ seccoes: [Seccao]) -> String {
        let minimo = seccoes.map(\.nivel).min() ?? 1
        return seccoes.map { String(repeating: "  ", count: $0.nivel - minimo) + "- [\($0.titulo)](#\($0.ancora))" }
            .joined(separator: "\n")
    }

    /// A secção a que um link se refere. Primeiro a âncora exata (tolerando acentos e maiúsculas), depois o texto do link
    /// e, por fim, um título que contenha a âncora ou o texto como palavras inteiras (apontamentos regenerados depois
    /// da resposta podem ter mudado um título).
    static func resolver(_ ligacao: LigacaoSeccao, em seccoes: [Seccao]) -> Seccao? {
        var bruto = ligacao.ancora.trimmingCharacters(in: .whitespaces)
        if bruto.hasPrefix("#") { bruto.removeFirst() }
        let alvo = ancora(bruto.removingPercentEncoding ?? bruto)
        let texto = ancora(limpar(Substring(ligacao.texto)))
        for chave in [alvo, texto] where !chave.isEmpty {
            if let s = seccoes.first(where: { $0.ancora == chave }) { return s }
        }
        // Um título repetido sem o sufixo, ou um título que mudou um pouco.
        for chave in [alvo, texto] where chave.count >= 3 {
            let candidatos = seccoes.filter {
                let a = "-\($0.ancora)-", c = "-\(chave)-"
                return a.contains(c) || c.contains(a)
            }
            if let s = candidatos.min(by: { abs($0.ancora.count - chave.count) < abs($1.ancora.count - chave.count) }) { return s }
        }
        return nil
    }
}
