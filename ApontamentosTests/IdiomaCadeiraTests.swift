import Foundation
import Testing
@testable import Apontamentos

@MainActor
struct IdiomaCadeiraTests {
    @Test func cadeiraDadaNoutraLingua() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "idioma-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        // Preferências vazias e nada gravado nelas: a língua das aulas fica a de defeito (espanhol).
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "idioma-\(UUID().uuidString)")!)
        let lib = Library(raiz: raiz)
        try lib.criarCadeira(nome: "Finanzas")
        try lib.criarCadeira(nome: "Strategy")
        var meta = try #require(lib.cadeira(nome: "Strategy")).meta
        meta.idioma = .ingles
        try lib.guardarCadeira(meta, cadeira: try #require(lib.cadeira(nome: "Strategy")))

        #expect(definicoes.idioma(da: lib.cadeira(nome: "Finanzas")) == .espanhol)
        #expect(definicoes.idioma(da: lib.cadeira(nome: "Strategy")) == .ingles)
        #expect(definicoes.idioma(da: nil) == .espanhol)
        #expect(Disco.lerCadeira(try #require(lib.cadeira(nome: "Strategy")).pasta).idioma == .ingles)

        #expect(definicoes.prompt("em {{idioma}}") == "em espanhol")
        #expect(definicoes.prompt("em {{idioma}}", idioma: .ingles) == "em inglês")
        #expect(definicoes.prompt(PromptStore.original, idioma: .ingles).contains("da aula, em inglês, com"))

        // `cadeira.json` antigo, sem língua.
        #expect(try Disco.decoder.decode(CadeiraMeta.self, from: Data(#"{"glossario":"x"}"#.utf8)).idioma == nil)
    }
}
