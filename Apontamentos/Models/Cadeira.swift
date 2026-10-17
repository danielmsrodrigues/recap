import Foundation

/// Conteúdo de `cadeira.json`.
struct CadeiraMeta: Codable, Hashable, Sendable {
    /// Um termo por linha. Pode levar tradução: `autovalor = valor próprio`.
    var glossario: String = ""
    /// Onde costuma estar a câmara do professor nas gravações desta cadeira.
    var regiaoIgnorar: RegiaoIgnorar = .automatica
    /// Escolhido à mão na folha da cadeira. Sem ele, vem da data da primeira aula (`Library.ler`).
    var semestre: Semestre?

    init(glossario: String = "", regiaoIgnorar: RegiaoIgnorar = .automatica, semestre: Semestre? = nil) {
        self.glossario = glossario
        self.regiaoIgnorar = regiaoIgnorar
        self.semestre = semestre
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glossario = try c.decodeIfPresent(String.self, forKey: .glossario) ?? ""
        regiaoIgnorar = try c.decodeIfPresent(RegiaoIgnorar.self, forKey: .regiaoIgnorar) ?? .automatica
        semestre = try c.decodeIfPresent(Semestre.self, forKey: .semestre)
    }
}

struct Cadeira: Identifiable, Hashable, Sendable {
    var nome: String
    var pasta: URL
    var meta: CadeiraMeta
    var aulas: [Aula]
    /// O de `meta.semestre` ou, sem ele, o deduzido das datas das aulas.
    var semestre: Semestre

    var id: URL { pasta }
}

/// Ano do curso e semestre (1.º ou 2.º), para arrumar as cadeiras na barra lateral.
struct Semestre: Codable, Hashable, Comparable, Sendable {
    var ano: Int
    var numero: Int

    var nome: String { "\(ano).º ano · \(numero).º semestre" }

    static func < (a: Semestre, b: Semestre) -> Bool { (a.ano, a.numero) < (b.ano, b.numero) }

    /// Ano letivo (o ano civil em que começa) e semestre de uma data: setembro a janeiro é o 1.º, fevereiro a agosto o 2.º.
    static func letivo(_ data: Date, calendario: Calendar = .current) -> (inicio: Int, numero: Int) {
        let c = calendario.dateComponents([.year, .month], from: data)
        let ano = c.year ?? 0, mes = c.month ?? 1
        if mes >= 9 { return (ano, 1) }
        return mes == 1 ? (ano - 1, 1) : (ano - 1, 2)
    }
}

struct Aula: Identifiable, Hashable, Sendable {
    var pasta: URL
    var cadeira: String
    var meta: AulaMeta
    var temTranscricao: Bool
    var temApontamentos: Bool

    var id: URL { pasta }
}
