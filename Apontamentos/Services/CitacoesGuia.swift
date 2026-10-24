import Foundation

/// Confere as páginas da guía citadas nos apontamentos ("Guía (1.3, p. 7)", "Según la guía (p. 5)") com as das
/// secções que foram enviadas ao Claude. Uma página que ele não recebeu pode ser inventada: fica marcada
/// "página por confirmar", para o estudante a ir ver. Não apaga nada.
enum CitacoesGuia {
    static let marca = ", página por confirmar"

    /// O rótulo da guía (em qualquer língua), a secção se vier logo a seguir ("2.4", "Tema 1") e o primeiro "p. N",
    /// "pp. N–M" ou "pág. N" antes de fechar o parêntese.
    private static let padrao: NSRegularExpression = {
        let rotulos = RotulosApontamentos.todas("Guia").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?i)(?:\(rotulos))\\b\\s*\\(?\\s*(?:Tema\\s+)?(\\d+(?:\\.\\d+)*)?[^)\\n]*?\\bp(?:p|ág|ag)?\\.\\s*(\\d+)(?:\\s*[–-]\\s*(\\d+))?")
    }()

    /// `seccoes` vazio: não confere as secções, só as páginas.
    static func verificar(_ md: String, paginas: Set<Int>, seccoes: Set<String> = []) -> (markdown: String, invalidas: Int) {
        var resultado = md
        var invalidas = 0
        let ns = md as NSString
        // Do fim para o início, para as marcas acrescentadas não mudarem as posições seguintes.
        for m in padrao.matches(in: md, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let inicio = Int(ns.substring(with: m.range(at: 2))) else { continue }
            let fim = m.range(at: 3).location == NSNotFound ? inicio : Int(ns.substring(with: m.range(at: 3))) ?? inicio
            let seccao = m.range(at: 1).location == NSNotFound ? nil : ns.substring(with: m.range(at: 1))
            let seccaoValida = seccoes.isEmpty || seccao.map(seccoes.contains) ?? true
            guard !seccaoValida || !(min(inicio, fim)...max(inicio, fim)).allSatisfy(paginas.contains) else { continue }
            let depois = m.range.location + m.range.length
            guard let i = Range(NSRange(location: depois, length: 0), in: resultado),
                  !resultado[i.lowerBound...].hasPrefix(marca) else { continue }
            resultado.insert(contentsOf: marca, at: i.lowerBound)
            invalidas += 1
        }
        return (resultado, invalidas)
    }
}
