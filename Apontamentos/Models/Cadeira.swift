import Foundation

/// Conteúdo de `cadeira.json`.
struct CadeiraMeta: Codable, Hashable, Sendable {
    /// Um termo por linha. Pode levar tradução: `autovalor = valor próprio`.
    var glossario: String = ""
    /// Onde costuma estar a câmara do professor nas gravações desta cadeira.
    var regiaoIgnorar: RegiaoIgnorar = .automatica
    /// Escolhido à mão na folha da cadeira. Sem ele, vem da data da primeira aula (`Library.ler`).
    /// Escolhido em "Só por ano", fica com `numero` 0 e o semestre continua a vir das datas.
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

/// Como se arrumam as cadeiras na barra lateral. Um mestrado de um ano, por exemplo, não tem semestres.
enum OrganizacaoCurso: String, CaseIterable, Identifiable, Sendable {
    case anoESemestre, ano, nenhuma
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .anoESemestre: "Por ano e semestre"
        case .ano: "Só por ano"
        case .nenhuma: "Sem divisão"
        }
    }

    /// Nome do submenu da cadeira ("Semestre" ou "Ano").
    var rotulo: String { self == .ano ? "Ano" : "Semestre" }

    /// As escolhas manuais para uma cadeira, até ao ano `ate` (pelo menos o 4.º).
    func opcoes(ate: Int) -> [Semestre] {
        let anos = 1...max(4, ate)
        switch self {
        case .anoESemestre: return anos.flatMap { a in [1, 2].map { Semestre(ano: a, numero: $0) } }
        case .ano: return anos.map { Semestre(ano: $0, numero: 0) }
        case .nenhuma: return []
        }
    }
}

/// Ano do curso e semestre (1.º ou 2.º), para arrumar as cadeiras na barra lateral.
/// `numero` 0 é o ano inteiro; `ano` 0 é o curso todo, sem divisão.
struct Semestre: Codable, Hashable, Comparable, Sendable {
    var ano: Int
    var numero: Int

    static let todas = Semestre(ano: 0, numero: 0)

    var nome: String {
        if ano == 0 { return "Todas as cadeiras" }
        return numero == 0 ? "\(ano).º ano" : "\(ano).º ano · \(numero).º semestre"
    }

    /// O grupo da barra lateral. `deduzido` é o das datas das aulas e dá o semestre a uma escolha só de ano.
    static func grupo(escolhido: Semestre?, deduzido: Semestre, organizacao: OrganizacaoCurso) -> Semestre {
        var s = escolhido ?? deduzido
        if s.numero == 0 { s.numero = deduzido.numero }
        switch organizacao {
        case .anoESemestre: return s
        case .ano: return Semestre(ano: s.ano, numero: 0)
        case .nenhuma: return .todas
        }
    }

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
    var temSlides: Bool

    var id: URL { pasta }
}
