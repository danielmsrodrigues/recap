import Foundation
import PDFKit

/// O livro da cadeira: um PDF para estudar sem ecrã, com a capa e o índice, a ficha da cadeira, os apontamentos de
/// todas as aulas por ordem e, no fim, o glossário de todas as aulas junto. Num livro impresso os [mm:ss] não
/// servem de ligação: saem.
enum LivroCadeira {
    struct Capitulo: Sendable {
        var numero: Int
        var titulo: String
        var data: Date
        var apontamentos: String
    }

    /// Os capítulos de uma cadeira: as aulas com apontamentos, por data.
    @MainActor
    static func capitulos(_ cadeira: Cadeira, library: Library) -> [Capitulo] {
        cadeira.aulas.filter(\.temApontamentos).sorted { $0.meta.data < $1.meta.data }.compactMap { a in
            Disco.lerApontamentos(a.pasta).map { Capitulo(numero: library.numeroDaAula(a), titulo: a.meta.titulo, data: a.meta.data, apontamentos: $0) }
        }
    }

    /// A capa: o nome da cadeira, o índice das aulas e a ficha (sem o título dela).
    static func capa(cadeira: String, capitulos: [Capitulo], ficha: String?) -> String {
        let pt = Locale(identifier: "pt_PT")
        let indice = capitulos.sorted { $0.data < $1.data }.map {
            "\($0.numero). Aula \($0.numero) · \($0.titulo) — \($0.data.formatted(.dateTime.day().month(.abbreviated).locale(pt)))"
        }.joined(separator: "\n")
        var md = "# \(cadeira)\n\nLivro da cadeira · \(Date.now.formatted(.dateTime.day().month(.wide).year().locale(pt)))\n\n## Índice\n\n\(indice)"
        if let ficha {
            let semTitulo = ficha.components(separatedBy: "\n").filter { !$0.hasPrefix("# ") }.joined(separator: "\n")
            md += "\n\n" + semTitulo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return md
    }

    /// Os apontamentos de uma aula sem os [mm:ss] (no papel não levam a lado nenhum).
    static func paraImprimir(_ md: String) -> String {
        md.replacing(/[ ]?\[(?:\d{1,2}:)?\d{1,3}:\d{2}\]/, with: "")
    }

    /// O glossário de todas as aulas, por ordem alfabética e sem termos repetidos. Vazio se nenhuma aula tiver.
    static func glossario(_ capitulos: [Capitulo]) -> String {
        let titulos = Set(RotulosApontamentos.todas("Glossário").map { $0.lowercased() })
        var tituloUsado: String?
        var termos: [String: String] = [:]
        for c in capitulos {
            var dentro = false
            for linha in c.apontamentos.components(separatedBy: "\n") {
                if linha.hasPrefix("## ") {
                    let t = String(linha.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    dentro = titulos.contains { t.lowercased().hasPrefix($0) }
                    if dentro, tituloUsado == nil { tituloUsado = t.components(separatedBy: " (").first ?? t }
                    continue
                }
                guard dentro, linha.hasPrefix("- ") else { continue }
                let termo = linha.firstMatch(of: /\*\*(.+?)\*\*/).map { String($0.output.1) } ?? String(linha.dropFirst(2))
                let chave = termo.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).lowercased()
                if termos[chave] == nil { termos[chave] = linha }
            }
        }
        guard !termos.isEmpty else { return "" }
        let linhas = termos.sorted { $0.key.compare($1.key, locale: Locale(identifier: "es")) == .orderedAscending }.map(\.value)
        return "# \(tituloUsado ?? "Glossário")\n\n" + linhas.joined(separator: "\n")
    }

    #if os(macOS)
    /// Faz o PDF: cada parte com o exportador dos apontamentos (o mesmo aspeto e as imagens dos slides), depois juntas.
    @MainActor
    static func exportar(_ cadeira: Cadeira, library: Library, para destino: URL) async throws {
        let capitulos = capitulos(cadeira, library: library)
        let temporaria = FileManager.default.temporaryDirectory.appending(path: "livro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaria, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaria) }
        var partes: [(md: String, pasta: URL?)] = [(capa(cadeira: cadeira.nome, capitulos: capitulos, ficha: FichaCadeira.lerFicha(cadeira.pasta)), nil)]
        let pastas = cadeira.aulas.filter(\.temApontamentos).sorted { $0.meta.data < $1.meta.data }.map(\.pasta)
        for (c, pasta) in zip(capitulos, pastas) { partes.append((paraImprimir(c.apontamentos), pasta)) }
        let g = glossario(capitulos)
        if !g.isEmpty { partes.append((g, nil)) }

        let livro = PDFDocument()
        for (i, parte) in partes.enumerated() {
            let url = temporaria.appending(path: "\(i).pdf")
            try await ExportadorPDF.exportar(markdown: parte.md, pastaAula: parte.pasta, para: url)
            guard let pdf = PDFDocument(url: url) else { continue }
            for p in 0..<pdf.pageCount {
                if let pagina = pdf.page(at: p) { livro.insert(pagina, at: livro.pageCount) }
            }
        }
        guard livro.write(to: destino) else {
            throw NSError(domain: "Recap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível gravar o PDF."])
        }
    }
    #endif
}
