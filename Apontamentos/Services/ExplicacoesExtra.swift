import Foundation

/// O segundo passo dos apontamentos: o Claude relê-os só para encontrar os termos que ficaram sem explicação
/// ("Estratégico: donde se formulan las estrategias") e a app acrescenta-lhe, na mesma linha, o que quer dizer:
/// `📘 *Guía (p. N): …*` quando a guía de estudio o explica, `💡 *Ext.: …*` quando é conhecimento externo.
/// Ao gerar os apontamentos esta regra perde-se entre as outras; um pedido só com ela cumpre-a. Nunca apaga nem
/// reescreve texto: só acrescenta ao fim de linhas que já existem.
enum ExplicacoesExtra {
    struct Explicacao: Equatable, Sendable {
        /// Número da linha nos apontamentos, a contar de 1 (o "L" de `numeradas`).
        var linha: Int
        var explicacao: String
        var fonte: Fonte = .ext
    }

    enum Fonte: Equatable, Sendable {
        /// Conhecimento externo: nem a aula nem a guía o explicam.
        case ext
        /// Tirado da guía de estudio, com a página impressa quando o Claude a deu.
        case guia(pagina: Int?)
    }

    static let sistema = """
    Revês apontamentos de uma aula universitária, feitos a partir do que o professor disse. Quem os lê está a ver a matéria pela primeira vez e vai passá-los para o papel.

    A tua única tarefa: encontrar as linhas onde um termo fica sem explicação e dizer, para cada uma, o que o termo quer dizer na prática.

    Uma linha precisa de explicação quando quem a lê não fica a saber o que o termo é nem o que faz:
    - a frase repete a palavra do termo ("Estratégico: donde se formulan las estrategias", "Procedimientos: los procedimientos definidos para los registros");
    - ou só diz onde aparece ou a que pertence, sem dizer o que é;
    - ou explica com palavras técnicas que os apontamentos não explicaram antes.

    Não precisam de explicação: linhas que já explicam bem, exemplos, avisos, frases de contexto, títulos, imagens, as caixas 👀 (o que o professor só mencionou), linhas que já têm 💡 ou 📘, o glossário, as dúvidas e as perguntas de revisão. Também não as listas de nomes que o professor só enumerou (áreas, tipos, impostos) quando o nome já diz o que é ("Logística", "Producción").

    Escolhe no máximo 10 linhas: as que mais fazem falta para perceber a matéria. Mais explicações tornam os apontamentos confusos.

    Quando recebes secções da guía de estudio da cadeira, procura primeiro aí: se a guía explica o termo, a explicação vem dela (com as palavras dela, resumidas) e diz a página [p. N] onde está. Só quando a guía não o explica usas conhecimento externo.

    Cada explicação:
    - uma ou duas frases curtas, na língua dos apontamentos;
    - diz o que o termo é e o que faz na prática, com um exemplo do dia a dia se ajudar;
    - conhecimento padrão e certo, coerente com o que os apontamentos dizem; nada de matéria nova (teoremas, métodos, exercícios);
    - não repete o que a linha já diz.

    Responde só com JSON: uma lista com um objeto por linha, com as chaves "linha" (o número L da linha), "fonte" ("guia" ou "ext"), "pagina" (a página da guía, só quando a fonte é "guia") e "explicacao" (só o texto, sem 💡, 📘, "Ext." nem asteriscos). Se nenhuma linha precisar, responde [].
    """

    /// Os apontamentos com o número de cada linha à frente ("L12: …"), para o Claude responder com o número.
    static func numeradas(_ md: String) -> String {
        md.components(separatedBy: "\n").enumerated().map { "L\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
    }

    /// A mensagem com os apontamentos numerados. As instruções estão em português: a língua das explicações vai aqui.
    static func pedido(_ md: String, lingua: LinguaApontamentos, guia: GuiaDaAula?) -> String {
        var texto = "Apontamentos, com o número de cada linha. Escreve as explicações em \(lingua.nomeNoPrompt), a língua destes apontamentos.\n\n<apontamentos>\n\(numeradas(md))\n</apontamentos>"
        if let guia {
            texto += "\n\n\(guia.blocoParaPedido())\n\nSó usa Ext. quando a guía não explica o termo. Mesmo quando a explicação vem da guía, escreve-a em \(lingua.nomeNoPrompt)."
        }
        return texto
    }

    /// Pede as explicações ao Claude e põe-nas nos apontamentos.
    static func rever(_ md: String, lingua: LinguaApontamentos, guia: GuiaDaAula?, gerador: NotesGenerator,
                      aoRepetir: (Int, Double, ErroClaude) -> Void = { _, _, _ in }) async throws -> ResultadoApontamentos {
        var g = gerador
        g.maxTokens = 8_000
        let r = try await g.gerar(sistema: sistema, conteudo: [.texto(pedido(md, lingua: lingua, guia: guia))],
                                  aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: aoRepetir)
        return ResultadoApontamentos(markdown: aplicar(daResposta(r.markdown), em: md, lingua: lingua), geracao: r.geracao)
    }

    /// Lê a resposta (tolera ``` à volta e as chaves traduzidas). O que não se perceber fica de fora.
    static func daResposta(_ texto: String) -> [Explicacao] {
        guard let a = texto.firstIndex(of: "["), let b = texto.lastIndex(of: "]"), a < b,
              let lista = try? JSONSerialization.jsonObject(with: Data(texto[a...b].utf8)) as? [[String: Any]]
        else { return [] }
        return lista.compactMap { objeto in
            // A chave do número e a do texto, em qualquer língua: o número é o valor que se lê como inteiro.
            // "fonte" e "pagina" têm nomes fixos e leem-se primeiro; o resto, pelo valor.
            var fonte = Fonte.ext
            if (objeto["fonte"] as? String)?.lowercased().hasPrefix("gu") == true {
                let pagina = objeto["pagina"].flatMap { ($0 as? Int) ?? ($0 as? String).flatMap(numero) }
                fonte = .guia(pagina: pagina)
            }
            var linha: Int?
            var explicacao: String?
            for (chave, valor) in objeto.sorted(by: { $0.key < $1.key }) where chave != "fonte" && chave != "pagina" {
                if let n = valor as? Int { linha = linha ?? n }
                else if let s = valor as? String {
                    if let n = numero(s) { linha = linha ?? n } else { explicacao = explicacao ?? s }
                }
            }
            guard let linha, let texto = explicacao.map(limpar), !texto.isEmpty else { return nil }
            return Explicacao(linha: linha, explicacao: texto, fonte: fonte)
        }
    }

    /// "12" ou "L12" (o Claude às vezes copia o número tal como o viu).
    private static func numero(_ s: String) -> Int? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "L" || t.first == "l" { t.removeFirst() }
        return Int(t)
    }

    private static func limpar(_ s: String) -> String {
        var t = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        if t.hasPrefix("💡") || t.hasPrefix("📘") { t.removeFirst() }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
        if t.hasPrefix("Ext.:") { t = String(t.dropFirst(5)) }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
    }

    /// Os apontamentos com cada explicação no fim da sua linha (numa tabela, dentro da última célula).
    /// Títulos, imagens, fórmulas, código, caixas 👀 e 🔗, linhas que já têm 💡 ou 📘, cabeçalhos de tabelas e tudo o que
    /// vem a partir do glossário, das dúvidas ou das perguntas de revisão ficam como estão.
    static func aplicar(_ itens: [Explicacao], em md: String, lingua: LinguaApontamentos) -> String {
        var linhas = md.components(separatedBy: "\n")
        let fim = linhas.firstIndex(where: seccaoFinal) ?? linhas.count
        var dentroDeCodigo = Set<Int>()
        var aberto = false
        for (i, l) in linhas.enumerated() {
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { aberto.toggle(); dentroDeCodigo.insert(i) }
            else if aberto { dentroDeCodigo.insert(i) }
        }
        var feitas = Set<Int>()
        for item in itens {
            let i = item.linha - 1
            guard i >= 0, i < fim, !feitas.contains(i), !dentroDeCodigo.contains(i) else { continue }
            let seguinte = i + 1 < linhas.count ? linhas[i + 1] : ""
            guard pode(linhas[i], seguinte: seguinte) else { continue }
            var base = linhas[i]
            while base.last?.isWhitespace == true { base.removeLast() }
            let nota: String
            switch item.fonte {
            case .ext: nota = "💡 *Ext.: \(item.explicacao)*"
            case .guia(let pagina):
                let rotulo = RotulosApontamentos.rotulo("Guia", lingua) + (pagina.map { " (p. \($0))" } ?? "")
                nota = "📘 *\(rotulo): \(item.explicacao)*"
            }
            if base.hasPrefix("|"), base.hasSuffix("|") {
                base.removeLast()
                while base.last?.isWhitespace == true { base.removeLast() }
                linhas[i] = base + " " + nota + " |"
            } else {
                linhas[i] = base + " " + nota
            }
            feitas.insert(i)
        }
        return linhas.joined(separator: "\n")
    }

    private static func pode(_ linha: String, seguinte: String) -> Bool {
        let t = linha.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("![") || t.hasPrefix("$$") || t.contains("💡") || t.contains("📘") || t.contains("👀") { return false }
        if t.hasPrefix(NotasLigacoes.marca.trimmingCharacters(in: .whitespaces)) { return false }
        if separadorDeTabela(t) || (t.hasPrefix("|") && separadorDeTabela(seguinte.trimmingCharacters(in: .whitespaces))) { return false }
        return true
    }

    private static func separadorDeTabela(_ t: String) -> Bool {
        t.hasPrefix("|") && t.contains("-") && t.allSatisfy { "|-: ".contains($0) }
    }

    private static let finais = ["Glossário", "Dúvidas / pontos ambíguos", "Perguntas de revisão"].flatMap(RotulosApontamentos.todas)

    private static func seccaoFinal(_ linha: String) -> Bool {
        guard linha.hasPrefix("## ") else { return false }
        let titulo = linha.dropFirst(3)
        return finais.contains { titulo.hasPrefix($0) }
    }
}
