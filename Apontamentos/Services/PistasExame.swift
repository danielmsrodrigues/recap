import Foundation

/// "Sai no exame": o que o professor disse que entra no exame ("esto entra seguro", "lo pregunto siempre"), com o minuto
/// da aula. Um pedido próprio, só com esta tarefa, sobre a transcrição: dentro do pedido dos apontamentos perdia-se
/// (ver `ExplicacoesExtra`). Fica em `<aula>/exame.json`; uma lista vazia quer dizer "já procurado, nada".
enum PistasExame {
    struct Pista: Codable, Equatable, Hashable, Sendable {
        /// O segundo da aula em que foi dito.
        var tempo: Double
        /// As palavras do professor, na língua da aula.
        var citacao: String
        /// O que sai, em poucas palavras, na língua dos apontamentos.
        var descricao: String
    }

    static let sistema = """
    Lês a transcrição de uma aula universitária, com o minuto de cada frase. A tua única tarefa: encontrar os momentos em que o professor diz, ou deixa claro, que uma matéria vai sair no exame ou na avaliação.

    Contam:
    - quando o diz diretamente ("esto entra en el examen", "esto lo pregunto siempre", "esto cae seguro", "isto sai no teste");
    - quando insiste que algo é muito importante para a avaliação ("quedaos con esto para el examen", "esto hay que saberlo sí o sí");
    - quando descreve uma pergunta ou um exercício do exame ("os voy a pedir que paséis un decimal a fracción").

    Não contam: avisos gerais sobre o formato, as datas ou as regras do exame (quantas perguntas, que duração, se há consulta), nem frases como "esto es importante" sem ligação à avaliação.

    Para cada momento:
    - "tempo": o minuto da frase, tal como aparece na transcrição (mm:ss);
    - "citacao": as palavras do professor, curtas e exatas, na língua da aula;
    - "descricao": o que vai sair, em poucas palavras (o tema ou o tipo de exercício), na língua pedida.

    Responde só com JSON: uma lista com um objeto por momento, com as chaves "tempo", "citacao" e "descricao". Se não houver nenhum, responde [].
    """

    /// A transcrição com os minutos. As instruções estão em português: a língua das descrições vai aqui.
    static func pedido(_ t: Transcricao, lingua: LinguaApontamentos) -> String {
        "Transcrição da aula, com o minuto de cada frase. Escreve as descrições em \(lingua.nomeNoPrompt).\n\n<transcricao>\n\(t.textoComTimestamps)\n</transcricao>"
    }

    /// Pede as pistas ao Claude.
    static func procurar(_ t: Transcricao, lingua: LinguaApontamentos, gerador: NotesGenerator,
                         aoRepetir: (Int, Double, ErroClaude) -> Void = { _, _, _ in }) async throws -> (pistas: [Pista], geracao: Geracao) {
        var g = gerador
        g.maxTokens = 8_000
        let r = try await g.gerar(sistema: sistema, conteudo: [.texto(pedido(t, lingua: lingua))],
                                  aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: aoRepetir)
        // Cortada ou sem JSON: é um erro e não "nada sai no exame", senão a aula nunca mais era procurada.
        guard !r.geracao.truncada, let pistas = daResposta(r.markdown) else { throw ErroPistas.resposta }
        return (pistas, r.geracao)
    }

    enum ErroPistas: LocalizedError {
        case resposta
        var errorDescription: String? { "A resposta do Claude veio cortada ou num formato que não se lê." }
    }

    /// Lê a resposta (tolera ``` à volta e as chaves traduzidas: tiempo/time, cita/quote, descripción/description).
    /// As que não têm um minuto que se leia ficam de fora. nil se não houver uma lista JSON que se leia
    /// (um "[" no texto antes da lista não a estraga: tenta-se a partir de cada um).
    static func daResposta(_ texto: String) -> [Pista]? {
        guard let b = texto.lastIndex(of: "]") else { return nil }
        let lista = texto[..<b].indices.lazy
            .filter { texto[$0] == "[" }
            .compactMap { a in try? JSONSerialization.jsonObject(with: Data(texto[a...b].utf8)) as? [[String: Any]] }
            .first
        guard let lista else { return nil }
        func valor(_ objeto: [String: Any], _ nomes: [String]) -> String? {
            objeto.first { nomes.contains($0.key.lowercased().folding(options: .diacriticInsensitive, locale: nil)) }?.value as? String
        }
        return lista.compactMap { objeto in
            guard let minuto = valor(objeto, ["tempo", "tiempo", "time", "minuto"]),
                  let tempo = Timestamp.parse(minuto.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")))
            else { return nil }
            let citacao = valor(objeto, ["citacao", "cita", "quote", "citation"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let descricao = valor(objeto, ["descricao", "descripcion", "description"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !citacao.isEmpty || !descricao.isEmpty else { return nil }
            return Pista(tempo: tempo, citacao: citacao, descricao: descricao)
        }
    }

    struct Grupo: Identifiable {
        var cadeira: Cadeira
        var pistas: [(aula: Aula, pista: Pista)]
        var id: URL { cadeira.pasta }
    }

    /// As pistas de cada cadeira, pela ordem das aulas e, dentro de cada aula, pelo minuto. Cadeiras sem pistas ficam de fora.
    static func porCadeira(_ cadeiras: [Cadeira], ler: (URL) -> [Pista]? = Disco.lerPistasExame) -> [Grupo] {
        cadeiras.compactMap { cadeira in
            let pistas = cadeira.aulas
                .sorted { ($0.meta.data, $0.meta.criadaEm) < ($1.meta.data, $1.meta.criadaEm) }
                .flatMap { aula in (ler(aula.pasta) ?? []).sorted { $0.tempo < $1.tempo }.map { (aula: aula, pista: $0) } }
            return pistas.isEmpty ? nil : Grupo(cadeira: cadeira, pistas: pistas)
        }
    }
}

extension Disco {
    static let pistasExameJSON = "exame.json"

    /// nil: ainda não se procurou nesta aula; [] : procurou-se e não há nada.
    static func lerPistasExame(_ pasta: URL) -> [PistasExame.Pista]? {
        guard let dados = try? lerDados(pasta.appending(path: pistasExameJSON)) else { return nil }
        return try? decoder.decode([PistasExame.Pista].self, from: dados)
    }

    static func escreverPistasExame(_ pistas: [PistasExame.Pista], em pasta: URL) throws {
        try gravar(encoder.encode(pistas), em: pasta.appending(path: pistasExameJSON))
    }
}
