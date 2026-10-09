import Foundation

/// Preço em USD por milhão de tokens.
struct Preco: Codable, Hashable, Sendable {
    var entrada: Double
    var saida: Double
    var escritaCache: Double
    var leituraCache: Double
}

/// Preços da página oficial (platform.claude.com/docs/en/about-claude/pricing, consultada a 2026-10-08).
/// O modelo configurado pode ter preços próprios nas Definições.
struct TabelaPrecos: Sendable {
    static let oficial: [String: Preco] = [
        "claude-sonnet-5-5": Preco(entrada: 2, saida: 10, escritaCache: 2.5, leituraCache: 0.10),
        "claude-sonnet-5": Preco(entrada: 2, saida: 10, escritaCache: 2.5, leituraCache: 0.20),
        "claude-opus-5-5": Preco(entrada: 4, saida: 20, escritaCache: 5, leituraCache: 0.20),
        "claude-opus-5": Preco(entrada: 5, saida: 25, escritaCache: 6.25, leituraCache: 0.50),
        "claude-opus-4-8": Preco(entrada: 5, saida: 25, escritaCache: 6.25, leituraCache: 0.50),
        "claude-fable-5-1": Preco(entrada: 10, saida: 50, escritaCache: 12.5, leituraCache: 0.25),
        "claude-haiku-4-5": Preco(entrada: 1, saida: 5, escritaCache: 1.25, leituraCache: 0.10),
    ]

    var personalizados: [String: Preco] = [:]

    /// Procura pelo prefixo mais longo, para aceitar IDs com sufixo de data.
    func preco(para modelo: String) -> Preco? {
        if let p = personalizados[modelo] { return p }
        let chave = Self.oficial.keys
            .filter { modelo == $0 || modelo.hasPrefix($0 + "-") }
            .max { $0.count < $1.count }
        return chave.flatMap { Self.oficial[$0] }
    }

    /// Custo de uma resposta. Com fallback, `usage.iterations` traz cada tentativa e o seu modelo.
    func custo(_ uso: UsoTokens, modeloPedido: String) -> Double {
        let partes = uso.iteracoes.isEmpty
            ? [(uso.modelo ?? modeloPedido, uso.contagem)]
            : uso.iteracoes.map { ($0.modelo ?? modeloPedido, $0.contagem) }
        return partes.reduce(0) { total, parte in
            guard let p = preco(para: parte.0) ?? preco(para: modeloPedido) else { return total }
            return total + Self.custo(parte.1, p)
        }
    }

    static func custo(_ c: ContagemTokens, _ p: Preco) -> Double {
        (Double(c.input) * p.entrada
            + Double(c.output) * p.saida
            + Double(c.cacheWrite) * p.escritaCache
            + Double(c.cacheRead) * p.leituraCache) / 1_000_000
    }

    static func formatar(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD").precision(.fractionLength(usd < 0.1 ? 3 : 2)).locale(Locale(identifier: "pt_PT")))
    }
}

struct ContagemTokens: Hashable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
}

struct UsoTokens: Hashable, Sendable {
    struct Iteracao: Hashable, Sendable {
        var tipo: String
        var modelo: String?
        var contagem: ContagemTokens
    }

    /// Modelo que serviu a resposta (pode ser um fallback).
    var modelo: String?
    var contagem = ContagemTokens()
    var iteracoes: [Iteracao] = []
}
