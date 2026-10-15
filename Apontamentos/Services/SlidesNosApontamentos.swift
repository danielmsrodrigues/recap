import AppKit
import PDFKit

/// Slides dentro dos apontamentos. O Claude marca onde entra cada slide com `![Slide 7 — título](slide:2/7)`
/// (página 7 do PDF 2 do professor) ou `![Slide 7 — título](slide:7)` (captura 7), e a app troca a marca pelo
/// caminho da imagem, relativo à pasta da aula (`slides-pdf-2/pagina-07.jpg`, `slides/<ficheiro>`).
enum SlidesNosApontamentos {
    /// Largura das imagens das páginas: nítidas no ecrã Retina e no PDF, sem pesar.
    static let larguraPagina: CGFloat = 1600

    /// Um slide citado nos apontamentos: a página de um PDF do professor, ou uma captura (pdf nil).
    struct Referencia: Hashable, Sendable {
        var pdf: Int?
        var numero: Int
    }

    static func nomePagina(_ n: Int) -> String { String(format: "pagina-%02d.jpg", n) }

    /// Imagens das páginas de um PDF, na pasta dele. Só as cria se faltarem (apagar a pasta obriga a refazer).
    /// Devolve o número de páginas.
    @discardableResult
    static func garantirPaginas(de pdf: PDFProfessor, em pasta: URL) throws -> Int {
        guard let documento = PDFDocument(url: pdf.url(em: pasta)) else {
            throw NSError(domain: "Recap", code: 41, userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir o PDF dos slides \(pdf.titulo)."])
        }
        let destino = pasta.appending(path: pdf.pastaPaginas, directoryHint: .isDirectory)
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

    /// As imagens de todos os PDFs da aula, fora da thread principal e sem falhar: sem imagens os apontamentos
    /// fazem-se na mesma, só sem esses slides. Devolve o número de páginas de cada PDF (pelo número do PDF).
    static func garantirPaginasEmFundo(em pasta: URL) async -> [Int: Int] {
        await Task.detached(priority: .userInitiated) {
            var paginas: [Int: Int] = [:]
            for pdf in Disco.pdfsProfessor(pasta) {
                paginas[pdf.numero] = try? garantirPaginas(de: pdf, em: pasta)
            }
            return paginas
        }.value
    }

    /// Manda as imagens das páginas de um PDF para o Lixo (o PDF foi removido); recuperáveis com o PDF.
    static func apagarPaginas(de pdf: PDFProfessor, em pasta: URL) {
        let url = pasta.appending(path: pdf.pastaPaginas, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Slide citado → caminho da imagem, com a mesma numeração que o Claude recebeu
    /// (PDF e página, ou capturas pela ordem de `slides.json`).
    static func imagens(paginasPDF: [Int: Int], capturas: [Slide]) -> [Referencia: String] {
        var imagens: [Referencia: String] = [:]
        for (numero, total) in paginasPDF where total > 0 {
            let pasta = PDFProfessor(numero: numero).pastaPaginas
            for pagina in 1...total { imagens[Referencia(pdf: numero, numero: pagina)] = "\(pasta)/\(nomePagina(pagina))" }
        }
        for (i, s) in capturas.enumerated() { imagens[Referencia(pdf: nil, numero: i + 1)] = "\(Disco.pastaSlides)/\(s.ficheiro)" }
        return imagens
    }

    private static let reMarca = try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(\s*slide:\s*(?:(\d+)\s*/\s*)?(\d+)\s*\)[ \t]*\n?"#)

    /// Troca cada `![…](slide:P/N)` ou `![…](slide:N)` pelo caminho da imagem. Marcas de slides que não existem saem do texto.
    static func resolver(_ markdown: String, imagens: [Referencia: String]) -> String {
        let ns = markdown as NSString
        var saida = ""
        var ultimo = 0
        for m in reMarca.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            saida += ns.substring(with: NSRange(location: ultimo, length: m.range.location - ultimo))
            ultimo = m.range.location + m.range.length
            let legenda = ns.substring(with: m.range(at: 1))
            let pdf = m.range(at: 2).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 2)))
            guard let n = Int(ns.substring(with: m.range(at: 3))), let caminho = imagens[Referencia(pdf: pdf, numero: n)] else { continue }
            let fimDeLinha = ns.substring(with: m.range).hasSuffix("\n") ? "\n" : ""
            saida += "![\(legenda)](\(caminho))" + fimDeLinha
        }
        saida += ns.substring(from: ultimo)
        return saida
    }
}
