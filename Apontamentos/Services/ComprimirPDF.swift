#if os(macOS)
import PDFKit
import Quartz

/// O WebKit grava os slides do PDF dos apontamentos sem perdas: uma aula com 30 slides dava 15 MB. Voltar a
/// desenhar as páginas com um filtro JPEG (sem baixar a resolução) deixa-o com cerca de um terço, igual à vista.
enum ComprimirPDF {
    /// Substitui `url` pela versão comprimida, com as mesmas páginas, texto e ligações. Se não ficar mais pequeno,
    /// fica o original.
    static func comprimir(_ url: URL, qualidade: Double = 0.8) throws {
        guard let origem = CGPDFDocument(url as CFURL), origem.numberOfPages > 0 else { return }
        let pasta = url.deletingLastPathComponent()
        let temporario = pasta.appending(path: ".\(UUID().uuidString).pdf")
        // O PDFKit lê o documento aos poucos: com as ligações, grava-se noutro ficheiro e não no que está a ler.
        let final = pasta.appending(path: ".\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: temporario)
            try? FileManager.default.removeItem(at: final)
        }

        let propriedades: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterData": ["ColorSettings": ["ImageSettings": ["Compression Quality": qualidade,
                                                               "ImageCompression": "ImageJPEGCompress"]]],
            "FilterType": 1, "Name": "Recap JPEG",
        ]
        var caixa = CGRect.zero
        guard let filtro = QuartzFilter(properties: propriedades),
              let ctx = CGContext(temporario as CFURL, mediaBox: &caixa, nil), filtro.apply(to: ctx)
        else { return }
        for i in 1...origem.numberOfPages {
            guard let pagina = origem.page(at: i) else { continue }
            var retangulo = pagina.getBoxRect(.mediaBox)
            ctx.beginPage(mediaBox: &retangulo)
            ctx.drawPDFPage(pagina)
            ctx.endPage()
        }
        ctx.closePDF()

        // As ligações (minutos, links) são anotações e não passam pelo desenho: copiam-se do original.
        guard let original = PDFDocument(url: url), let novo = PDFDocument(url: temporario),
              novo.pageCount == original.pageCount else { return }
        for i in 0..<original.pageCount {
            guard let de = original.page(at: i), let para = novo.page(at: i) else { continue }
            // Uma ligação nova com a mesma ação: a cópia de `copy()` perde o endereço.
            for anotacao in de.annotations where anotacao.type == "Link" {
                let ligacao = PDFAnnotation(bounds: anotacao.bounds, forType: .link, withProperties: nil)
                ligacao.action = anotacao.action?.copy() as? PDFAction
                if ligacao.action == nil { ligacao.url = anotacao.url }
                para.addAnnotation(ligacao)
            }
        }
        guard novo.write(to: final) else { return }
        let tamanho = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max }
        guard tamanho(final) < tamanho(url) else { return }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: final)
    }
}
#endif
