import Foundation

/// Quem disse um segmento, segundo a identificação de voz.
enum Orador: String, Codable, Hashable, Sendable {
    case professor, aluno
}

struct Segmento: Codable, Hashable, Sendable {
    var inicio: Double
    var fim: Double
    var texto: String
    /// nil = sem identificação de voz (aulas antigas, ou o modelo não estava disponível).
    var orador: Orador? = nil
}

/// Conteúdo de `transcricao.json`.
struct Transcricao: Codable, Sendable {
    var idioma: String
    var modelo: String
    var duracao: Double
    var criadaEm: Date
    var segmentos: [Segmento]

    /// Uma linha por segmento: `[mm:ss] texto`, com `(aluno)` antes do texto quando a voz é de um aluno.
    /// É o que vai para `transcricao.txt` e para o Claude.
    var textoComTimestamps: String {
        segmentos
            .map { "[\(Timestamp.format($0.inicio))] " + ($0.orador == .aluno ? "(aluno) " : "") + $0.texto }
            .joined(separator: "\n")
    }

    /// A identificação de voz marcou pelo menos um segmento.
    var temOradores: Bool { segmentos.contains { $0.orador != nil } }
}
