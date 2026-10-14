import AppKit
import PDFKit

/// Slides dentro dos apontamentos. O Claude marca onde entra cada slide com `![Slide 7 — título](slide:7)`
/// e a app troca a marca pelo caminho da imagem, relativo à pasta da aula (`slides-pdf/pagina-07.jpg`
/// para o PDF do professor, `slides/<ficheiro>` para as capturas).
enum SlidesNosApontamentos {
    /// Uma imagem por página do PDF do professor.
    static let pastaPaginas = "slides-pdf"
    /// Largura das imagens das páginas: nítidas no ecrã Retina e no PDF, sem pesar.
    static let larguraPagina: CGFloat = 1600

    static func nomePagina(_ n: Int) -> String { String(format: "pagina-%02d.jpg", n) }

    /// Imagens das páginas do PDF, em `slides-pdf/`. Só as cria se faltarem (apagar a pasta obriga a refazer).
    /// Devolve o número de páginas, ou nil se a aula não tem PDF.
    @discardableResult
    static func garantirPaginas(em pasta: URL) throws -> Int? {
        guard let pdf = Disco.urlPDFProfessor(pasta) else { return nil }
        guard let documento = PDFDocument(url: pdf) else {
            throw NSError(domain: "Recap", code: 41, userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir o PDF dos slides."])
        }
        let destino = pasta.appending(path: pastaPaginas, directoryHint: .isDirectory)
        let total = documento.pageCount
        if (1...max(total, 1)).allSatisfy({ FileManager.default.fileExists(atPath: destino.appending(path: nomePagina($0)).path) }) {
            return total
        }
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        for i in 0..<total {
            // Cada página são ~10 MB de imagens intermédias: libertá-las já, não no fim do ciclo.
            try autoreleasepool {
                guard let pagina = documento.page(at: i) else { return }
                var caixa = pagina.bounds(for: .cropBox).size
                if pagina.rotation % 180 != 0 { caixa = CGSize(width: caixa.height, height: caixa.width) }
                guard caixa.width > 0 else { return }
                let tamanho = CGSize(width: larguraPagina, height: (larguraPagina * caixa.height / caixa.width).rounded())
                let imagem = pagina.thumbnail(of: tamanho, for: .cropBox)
                guard let tiff = imagem.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
                else { return }
                try jpeg.write(to: destino.appending(path: nomePagina(i + 1)), options: .atomic)
            }
        }
        return total
    }

    /// O mesmo, fora da thread principal e sem falhar: sem imagens os apontamentos fazem-se na mesma, só sem slides.
    static func garantirPaginasEmFundo(em pasta: URL) async -> Int? {
        await Task.detached(priority: .userInitiated) { try? garantirPaginas(em: pasta) }.value ?? nil
    }

    /// Manda as imagens das páginas para o Lixo (o PDF foi substituído ou removido); recuperáveis com o PDF.
    static func apagarPaginas(em pasta: URL) {
        try? FileManager.default.trashItem(at: pasta.appending(path: pastaPaginas, directoryHint: .isDirectory), resultingItemURL: nil)
    }

    /// Número do slide → caminho da imagem, com a mesma numeração que o Claude recebeu
    /// (páginas do PDF, ou capturas pela ordem de `slides.json`).
    static func imagens(em pasta: URL, paginasPDF: Int?, capturas: [Slide]) -> [Int: String] {
        if let paginasPDF {
            guard paginasPDF > 0 else { return [:] }
            return Dictionary(uniqueKeysWithValues: (1...paginasPDF).map { ($0, "\(pastaPaginas)/\(nomePagina($0))") })
        }
        return Dictionary(uniqueKeysWithValues: capturas.enumerated().map { ($0.offset + 1, "\(Disco.pastaSlides)/\($0.element.ficheiro)") })
    }

    private static let reMarca = try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(\s*slide:\s*(\d+)\s*\)[ \t]*\n?"#)

    /// Troca cada `![…](slide:N)` pelo caminho da imagem. Marcas de slides que não existem saem do texto.
    static func resolver(_ markdown: String, imagens: [Int: String]) -> String {
        let ns = markdown as NSString
        var saida = ""
        var ultimo = 0
        for m in reMarca.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            saida += ns.substring(with: NSRange(location: ultimo, length: m.range.location - ultimo))
            ultimo = m.range.location + m.range.length
            let legenda = ns.substring(with: m.range(at: 1))
            guard let n = Int(ns.substring(with: m.range(at: 2))), let caminho = imagens[n] else { continue }
            let fimDeLinha = ns.substring(with: m.range).hasSuffix("\n") ? "\n" : ""
            saida += "![\(legenda)](\(caminho))" + fimDeLinha
        }
        saida += ns.substring(from: ultimo)
        return saida
    }
}
