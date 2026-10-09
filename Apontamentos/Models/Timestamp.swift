import Foundation

/// Timestamps no formato `[mm:ss]`, com os minutos a crescer para lá de 59
/// (uma aula de 90 min chega a `[89:59]`). O parser aceita também `h:mm:ss`.
enum Timestamp {
    static func format(_ segundos: Double) -> String {
        let total = max(0, Int(segundos.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func parse(_ texto: String) -> Double? {
        let partes = texto.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(partes.count) else { return nil }
        var total = 0
        for (i, parte) in partes.enumerated() {
            guard let valor = Int(parte), valor >= 0 else { return nil }
            if i > 0, valor > 59 { return nil }
            total = total * 60 + valor
        }
        return Double(total)
    }

    /// "1 h 32 min", "45 min", "40 s"
    static func duracao(_ segundos: Double) -> String {
        let total = Int(segundos.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }
}
