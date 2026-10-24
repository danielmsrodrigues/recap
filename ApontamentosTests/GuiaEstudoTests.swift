import CoreText
import Foundation
import PDFKit
import Testing
@testable import Apontamentos

struct GuiaEstudoTests {
    /// 66 páginas de uma guía como a de Fundamentos: capa, índice na 2.ª, o resto vazio.
    private var fixture: [String] {
        var p = [String](repeating: "", count: 66)
        p[0] = "Guía de estudio\nFundamentos de Empresas"
        p[1] = """
        Índice
        Tema 1. La empresa y la actividad empresarial ........ 4
            1.1. Fundamentos de las empresas ........ 5
            1.2. Principios de la actividad empresarial ........ 5
            1.3. Clase de empresas ........ 7
        Tema 2. Gestión Empresarial ........ 14
            6.2. El proceso ........ 52
            6.2. Técnicas ........ 60
        """
        p[4] = "TEMA 1\nLa empresa y la actividad empresarial"
        p[5] = "1.1. Fundamentos de las empresas\nUna empresa es..."
        return p
    }

    /// Escreve um PDF com uma página por texto (texto real, que o PDFKit consegue extrair).
    private func escreverPDF(_ paginas: [String], em url: URL) throws {
        var caixa = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &caixa, nil))
        let fonte = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for texto in paginas {
            ctx.beginPDFPage(nil)
            for (i, linha) in texto.components(separatedBy: "\n").enumerated() {
                let s = NSAttributedString(string: linha, attributes: [.font: fonte])
                ctx.textPosition = CGPoint(x: 40, y: 780 - CGFloat(i) * 16)
                CTLineDraw(CTLineCreateWithAttributedString(s), ctx)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    @Test func leOIndiceEODesvio() throws {
        let i = try #require(GuiaEstudo.indice(paginas: fixture, hash: "h"))
        #expect(i.desvio == 1)
        #expect(i.seccoes.map(\.id) == ["1", "1.1", "1.2", "1.3", "2", "6.2", "6.2"])
        #expect(i.seccoes[1] == SeccaoGuia(id: "1.1", titulo: "Fundamentos de las empresas", paginaInicio: 5, paginaFim: 5))
        #expect(i.seccoes[3].paginaFim == 13)                     // até à véspera do Tema 2
        #expect(i.seccoes.last?.paginaFim == 65)                  // última página impressa (66 − 1)
    }

    @Test func semIndiceDevolveNil() {
        #expect(GuiaEstudo.indice(paginas: ["", "texto sem índice"], hash: "h") == nil)
    }

    @Test func textoComPaginasImpressas() throws {
        let i = try #require(GuiaEstudo.indice(paginas: fixture, hash: "h"))
        let t = GuiaEstudo.texto(i.seccoes[1], indice: i, paginas: fixture)
        #expect(t.hasPrefix("[p. 5]\n"))
        #expect(t.contains("1.1. Fundamentos de las empresas"))
    }

    @Test func refazOIndiceQuandoAGuiaMuda() throws {
        let cadeira = FileManager.default.temporaryDirectory.appending(path: "guia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cadeira, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cadeira) }
        try escreverPDF(["Índice\nTema 1. La empresa ........ 2", "La empresa\nTexto da página"],
                        em: FichaCadeira.urlPrograma(cadeira))
        let antigo = IndiceGuia(hash: "antigo", desvio: 9, seccoes: [])
        try Disco.escrever(antigo, em: cadeira.appending(path: GuiaEstudo.ficheiro))

        let (indice, paginas) = try #require(GuiaEstudo.carregar(cadeira: cadeira))
        let hash = try #require(FichaCadeira.hashDoPrograma(cadeira))
        #expect(indice.hash == hash)
        #expect(indice.seccoes.map(\.id) == ["1"])
        #expect(paginas.count == 2)
        let gravado = try Disco.ler(IndiceGuia.self, de: cadeira.appending(path: GuiaEstudo.ficheiro))
        #expect(gravado == indice)
        // Com o hash a bater, devolve o que está gravado.
        #expect(GuiaEstudo.carregar(cadeira: cadeira)?.indice == indice)
    }

    @Test func semProgramaDevolveNil() {
        #expect(GuiaEstudo.carregar(cadeira: FileManager.default.temporaryDirectory.appending(path: "nao-existe-\(UUID().uuidString)")) == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_GUIA"] != nil))
    func guiaReal() throws {
        let caminho = try #require(ProcessInfo.processInfo.environment["APONTAMENTOS_GUIA"])
        let pdf = try #require(PDFDocument(url: URL(fileURLWithPath: caminho)))
        let i = try #require(GuiaEstudo.indice(paginas: GuiaEstudo.paginas(pdf), hash: "h"))
        #expect(i.desvio == 1)
        let s = try #require(i.seccoes.first { $0.id == "2.4" })
        #expect(s.titulo.contains("Estructuras organizativas"))
    }
}
