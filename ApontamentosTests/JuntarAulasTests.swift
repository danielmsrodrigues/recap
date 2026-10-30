import Foundation
import Testing
@testable import Apontamentos

@MainActor
struct JuntarAulasTests {
    private func biblioteca() throws -> (Library, URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "juntar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return (Library(raiz: raiz), raiz)
    }

    /// Uma aula transcrita com `duracao` segundos, um slide no início e, opcionalmente, um PDF do professor.
    private func aula(_ lib: Library, _ titulo: String, duracao: Double, texto: String, pdf: String? = nil) throws -> URL {
        let pasta = try lib.criarAula(cadeira: "Gestão", titulo: titulo, data: .now, video: nil)
        try Disco.escreverTranscricao(Transcricao(idioma: "pt", modelo: "m", duracao: duracao, criadaEm: .now,
                                                  segmentos: [Segmento(inicio: 1, fim: 5, texto: texto, orador: .professor)]), em: pasta)
        let slides = pasta.appending(path: Disco.pastaSlides)
        try FileManager.default.createDirectory(at: slides, withIntermediateDirectories: true)
        try Data(titulo.utf8).write(to: slides.appending(path: "slide_01_00-02.jpg"))
        try Disco.escreverSlides([Slide(ficheiro: "slide_01_00-02.jpg", inicio: 2, fim: 30, reaparicoes: [40])], em: pasta)
        if let pdf {
            try Data(pdf.utf8).write(to: pasta.appending(path: "slides-professor.pdf"))
            try lib.atualizarMeta(em: pasta) { $0.nomesPDFs = ["slides-professor.pdf": "\(pdf).pdf"] }
        }
        try lib.atualizarMeta(em: pasta) { $0.duracao = duracao; $0.revista = true }
        return pasta
    }

    @Test func aSegundaParteEntraDepoisDaPrimeira() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let p1 = try aula(lib, "Parte 1", duracao: 3000, texto: "Antes do intervalo", pdf: "Tema 1")
        let p2 = try aula(lib, "Parte 2", duracao: 2400, texto: "Depois do intervalo", pdf: "Tema 2")

        let pasta = try lib.juntar(try #require(lib.aula(em: p2)), a: try #require(lib.aula(em: p1)))

        #expect(pasta.mesmoCaminho(p1))
        #expect(!FileManager.default.fileExists(atPath: p2.path))
        #expect(lib.cadeira(nome: "Gestão")?.aulas.count == 1)

        let t = try #require(Disco.lerTranscricao(pasta))
        #expect(t.segmentos.map(\.texto) == ["Antes do intervalo", "Depois do intervalo"])
        #expect(t.segmentos[1].inicio == 3001 && t.segmentos[1].fim == 3005)
        #expect(t.segmentos[1].orador == .professor)
        #expect(t.duracao == 5400)
        #expect(try String(contentsOf: pasta.appending(path: Disco.transcricaoTXT), encoding: .utf8).contains("[50:01] Depois do intervalo"))

        let slides = try #require(Disco.lerSlides(pasta))
        #expect(slides.count == 2)
        #expect(slides[1].ficheiro == "slide_02_50-02.jpg")
        #expect(slides[1].inicio == 3002 && slides[1].fim == 3030 && slides[1].reaparicoes == [3040])
        #expect(try Data(contentsOf: Disco.urlSlide(slides[1], em: pasta)) == Data("Parte 2".utf8))

        let meta = try Disco.lerMeta(pasta)
        #expect(meta.duracao == 5400)
        #expect(meta.revista == false)
        #expect(Disco.pdfsProfessor(pasta, nomes: meta.nomesPDFs).map(\.titulo) == ["Tema 1", "Tema 2"])
    }

    @Test func osMateriaisDaSegundaPassamParaAPrimeira() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let p1 = try aula(lib, "Parte 1", duracao: 3000, texto: "Antes")
        let p2 = try aula(lib, "Parte 2", duracao: 2400, texto: "Depois")
        let origem = raiz.appending(path: "origem")
        try FileManager.default.createDirectory(at: origem, withIntermediateDirectories: true)
        try "Parte 1".write(to: origem.appending(path: "Enunciado.txt"), atomically: true, encoding: .utf8)
        try Materiais.juntar([origem.appending(path: "Enunciado.txt")], em: p1)
        try "Parte 2".write(to: origem.appending(path: "Enunciado.txt"), atomically: true, encoding: .utf8)
        try "a;b".write(to: origem.appending(path: "Dados.csv"), atomically: true, encoding: .utf8)
        try Materiais.juntar([origem.appending(path: "Enunciado.txt"), origem.appending(path: "Dados.csv")], em: p2)

        let pasta = try lib.juntar(try #require(lib.aula(em: p2)), a: try #require(lib.aula(em: p1)))

        #expect(Materiais.nomes(em: pasta) == ["Enunciado.txt", "Enunciado 2.txt", "Dados.csv"])
        #expect(try String(contentsOf: Materiais.url("Enunciado 2.txt", em: pasta), encoding: .utf8) == "Parte 2")
    }

    @Test func semTranscricaoNaoMexeEmNada() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let p1 = try aula(lib, "Parte 1", duracao: 3000, texto: "Antes")
        let p2 = try lib.criarAula(cadeira: "Gestão", titulo: "Parte 2", data: .now, video: nil)

        #expect(throws: JuntarAulas.Erro.self) {
            try lib.juntar(try #require(lib.aula(em: p2)), a: try #require(lib.aula(em: p1)))
        }
        #expect(FileManager.default.fileExists(atPath: p2.path))
        #expect(Disco.lerTranscricao(p1)?.segmentos.count == 1)
        #expect(Disco.lerSlides(p1)?.count == 1)
    }
}
