import Foundation
import PDFKit
import Testing
@testable import Apontamentos

/// O PDF dos apontamentos: o WebKit grava os slides sem perdas (15 MB numa aula com 30 slides). Depois de
/// comprimir em JPEG fica bem mais pequeno, com as mesmas páginas, o mesmo texto e as mesmas ligações.
struct ComprimirPDFTests {
    /// Uma página com uma imagem "de slide" (ruído suave, que sem perdas quase não comprime), texto e uma ligação.
    private func pdfComSlide(em url: URL) throws {
        let (w, h) = (1200, 700)
        var pixeis = [UInt8](repeating: 255, count: w * h * 4)
        var semente: UInt32 = 7
        for i in stride(from: 0, to: pixeis.count, by: 4) {
            semente = semente &* 1_664_525 &+ 1_013_904_223
            let v = UInt8(truncatingIfNeeded: (i / 4 % w) / 6 + Int(semente >> 28))
            pixeis[i] = v; pixeis[i + 1] = v &+ 40; pixeis[i + 2] = 255 &- v
        }
        let imagem = try #require(CGContext(data: &pixeis, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let semLigacao = url.deletingPathExtension().appendingPathExtension("sem.pdf")
        defer { try? FileManager.default.removeItem(at: semLigacao) }
        var caixa = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try #require(CGContext(semLigacao as CFURL, mediaBox: &caixa, nil))
        ctx.beginPDFPage(nil)
        ctx.draw(imagem, in: CGRect(x: 36, y: 400, width: 523, height: 305))
        let texto = NSAttributedString(string: "Frecuencias absolutas", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        ctx.textPosition = CGPoint(x: 36, y: 360)
        CTLineDraw(CTLineCreateWithAttributedString(texto), ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        let doc = try #require(PDFDocument(url: semLigacao))
        let ligacao = PDFAnnotation(bounds: CGRect(x: 36, y: 355, width: 150, height: 20), forType: .link, withProperties: nil)
        ligacao.url = URL(string: "https://example.com")
        doc.page(at: 0)?.addAnnotation(ligacao)
        #expect(doc.write(to: url))
    }

    @Test func fixaMaisPequenoComAsMesmasPaginasTextoELigacoes() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "comprimir-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try pdfComSlide(em: url)
        let antes = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)

        try ComprimirPDF.comprimir(url)

        let depois = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(depois < antes / 2)
        let doc = try #require(PDFDocument(url: url))
        #expect(doc.pageCount == 1)
        #expect(doc.string?.contains("Frecuencias absolutas") == true)
        #expect(doc.page(at: 0)?.annotations.first?.url?.absoluteString == "https://example.com")
    }
}
