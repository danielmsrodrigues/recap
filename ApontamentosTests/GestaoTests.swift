import Foundation
import Testing
@testable import Apontamentos

@MainActor
struct GestaoTests {
    private func biblioteca() throws -> (Library, URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "gestao-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return (Library(raiz: raiz), raiz)
    }

    @Test func editarAulaRenomeiaEMoveDeCadeira() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let video = raiz.appending(path: "v.mp4")
        try Data().write(to: video)
        let pasta = try lib.criarAula(cadeira: "Cálculo", titulo: "Límites", data: .now, video: video)
        try Disco.escreverApontamentos("# x", em: pasta)
        try lib.criarCadeira(nome: "Álgebra")

        let aula = try #require(lib.aula(em: pasta))
        let nova = try lib.editarAula(aula, titulo: "Autovalores", data: aula.meta.data, cadeira: "Álgebra")
        #expect(nova.deletingLastPathComponent().lastPathComponent == "Álgebra")
        #expect(nova.lastPathComponent.hasSuffix("_Autovalores"))
        #expect(!FileManager.default.fileExists(atPath: pasta.path))
        #expect(Disco.lerApontamentos(nova) == "# x")
        #expect(lib.aula(em: nova)?.meta.titulo == "Autovalores")
        #expect(lib.cadeira(nome: "Cálculo")?.aulas.isEmpty == true)
    }

    @Test func renomearCadeiraERecusarDuplicado() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try lib.criarCadeira(nome: "A")
        try lib.criarCadeira(nome: "B")
        let a = try #require(lib.cadeira(nome: "A"))
        #expect(throws: (any Error).self) { try lib.renomearCadeira(a, para: "B") }
        try lib.renomearCadeira(a, para: "Álgebra Lineal")
        #expect(lib.cadeiras.map(\.nome) == ["Álgebra Lineal", "B"])
    }

    @Test func revistaEEdicoesManuais() throws {
        let (lib, raiz) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let video = raiz.appending(path: "v.mp4")
        try Data().write(to: video)
        let pasta = try lib.criarAula(cadeira: "C", titulo: "T", data: .now, video: video)
        try lib.definirRevista(true, em: pasta)
        #expect(lib.aula(em: pasta)?.meta.revista == true)

        var meta = try Disco.lerMeta(pasta)
        #expect(!meta.temEdicoesManuais)
        meta.geracoes = [Geracao(data: .now.addingTimeInterval(-60), modeloPedido: "m", modeloServido: "m", inputTokens: 0,
                                 outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, custoUSD: 0, truncada: false)]
        meta.editadoEm = .now
        #expect(meta.temEdicoesManuais)
    }

    @Test func copiaDeSegurancaAntesDeRegenerar() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "copia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        try Disco.guardarCopiaApontamentos(em: pasta) // sem apontamentos: não faz nada
        try Disco.escreverApontamentos("v1", em: pasta)
        try Disco.guardarCopiaApontamentos(em: pasta)
        try Disco.escreverApontamentos("v2", em: pasta)
        #expect(try String(contentsOf: pasta.appending(path: Disco.apontamentosAnteriorMD), encoding: .utf8) == "v1")
        #expect(Disco.lerApontamentos(pasta) == "v2")
    }
}
