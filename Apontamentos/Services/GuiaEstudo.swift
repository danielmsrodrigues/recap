import Foundation
import PDFKit

/// Uma secção da guía de estudo (um tema ou um subtema). As páginas são as impressas na guía, inclusivas.
struct SeccaoGuia: Codable, Equatable, Sendable {
    /// "2.4" para um subtema; "N" para o "Tema N".
    var id: String
    var titulo: String
    var paginaInicio: Int
    var paginaFim: Int
}

/// O índice da guía, lido do próprio PDF, com o hash da guía de que veio.
struct IndiceGuia: Codable, Equatable, Sendable {
    var hash: String
    /// Páginas do PDF (a contar de 1) menos páginas impressas: a capa e o índice não vêm numerados.
    var desvio: Int
    var seccoes: [SeccaoGuia]
}

/// A guía de estudo da cadeira (`programa.pdf`): o índice das secções e o texto de cada uma.
///
///     ~/Aulas/<cadeira>/guia.json    o índice já lido (refeito quando a guía muda)
enum GuiaEstudo {
    static let ficheiro = "guia.json"
    /// O índice procura-se só no início do PDF.
    private static let paginasDoIndice = 6

    // Ex.: "    2.4. Estructuras organizativas ........ 18" ou "Tema 2. Gestión Empresarial ........ 14".
    private static var linha: Regex<(Substring, Substring?, Substring?, Substring, Substring)> {
        /^\s*(?:Tema\s+(\d+)|(\d+(?:\.\d+)+))\.?\s+(.+?)\s*\.{3,}\s*(\d+)\s*$/
    }

    /// O texto de cada página, por ordem.
    static func paginas(_ pdf: PDFDocument) -> [String] {
        (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
    }

    /// Lê o índice das primeiras páginas e acha o desvio entre páginas do PDF e impressas.
    /// nil se não houver índice ou se nenhum título for encontrado no corpo da guía.
    static func indice(paginas: [String], hash: String) -> IndiceGuia? {
        var seccoes: [SeccaoGuia] = []
        var ultimaDoIndice = -1
        for (i, texto) in paginas.prefix(paginasDoIndice).enumerated() {
            for l in texto.components(separatedBy: .newlines) {
                guard let m = try? linha.wholeMatch(in: l), let inicio = Int(m.4) else { continue }
                seccoes.append(SeccaoGuia(id: String(m.1 ?? m.2 ?? ""), titulo: String(m.3), paginaInicio: inicio, paginaFim: inicio))
                ultimaDoIndice = i
            }
        }
        guard !seccoes.isEmpty else { return nil }

        // Desvio: a moda de (página do PDF onde o título aparece depois do índice) − (página impressa).
        let corpo = paginas.enumerated().dropFirst(ultimaDoIndice + 1).map { ($0.offset + 1, normalizar($0.element)) }
        var votos: [Int: Int] = [:]
        for s in seccoes {
            let titulo = normalizar(s.titulo)
            if let (pagina, _) = corpo.first(where: { $0.1.contains(titulo) }) { votos[pagina - s.paginaInicio, default: 0] += 1 }
        }
        // Em empate, o desvio menor (determinista).
        // Um desvio negativo deslocaria o texto e as citações de todas as páginas: melhor sem guía.
        guard let desvio = votos.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) })?.key, desvio >= 0 else { return nil }

        let ultima = max(paginas.count - desvio, 1)
        for i in seccoes.indices {
            let fim = i + 1 < seccoes.count ? seccoes[i + 1].paginaInicio - 1 : ultima
            seccoes[i].paginaFim = max(fim, seccoes[i].paginaInicio)
        }
        return IndiceGuia(hash: hash, desvio: desvio, seccoes: seccoes)
    }

    /// O texto das páginas da secção, cada uma precedida de "[p. N]" (N, a página impressa).
    static func texto(_ s: SeccaoGuia, indice: IndiceGuia, paginas: [String]) -> String {
        (s.paginaInicio...max(s.paginaInicio, s.paginaFim)).compactMap { p -> String? in
            let i = p + indice.desvio - 1
            guard paginas.indices.contains(i) else { return nil }
            return "[p. \(p)]\n\(paginas[i])"
        }.joined(separator: "\n")
    }

    /// O índice e as páginas da guía da cadeira. Usa o `guia.json` se for da mesma guía; senão refaz o índice e
    /// grava-o. nil sem PDF ou sem índice.
    static func carregar(cadeira: URL) -> (indice: IndiceGuia, paginas: [String])? {
        guard let hash = FichaCadeira.hashDoPrograma(cadeira),
              let pdf = PDFDocument(url: FichaCadeira.urlPrograma(cadeira)) else { return nil }
        let paginas = paginas(pdf)
        let guardado = cadeira.appending(path: ficheiro)
        if let i = try? Disco.ler(IndiceGuia.self, de: guardado), i.hash == hash { return (i, paginas) }
        guard let novo = indice(paginas: paginas, hash: hash) else { return nil }
        try? Disco.escrever(novo, em: guardado)
        return (novo, paginas)
    }

    /// Minúsculas e espaços simples, para achar um título apesar das quebras de linha do PDF.
    private static func normalizar(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
