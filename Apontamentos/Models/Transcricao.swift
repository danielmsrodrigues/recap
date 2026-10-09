import Foundation

struct Segmento: Codable, Hashable, Sendable {
    var inicio: Double
    var fim: Double
    var texto: String
}

/// Conteúdo de `transcricao.json`.
struct Transcricao: Codable, Sendable {
    var idioma: String
    var modelo: String
    var duracao: Double
    var criadaEm: Date
    var segmentos: [Segmento]

    /// Uma linha por segmento: `[mm:ss] texto`. É o que vai para `transcricao.txt` e para o Claude.
    var textoComTimestamps: String {
        segmentos
            .map { "[\(Timestamp.format($0.inicio))] \($0.texto)" }
            .joined(separator: "\n")
    }
}
