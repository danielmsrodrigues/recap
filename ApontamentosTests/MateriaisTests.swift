import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Apontamentos

/// Outros materiais do professor juntados à aula além dos PDFs (`Materiais`): Excel, Word, PowerPoint, imagens, texto.
@MainActor
struct MateriaisTests {
    private func pastaTemporaria() throws -> URL {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "materiais-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta
    }

    private func ficheiro(_ nome: String, _ texto: String, em pasta: URL) throws -> URL {
        let url = pasta.appending(path: "origem").appending(path: nome)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try texto.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func png(_ nome: String, em pasta: URL) throws -> URL {
        let url = pasta.appending(path: "origem").appending(path: nome)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let destino = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destino, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destino))
        return url
    }

    @Test func ficamNaPastaDosMateriaisPelaOrdemEmQueSeJuntaram() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        let juntados = try Materiais.juntar([try ficheiro("Notas.csv", "a;b\n1;2", em: aula), try png("Quadro.png", em: aula)], em: aula)
        #expect(juntados == ["Notas.csv", "Quadro.jpg"])
        try Materiais.juntar([try ficheiro("Enunciado.txt", "Exercício 1", em: aula)], em: aula)
        #expect(Materiais.nomes(em: aula) == ["Notas.csv", "Quadro.jpg", "Enunciado.txt"])
        #expect(FileManager.default.fileExists(atPath: aula.appending(path: "materiais/Notas.csv").path))
    }

    @Test func oMesmoFicheiroNaoEntraDuasVezes() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        let csv = try ficheiro("Notas.csv", "a;b", em: aula)
        try Materiais.juntar([csv], em: aula)
        #expect(try Materiais.juntar([csv], em: aula).isEmpty)
        #expect(Materiais.nomes(em: aula) == ["Notas.csv"])
    }

    @Test func recusaOQueNaoSabeLer() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        #expect(throws: ErroAnexo.self) { try Materiais.juntar([try ficheiro("filme.mov", "x", em: aula)], em: aula) }
        #expect(Materiais.nomes(em: aula).isEmpty)
    }

    /// Os PDFs e os outros materiais vão juntos no pedido dos apontamentos: o limite é para todos.
    @Test func oLimiteContaComOsPDFs() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        try Data(count: Disco.tamanhoMaximoPDF - 4).write(to: aula.appending(path: "slides-professor.pdf"))
        #expect(throws: (any Error).self) { try Materiais.juntar([try ficheiro("Notas.csv", "a;b;c;d;e", em: aula)], em: aula) }
        #expect(Materiais.nomes(em: aula).isEmpty)

        try FileManager.default.removeItem(at: aula.appending(path: "slides-professor.pdf"))
        try Materiais.juntar([try ficheiro("Notas.csv", "a;b;c;d;e", em: aula)], em: aula)
        let pdf = aula.appending(path: "origem/grande.pdf")
        try Data(count: Disco.tamanhoMaximoPDF - 4).write(to: pdf)
        #expect(throws: (any Error).self) { try Disco.juntarPDFsProfessor([pdf], em: aula) }
    }

    @Test func tirarVaiParaOLixo() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        try Materiais.juntar([try ficheiro("Notas.csv", "a;b", em: aula), try ficheiro("Outro.txt", "x", em: aula)], em: aula)
        try Materiais.remover("Notas.csv", em: aula)
        #expect(Materiais.nomes(em: aula) == ["Outro.txt"])
        #expect(throws: (any Error).self) { try Materiais.remover("../aula.json", em: aula) }
    }

    @Test func entramNoPedidoDosApontamentosComOPedidoDasTabelas() throws {
        let aula = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: aula) }
        try Materiais.juntar([try ficheiro("Custos.csv", "Produto;Custo\nMesa;120", em: aula)], em: aula)
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: [Segmento(inicio: 0, fim: 5, texto: "Hola")])
        var c = ContextoAula(cadeira: "C", titulo: "T", data: .now, glossario: "", transcricao: t)
        let semMateriais = NotesGenerator.conteudo(c).compactMap { if case .texto(let s) = $0 { s } else { nil } }.joined()
        #expect(!semMateriais.contains("materiais"))

        c.materiaisProfessor = Materiais.blocos(em: aula)
        let textos = NotesGenerator.conteudo(c).compactMap { if case .texto(let s) = $0 { s } else { nil } }
        let materiais = try #require(textos.firstIndex { $0.contains("Outros materiais do professor") })
        let transcricao = try #require(textos.firstIndex { $0.contains("<transcricao>") })
        #expect(materiais < transcricao)
        #expect(textos.contains { $0.contains("Custos.csv") && $0.contains("Mesa;120") })
        #expect(textos.last?.contains("tabela") == true)
        // As perguntas do chat usam os mesmos materiais.
        #expect(NotesGenerator.materiais(c).contains { if case .texto(let s) = $0 { s.contains("Mesa;120") } else { false } })
    }

    @Test func carregarAAulaLeOsMateriais() async throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let pasta = try lib.criarAula(cadeira: "Gestão", titulo: "Aula 1", data: .now, video: nil)
        try Materiais.juntar([try ficheiro("Custos.csv", "Mesa;120", em: raiz)], em: pasta)
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: [Segmento(inicio: 0, fim: 5, texto: "Hola")])
        let contexto = await ContextoAula.carregar(try #require(lib.aula(em: pasta)), cadeira: nil, transcricao: t)
        #expect(contexto.materiaisProfessor.contains { if case .texto(let s) = $0 { s.contains("Mesa;120") } else { false } })
    }
}
