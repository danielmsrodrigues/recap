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
    /// Para uma cadeira dada noutra língua; nil = a língua das aulas das Definições.
    var idioma: IdiomaAula?
    /// A cor escolhida à mão (índice de `Revisao.paleta`); nil = automática.
    var cor: Int?

    init(glossario: String = "", regiaoIgnorar: RegiaoIgnorar = .automatica, semestre: Semestre? = nil, idioma: IdiomaAula? = nil) {
        self.glossario = glossario
        self.regiaoIgnorar = regiaoIgnorar
        self.semestre = semestre
        self.idioma = idioma
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glossario = try c.decodeIfPresent(String.self, forKey: .glossario) ?? ""
        regiaoIgnorar = try c.decodeIfPresent(RegiaoIgnorar.self, forKey: .regiaoIgnorar) ?? .automatica
        semestre = try c.decodeIfPresent(Semestre.self, forKey: .semestre)
        idioma = try c.decodeIfPresent(IdiomaAula.self, forKey: .idioma)
        cor = try c.decodeIfPresent(Int.self, forKey: .cor)
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

    /// Nome do seletor da cadeira ("Semestre", "Trimestre"… ou "Ano"); `periodo` vem do calendário letivo.
    func rotulo(periodo: String) -> String { self == .ano ? "Ano" : periodo.prefix(1).uppercased() + periodo.dropFirst() }

    /// As escolhas manuais para uma cadeira, até ao ano `ate` (quem chama junta a duração do curso),
    /// com `periodos` por ano.
    func opcoes(ate: Int, periodos: Int = 2) -> [Semestre] {
        let anos = 1...max(1, ate)
        switch self {
        case .anoESemestre: return anos.flatMap { a in (1...max(1, periodos)).map { Semestre(ano: a, numero: $0) } }
        case .ano: return anos.map { Semestre(ano: $0, numero: 0) }
        case .nenhuma: return []
        }
    }
}

/// Ano do curso e período dentro dele (semestre, ou trimestre… conforme o calendário letivo), para arrumar as
/// cadeiras na barra lateral. `numero` 0 é o ano inteiro; `ano` 0 é o curso todo, sem divisão.
struct Semestre: Codable, Hashable, Comparable, Sendable {
    var ano: Int
    var numero: Int

    static let todas = Semestre(ano: 0, numero: 0)

    var nome: String { nome(periodo: "semestre") }

    /// `periodo` é o nome dos períodos do calendário ("semestre", "trimestre"…; ver `CalendarioLetivo`).
    func nome(periodo: String) -> String {
        if ano == 0 { return "Todas as cadeiras" }
        return numero == 0 ? "\(ano).º ano" : "\(ano).º ano · \(numero).º \(periodo)"
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

    /// Ano letivo (o ano civil em que começa) e período de uma data. `inicios` são os meses em que começa cada
    /// período (ver `CalendarioLetivo`): com `[9, 2]`, setembro a janeiro é o 1.º semestre e fevereiro a agosto o 2.º.
    static func letivo(_ data: Date, inicios: [Int] = CalendarioLetivo.porDefeito, calendario: Calendar = .current) -> (inicio: Int, numero: Int) {
        let c = calendario.dateComponents([.year, .month], from: data)
        let ano = c.year ?? 0, mes = c.month ?? 1
        let inicios = CalendarioLetivo.valido(inicios) ? inicios : CalendarioLetivo.porDefeito
        // Meses desde o início do ano letivo, para os períodos que atravessam a passagem de ano.
        let desde = { (m: Int) in (m - inicios[0] + 12) % 12 }
        let numero = inicios.lastIndex { desde($0) <= desde(mes) }.map { $0 + 1 } ?? 1
        return (mes >= inicios[0] ? ano : ano - 1, numero)
    }
}

/// Os meses em que começa cada período do ano letivo, a começar pelo 1.º (que é também o início do ano):
/// `[9, 2]` semestres de setembro e fevereiro, `[2, 8]` o calendário brasileiro, `[9, 1, 4]` trimestres.
enum CalendarioLetivo {
    static let porDefeito = [9, 2]

    struct Opcao: Hashable, Sendable {
        var nome: String
        var inicios: [Int]
    }

    /// Os que se escolhem nas Definições.
    static let opcoes = [
        Opcao(nome: "Semestres de setembro e fevereiro", inicios: [9, 2]),
        Opcao(nome: "Semestres de fevereiro e agosto", inicios: [2, 8]),
        Opcao(nome: "Trimestres de setembro, janeiro e abril", inicios: [9, 1, 4]),
        Opcao(nome: "Ano inteiro, sem períodos", inicios: [9]),
    ]

    /// Meses de 1 a 12, sem repetidos, pela ordem do ano letivo.
    static func valido(_ inicios: [Int]) -> Bool {
        guard let primeiro = inicios.first, inicios.allSatisfy((1...12).contains) else { return false }
        let desde = inicios.map { ($0 - primeiro + 12) % 12 }
        return zip(desde, desde.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// "semestre", "trimestre" ou "período".
    static func nomePeriodo(_ inicios: [Int]) -> String {
        switch inicios.count {
        case 2: "semestre"
        case 3: "trimestre"
        default: "período"
        }
    }

    /// "1.º semestre de setembro a janeiro, 2.º de fevereiro a agosto".
    static func descricao(_ inicios: [Int]) -> String {
        var calendario = Calendar(identifier: .gregorian)
        calendario.locale = Locale(identifier: "pt_PT")
        let meses = calendario.standaloneMonthSymbols.map { $0.lowercased() }
        let n = inicios.count
        guard n > 1 else { return "o ano letivo começa em \(meses[inicios[0] - 1])" }
        return inicios.enumerated().map { i, inicio in
            let fim = (inicios[(i + 1) % n] + 10) % 12 + 1
            return "\(i + 1).º\(i == 0 ? " \(nomePeriodo(inicios))" : "") de \(meses[inicio - 1]) a \(meses[fim - 1])"
        }.joined(separator: ", ")
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
