import CoreGraphics
import Foundation

/// Um slide guardado em `slides/`. O conjunto vai para `slides.json`.
struct Slide: Codable, Hashable, Sendable, Identifiable {
    var ficheiro: String
    /// Quando apareceu pela primeira vez (segundos).
    var inicio: Double
    var fim: Double
    /// Outras vezes em que voltou a aparecer.
    var reaparicoes: [Double] = []

    var id: String { ficheiro }
}

/// Zona do frame ignorada ao comparar slides, para a câmara do professor não gerar slides falsos.
enum RegiaoIgnorar: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatica, nenhuma
    case superiorDireito, inferiorDireito, superiorEsquerdo, inferiorEsquerdo
    case soCentro

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .automatica: "Automática (deteta a câmara)"
        case .nenhuma: "Nenhuma"
        case .superiorDireito: "Canto superior direito"
        case .inferiorDireito: "Canto inferior direito"
        case .superiorEsquerdo: "Canto superior esquerdo"
        case .inferiorEsquerdo: "Canto inferior esquerdo"
        case .soCentro: "Comparar só a zona central"
        }
    }

    /// Retângulos normalizados (origem em cima à esquerda) a tapar antes de comparar.
    /// `.automatica` devolve vazio: a zona é calculada a partir do vídeo.
    var retangulos: [CGRect] {
        let w = 0.3, h = 0.32
        switch self {
        case .automatica, .nenhuma: return []
        case .superiorDireito: return [CGRect(x: 1 - w, y: 0, width: w, height: h)]
        case .inferiorDireito: return [CGRect(x: 1 - w, y: 1 - h, width: w, height: h)]
        case .superiorEsquerdo: return [CGRect(x: 0, y: 0, width: w, height: h)]
        case .inferiorEsquerdo: return [CGRect(x: 0, y: 1 - h, width: w, height: h)]
        case .soCentro:
            let mx = 0.18, my = 0.18
            return [
                CGRect(x: 0, y: 0, width: 1, height: my), CGRect(x: 0, y: 1 - my, width: 1, height: my),
                CGRect(x: 0, y: 0, width: mx, height: 1), CGRect(x: 1 - mx, y: 0, width: mx, height: 1),
            ]
        }
    }
}
