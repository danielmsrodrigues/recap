import Foundation
import Testing
@testable import Apontamentos

struct DiscoTests {
    @Test func nomeDePastaMantemAcentosETiraSeparadores() {
        #expect(Disco.nomeDePasta("Álgebra Lineal") == "Álgebra Lineal")
        #expect(Disco.nomeDePasta("Tema 3: SVD / PCA") == "Tema 3- SVD - PCA")
        #expect(Disco.nomeDePasta("  ..oculto  ") == "oculto")
        #expect(Disco.nomeDePasta("   ") == "Sem título")
        #expect(Disco.nomeDePasta(String(repeating: "a", count: 200)).count == 80)
    }

    @Test func nomePastaAulaComData() throws {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 8; c.hour = 12
        let data = try #require(Calendar.current.date(from: c))
        #expect(Disco.nomePastaAula(titulo: "Autovalores", data: data) == "2026-10-08_Autovalores")
    }

    @Test func pastaLivreAcrescentaNumero() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp.appending(path: "Aula"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(Disco.pastaLivre("Aula", em: tmp).lastPathComponent == "Aula (2)")
        #expect(Disco.pastaLivre("Outra", em: tmp).lastPathComponent == "Outra")
    }

    @Test func leEstruturaDeAulas() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: raiz) }
        let cadeira = raiz.appending(path: "Cálculo")
        let aula1 = cadeira.appending(path: "2026-09-01_Límites")
        let aula2 = cadeira.appending(path: "2026-09-08_Derivadas")
        for p in [aula1, aula2] { try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true) }
        // Pasta sem aula.json é ignorada.
        try FileManager.default.createDirectory(at: cadeira.appending(path: "lixo"), withIntermediateDirectories: true)
        try Disco.escreverCadeira(CadeiraMeta(glossario: "límite\nderivada"), em: cadeira)
        try Disco.escreverMeta(AulaMeta(titulo: "Límites", data: Date(timeIntervalSince1970: 1_788_000_000), video: nil), em: aula1)
        try Disco.escreverMeta(AulaMeta(titulo: "Derivadas", data: Date(timeIntervalSince1970: 1_789_000_000), video: nil), em: aula2)
        try Disco.escreverApontamentos("# Derivadas", em: aula2)

        let cadeiras = try Library.ler(raiz: raiz)
        #expect(cadeiras.map(\.nome) == ["Cálculo"])
        #expect(cadeiras[0].meta.glossario == "límite\nderivada")
        #expect(cadeiras[0].aulas.map(\.meta.titulo) == ["Derivadas", "Límites"])
        #expect(cadeiras[0].aulas[0].temApontamentos)
        #expect(!cadeiras[0].aulas[1].temApontamentos)
    }

    @Test func metaAntigaSemCamposNovosAbre() throws {
        let json = #"{"titulo":"X","data":"2026-10-08T10:00:00Z"}"#
        let meta = try Disco.decoder.decode(AulaMeta.self, from: Data(json.utf8))
        #expect(meta.titulo == "X")
        #expect(meta.geracoes.isEmpty)
        #expect(meta.video == nil)
    }

    @Test func videoMovidoEEncontradoPeloBookmark() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let original = tmp.appending(path: "aula.mp4")
        try Data("x".utf8).write(to: original)
        let ref = VideoResolver.referencia(para: original)
        guard case .ok(let encontrado) = VideoResolver.resolver(ref) else {
            Issue.record("esperava .ok"); return
        }
        #expect(encontrado.lastPathComponent == "aula.mp4")

        let movido = tmp.appending(path: "renomeado.mp4")
        try FileManager.default.moveItem(at: original, to: movido)
        guard case .movido(let url, let nova) = VideoResolver.resolver(ref) else {
            Issue.record("esperava .movido"); return
        }
        #expect(url.lastPathComponent == "renomeado.mp4")
        #expect(nova.caminho.hasSuffix("renomeado.mp4"))

        try FileManager.default.removeItem(at: movido)
        #expect(VideoResolver.resolver(nova) == .emFalta(caminho: nova.caminho))
    }
}

