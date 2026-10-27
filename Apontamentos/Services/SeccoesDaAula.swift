import Foundation

/// As secções da guía de estudio que uma aula tocou, como posições em `IndiceGuia.seccoes` (a contar de 0).
/// Sem repetidos, e cada posição está numa só lista (prioridade: remetidas > explicadas > mencionadas).
struct SelecaoGuia: Equatable, Sendable {
    /// O professor deu a matéria da secção na aula.
    var explicadas: [Int]
    /// O professor mandou estudá-la pela guía.
    var remetidas: [Int]
    /// O professor só a nomeou ou disse que se vai ver.
    var mencionadas: [Int]
}

/// O primeiro passo da guía: um pedido curto ao Claude, só com a lista numerada de secções e a transcrição,
/// para saber quais a aula explicou, quais deixou para a guía e quais só mencionou.
enum SeccoesDaAula {
    static let sistema = """
    Recebes o índice numerado (S1, S2, …) da guía de estudio de uma cadeira e a transcrição de uma aula. A tua única tarefa: dizer que secções da guía a aula tocou e de que maneira.

    Três categorias:
    - "explicadas": o professor deu a matéria da secção na aula (explicou-a, desenvolveu-a, deu exemplos).
    - "remetidas": o professor mandou estudar a secção pela guía ("eso está en la guía", "no lo vamos a leer", "ahí tienen una tabla"), ou deixou-a para os alunos lerem sozinhos.
    - "mencionadas": o professor só nomeou a secção ou disse que se vai ver, sem a explicar nem a remeter.

    Cada secção entra, no máximo, numa categoria. Se a secção foi explicada e depois remetida, é remetida. Fica de fora tudo o que a aula não tocou: na dúvida, não incluas.

    Responde só com JSON: {"explicadas":["S…"],"remetidas":["S…"],"mencionadas":["S…"]}, com os rótulos S do índice (por exemplo "S3"), nunca o número da secção (1.2). Listas vazias se nenhuma secção couber.
    """

    /// A lista numerada de secções ("S3: 1.2 Título (p. 7–9)") e a transcrição.
    static func pedido(_ indice: IndiceGuia, transcricao: Transcricao) -> String {
        let lista = indice.seccoes.enumerated().map { i, s in
            "S\(i + 1): \(s.id) \(s.titulo) (p. \(s.paginaInicio)–\(s.paginaFim))"
        }.joined(separator: "\n")
        return "Índice da guía:\n\n<indice>\n\(lista)\n</indice>\n\nTranscrição da aula:\n\n<transcricao>\n\(transcricao.textoComTimestamps)\n</transcricao>"
    }

    /// Pede a escolha ao Claude (esforço baixo e resposta curta: é só uma lista de números).
    /// Lança `ErroSelecao` se a resposta vier cortada ou sem JSON: a app avisa em vez de gerar sem guía em silêncio.
    static func escolher(_ indice: IndiceGuia, transcricao: Transcricao, gerador: NotesGenerator) async throws -> (selecao: SelecaoGuia, geracao: Geracao) {
        var g = gerador
        g.esforco = .low
        g.maxTokens = 2_000
        let r = try await g.gerar(sistema: sistema, conteudo: [.texto(pedido(indice, transcricao: transcricao))],
                                  aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: { _, _, _ in })
        guard !r.geracao.truncada, let selecao = daResposta(r.markdown, total: indice.seccoes.count) else { throw ErroSelecao.resposta }
        return (selecao, r.geracao)
    }

    enum ErroSelecao: LocalizedError {
        case resposta
        var errorDescription: String? { "a resposta do Claude não trazia a lista de secções" }
    }

    /// Lê a resposta (tolera ``` à volta e as chaves traduzidas). Aceita "S3", "3" ou 3; o que estiver fora
    /// de 1…total ou não se perceber fica de fora. nil se não houver nenhum objeto JSON.
    static func daResposta(_ texto: String, total: Int) -> SelecaoGuia? {
        var explicadas: [Int] = [], remetidas: [Int] = [], mencionadas: [Int] = []
        guard let a = texto.firstIndex(of: "{"), let b = texto.lastIndex(of: "}"), a < b,
              let objeto = try? JSONSerialization.jsonObject(with: Data(texto[a...b].utf8)) as? [String: Any]
        else { return nil }
        for (chave, valor) in objeto.sorted(by: { $0.key < $1.key }) {
            let posicoes = ((valor as? [Any]) ?? []).compactMap { posicao($0, total: total) }
            // Pelo início da chave, que muda pouco entre línguas (remetidas/remitidas/referred).
            switch chave.lowercased().prefix(3) {
            case "exp": explicadas = posicoes
            case "rem", "ref": remetidas = posicoes
            case "men": mencionadas = posicoes
            default: break
            }
        }
        var vistas = Set<Int>()
        func novas(_ l: [Int]) -> [Int] { l.filter { vistas.insert($0).inserted } }
        let r = novas(remetidas), e = novas(explicadas), m = novas(mencionadas)
        return SelecaoGuia(explicadas: e, remetidas: r, mencionadas: m)
    }

    /// "S3", "3" ou 3 -> posição 2; fora de 1…total -> nil.
    private static func posicao(_ valor: Any, total: Int) -> Int? {
        var n: Int?
        if let i = valor as? Int, !(valor is Bool) { n = i }
        else if var s = (valor as? String)?.trimmingCharacters(in: .whitespaces) {
            if s.first == "S" || s.first == "s" { s.removeFirst() }
            n = Int(s)
        }
        guard let n, n >= 1, n <= total else { return nil }
        return n - 1
    }
}
