import Foundation

/// Confere as páginas da guía citadas nos apontamentos ("Guía (1.3, p. 7)", "Según la guía (p. 5)") com as das
/// secções que foram enviadas ao Claude. Uma página que ele não recebeu pode ser inventada: fica marcada
/// "página por confirmar", para o estudante a ir ver. Não apaga nada.
enum CitacoesGuia {
    static let marca = ", página por confirmar"

    /// O rótulo da guía (em qualquer língua) até ao primeiro "p. N" ou "p. N–M" antes de fechar o parêntese.
    private static let padrao: NSRegularExpression = {
        let rotulos = RotulosApontamentos.todas("Guia").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?i)(?:\(rotulos))\\b[^)\\n]*?\\bpp?\\.\\s*(\\d+)(?:\\s*[–-]\\s*(\\d+))?")
    }()

    static func verificar(_ md: String, paginas: Set<Int>) -> (markdown: String, invalidas: Int) {
        var resultado = md
        var invalidas = 0
        let ns = md as NSString
        // Do fim para o início, para as marcas acrescentadas não mudarem as posições seguintes.
        for m in padrao.matches(in: md, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let inicio = Int(ns.substring(with: m.range(at: 1))) else { continue }
            let fim = m.range(at: 2).location == NSNotFound ? inicio : Int(ns.substring(with: m.range(at: 2))) ?? inicio
            guard !(min(inicio, fim)...max(inicio, fim)).allSatisfy(paginas.contains) else { continue }
            invalidas += 1
            let depois = m.range.location + m.range.length
            if let i = Range(NSRange(location: depois, length: 0), in: resultado) {
                guard !resultado[i.lowerBound...].hasPrefix(marca) else { continue }
                resultado.insert(contentsOf: marca, at: i.lowerBound)
            }
        }
        return (resultado, invalidas)
    }
}
