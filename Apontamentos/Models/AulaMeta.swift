import Foundation

/// Referência ao vídeo original, que não é copiado para a pasta da aula.
struct VideoRef: Codable, Hashable, Sendable {
    var caminho: String
    var bookmark: Data?
}

/// Uma chamada ao Claude que gerou apontamentos.
struct Geracao: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var data: Date
    var modeloPedido: String
    var modeloServido: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var custoUSD: Double
    var truncada: Bool
    /// "claude-code" ou nil (API, gerações antigas).
    var motor: String?
    /// Quanto custaria na API (só informativo com o Claude Code).
    var custoEquivalenteAPI: Double?
    /// Fração usada da janela de 5 h da subscrição no fim da geração.
    var usoSubscricao5h: Double?

    var viaClaudeCode: Bool { motor == "claude-code" }

    /// "subscrição · 12 400 + 6 100 tokens · 5 h: 23 %" ou "$0,31 (12 400 + 6 100 tokens)".
    var resumo: String {
        let tokens = "\(inputTokens.formatted()) + \(outputTokens.formatted()) tokens"
        guard viaClaudeCode else { return "\(TabelaPrecos.formatar(custoUSD)) (\(tokens))" }
        var s = "subscrição · \(tokens)"
        if let u = usoSubscricao5h, u > 0 { s += " · 5 h: \(u.formatted(.percent.precision(.fractionLength(0))))" }
        return s
    }
}

/// Conteúdo de `aula.json`.
struct AulaMeta: Codable, Hashable, Sendable {
    var titulo: String
    var data: Date
    var criadaEm: Date
    var video: VideoRef?
    var duracao: Double?
    var modeloWhisper: String?
    var geracoes: [Geracao]
    /// Marcada pelo utilizador depois de estudar a aula.
    var revista: Bool
    /// Última vez que os apontamentos foram alterados à mão.
    var editadoEm: Date?
    /// "direto" quando o áudio foi captado enquanto a aula tocava (não há vídeo guardado).
    var origem: String?
    /// O utilizador mudou o título à mão; a partir daí as gerações deixam de o substituir pelo tema da aula.
    var tituloManual: Bool?
    /// Nome original de cada PDF do professor juntado, pelo ficheiro na pasta da aula (`slides-professor-2.pdf` → `Tema 3.pdf`).
    var nomesPDFs: [String: String]?

    init(titulo: String, data: Date, video: VideoRef?) {
        self.titulo = titulo
        self.data = data
        self.criadaEm = .now
        self.video = video
        self.geracoes = []
        self.revista = false
    }

    /// Há alterações à mão feitas depois da última geração (perdem-se ao regenerar, salvo a cópia de segurança).
    var temEdicoesManuais: Bool {
        guard let editadoEm else { return false }
        return editadoEm > (geracoes.last?.data ?? .distantPast)
    }

    // Campos novos entram como opcionais, para que aulas antigas continuem a abrir.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titulo = try c.decode(String.self, forKey: .titulo)
        data = try c.decode(Date.self, forKey: .data)
        criadaEm = try c.decodeIfPresent(Date.self, forKey: .criadaEm) ?? data
        video = try c.decodeIfPresent(VideoRef.self, forKey: .video)
        duracao = try c.decodeIfPresent(Double.self, forKey: .duracao)
        modeloWhisper = try c.decodeIfPresent(String.self, forKey: .modeloWhisper)
        geracoes = try c.decodeIfPresent([Geracao].self, forKey: .geracoes) ?? []
        revista = try c.decodeIfPresent(Bool.self, forKey: .revista) ?? false
        editadoEm = try c.decodeIfPresent(Date.self, forKey: .editadoEm)
        origem = try c.decodeIfPresent(String.self, forKey: .origem)
        tituloManual = try c.decodeIfPresent(Bool.self, forKey: .tituloManual)
        nomesPDFs = try c.decodeIfPresent([String: String].self, forKey: .nomesPDFs)
    }
}

/// Título das aulas: o Claude escreve o tema no `# título` dos apontamentos e a app junta o número da aula,
/// que ele não sabe (vem da ordem das datas dentro da cadeira).
enum TituloAula {
    /// `aula` é a palavra na língua dos apontamentos ("Aula", "Clase", "Lecture").
    static func titulo(numero: Int, tema: String, aula: String = "Aula") -> String { "\(aula) \(numero) · \(tema)" }

    /// O tema no primeiro `# título`, sem o nome da cadeira nem um "Aula N" que o Claude tenha posto à frente.
    static func tema(_ markdown: String) -> String? {
        guard let linha = markdown.split(separator: "\n", omittingEmptySubsequences: true).first,
              linha.hasPrefix("# ") else { return nil }
        var tema = linha.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if let r = tema.range(of: #"^(.*[—–-]\s*)?(Aula|Clase|Sesi[oó]n|Lecture|Class|Session|Li[cç][aã]o)\s+\d+(\s*[:·—–-]\s*|$)"#, options: [.regularExpression, .caseInsensitive]) {
            tema.removeSubrange(r)
        }
        tema = tema.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        guard !tema.isEmpty else { return nil }
        return tema.prefix(1).uppercased() + tema.dropFirst()
    }

    /// Troca o primeiro `# título` dos apontamentos.
    static func trocarCabecalho(_ markdown: String, por titulo: String) -> String {
        guard let r = markdown.range(of: #"(?m)^# .*$"#, options: .regularExpression) else { return markdown }
        return markdown.replacingCharacters(in: r, with: "# \(titulo)")
    }
}
