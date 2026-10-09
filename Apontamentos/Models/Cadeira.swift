import Foundation

/// Conteúdo de `cadeira.json`.
struct CadeiraMeta: Codable, Hashable, Sendable {
    /// Um termo por linha. Pode levar tradução: `autovalor = valor próprio`.
    var glossario: String = ""
    /// Onde costuma estar a câmara do professor nas gravações desta cadeira.
    var regiaoIgnorar: RegiaoIgnorar = .automatica

    init(glossario: String = "", regiaoIgnorar: RegiaoIgnorar = .automatica) {
        self.glossario = glossario
        self.regiaoIgnorar = regiaoIgnorar
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glossario = try c.decodeIfPresent(String.self, forKey: .glossario) ?? ""
        regiaoIgnorar = try c.decodeIfPresent(RegiaoIgnorar.self, forKey: .regiaoIgnorar) ?? .automatica
    }
}

struct Cadeira: Identifiable, Hashable, Sendable {
    var nome: String
    var pasta: URL
    var meta: CadeiraMeta
    var aulas: [Aula]

    var id: URL { pasta }
}

struct Aula: Identifiable, Hashable, Sendable {
    var pasta: URL
    var cadeira: String
    var meta: AulaMeta
    var temTranscricao: Bool
    var temApontamentos: Bool

    var id: URL { pasta }
}
