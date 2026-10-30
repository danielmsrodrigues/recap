import Foundation

/// Os apontamentos como texto para ouvir: sem os sinais do Markdown, das ligações, dos minutos, das imagens, do código,
/// das fórmulas em bloco nem dos emojis das caixas. A voz do sistema leria "asterisco", "aspas" ou "cardinal".
/// Um trecho por secção (`## …`), com o título à parte, para se poder saltar de secção em secção.
enum TextoFalado {
    struct Trecho: Equatable, Sendable {
        /// O título da secção; nil antes da primeira (o título da aula, se houver).
        var titulo: String?
        var texto: String
    }

    static func trechos(_ md: String) -> [Trecho] {
        var trechos: [Trecho] = []
        var titulo: String?
        var frases: [String] = []
        var emCodigo = false
        var emFormula = false

        func fechar() {
            let texto = frases.joined(separator: " ")
            if titulo != nil || !texto.isEmpty { trechos.append(Trecho(titulo: titulo, texto: texto)) }
            frases = []
        }

        for bruta in md.components(separatedBy: .newlines) {
            let linha = bruta.trimmingCharacters(in: .whitespaces)
            if linha.hasPrefix("```") { emCodigo.toggle(); continue }
            if emCodigo { continue }
            // Fórmulas em bloco: `$$` numa linha própria abre e fecha; `$$…$$` numa linha só salta-se.
            if linha.hasPrefix("$$") {
                if !(linha.count > 4 && linha.hasSuffix("$$")) { emFormula.toggle() }
                continue
            }
            if emFormula || linha.isEmpty || linha.hasPrefix("![") { continue }
            if linha.hasPrefix("|") {
                // A linha de separação do cabeçalho não se lê; as outras, célula a célula.
                if linha.allSatisfy({ "|-: ".contains($0) }) { continue }
                let celulas = linha.split(separator: "|").map { limpar(String($0)) }.filter { !$0.isEmpty }
                if !celulas.isEmpty { frases.append(frase(celulas.joined(separator: ", "))) }
                continue
            }
            if linha.hasPrefix("## ") {
                fechar()
                titulo = limpar(String(linha.dropFirst(3)))
                continue
            }
            var texto = linha
            if texto.hasPrefix("#") { texto = String(texto.drop { $0 == "#" }) }
            if texto.hasPrefix(">") { texto = String(texto.drop { $0 == ">" }) }
            // Marcas de lista: "- ", "* ", "+ ", "1. ", "2) ".
            texto = texto.trimmingCharacters(in: .whitespaces).replacing(/^([-*+]|\d+[.)])\s+/, with: "")
            let limpo = limpar(texto)
            if !limpo.isEmpty { frases.append(frase(limpo)) }
        }
        fechar()
        return trechos
    }

    /// Uma linha sem nada que a voz leria como sinal.
    static func limpar(_ s: String) -> String {
        var t = s
        t = t.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        t = t.replacing(/\[(?:\d{1,2}:)?\d{1,3}:\d{2}\]/, with: "")
        t = t.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
        t = t.replacing(/<[^>]+>/, with: " ")
        t = t.replacing(/\$([^$]*)\$/) { String($0.output.1) }
        t = t.replacingOccurrences(of: "()", with: "")
        for (de, para) in [("—", ", "), ("–", ", "), ("·", ", "), ("(", ", "), (")", ", "), ("_", " ")] {
            t = t.replacingOccurrences(of: de, with: para)
        }
        let apagar = Set("*`\"«»“”„#[]{}\\^$|><~")
        t = String(String.UnicodeScalarView(t.unicodeScalars.filter { s in
            let p = s.properties
            let emoji = p.isEmojiPresentation || (p.isEmoji && s.value >= 0x2100) || s.value == 0xFE0F || s.value == 0x200D
            return !emoji && !apagar.contains(Character(s))
        }))
        t = t.replacing(/\s+/, with: " ")
        t = t.replacing(/\s+([,.:;!?])/) { String($0.output.1) }
        t = t.replacing(/,+/, with: ",")
        t = t.replacing(/,([.:;!?])/) { String($0.output.1) }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
    }

    /// Acaba em pontuação, para a voz fazer a pausa.
    private static func frase(_ s: String) -> String {
        guard let ultimo = s.last, !".!?:;…".contains(ultimo) else { return s }
        return s + "."
    }

    /// A voz na língua dos apontamentos.
    static func idiomaVoz(_ lingua: LinguaApontamentos) -> String {
        switch lingua {
        case .ptPT: "pt-PT"
        case .ptBR: "pt-BR"
        case .es: "es-ES"
        case .en: "en-GB"
        }
    }
}
