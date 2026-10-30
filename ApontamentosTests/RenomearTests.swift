import Foundation
import Testing
@testable import Apontamentos

/// As ligações (`ligacoes.json`) e a ficha da cadeira (`sobre.json`) guardam o nome das pastas. Ao renomear uma aula
/// ou uma cadeira, acompanham-no: senão as ligações pareciam desatualizadas (e refaziam-se com o Claude) e a aula
/// voltava a ser juntada à ficha.
@MainActor
struct RenomearTests {
    private func biblioteca() throws -> (Library, URL, a: URL, b: URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "renomear-\(UUID().uuidString)")
        let library = Library(raiz: raiz)
        let dia = Date(timeIntervalSince1970: 86_400)
        let a = try library.criarAula(cadeira: "Cálculo", titulo: "Limites", data: dia, video: nil)
        let b = try library.criarAula(cadeira: "Cálculo", titulo: "Derivadas", data: dia.addingTimeInterval(86_400), video: nil)
        let ra = "Cálculo/\(a.lastPathComponent)", rb = "Cálculo/\(b.lastPathComponent)"
        let ligacoes = LigacoesAula(
            ligacoes: [.init(aula: ra, direcao: .anterior, conceitos: ["limite"], explicacao: "x")],
            temas: [.init(tema: "Limites", aulas: [ra], explicacao: "y")],
            assinaturas: [ra: "1", rb: "2"], formato: LigacoesAula.formatoAtual)
        try Disco.escreverLigacoes(ligacoes, em: b)
        var registo = FichaCadeira.Registo()
        registo.aulas[a.lastPathComponent] = "h"
        registo.migradas = [a.lastPathComponent]
        try FichaCadeira.escreverRegisto(registo, em: a.deletingLastPathComponent())
        library.recarregar(forcar: true)
        return (library, raiz, a, b)
    }

    @Test func renomearUmaAulaAtualizaAsLigacoesEAFicha() throws {
        let (library, raiz, a, b) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let nova = try library.editarAula(try #require(library.aula(em: a)), titulo: "Limites laterais",
                                          data: Date(timeIntervalSince1970: 86_400), cadeira: "Cálculo")
        let rel = "Cálculo/\(nova.lastPathComponent)"
        let l = try #require(Disco.lerLigacoes(library.raiz.appending(path: "Cálculo/\(b.lastPathComponent)")))
        #expect(l.ligacoes.map(\.aula) == [rel])
        #expect(l.temas.first?.aulas == [rel])
        #expect(l.assinaturas?[rel] == "1")
        #expect(l.assinaturas?["Cálculo/\(a.lastPathComponent)"] == nil)
        let registo = FichaCadeira.lerRegisto(nova.deletingLastPathComponent())
        #expect(registo.aulas[nova.lastPathComponent] == "h")
        #expect(registo.migradas == [nova.lastPathComponent])
    }

    @Test func renomearACadeiraAtualizaAsLigacoes() throws {
        let (library, raiz, a, b) = try biblioteca()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let cadeira = try #require(library.cadeira(nome: "Cálculo"))
        let nova = try library.renomearCadeira(cadeira, para: "Cálculo I")
        let l = try #require(Disco.lerLigacoes(nova.appending(path: b.lastPathComponent)))
        #expect(l.ligacoes.map(\.aula) == ["Cálculo I/\(a.lastPathComponent)"])
        #expect(l.assinaturas?["Cálculo I/\(b.lastPathComponent)"] == "2")
    }
}
