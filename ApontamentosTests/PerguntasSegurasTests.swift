import Foundation
import Testing
@testable import Apontamentos

/// As perguntas de uma aula: um `perguntas.json` que não se lê (ainda a chegar do iCloud, estragado) não pode ser
/// substituído só pela resposta nova, nem levar os anexos com ele.
struct PerguntasSegurasTests {
    private func pasta() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "perguntas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func umaRespostaNovaJuntaSeAsAnteriores() throws {
        let p = try pasta()
        defer { try? FileManager.default.removeItem(at: p) }
        #expect(Disco.lerPerguntasSePossivel(p) == [])
        try Disco.juntarPergunta(PerguntaAula(pergunta: "A?", resposta: "a"), em: p)
        try Disco.juntarPergunta(PerguntaAula(pergunta: "B?", resposta: "b"), em: p)
        #expect(Disco.lerPerguntas(p).map(\.pergunta) == ["A?", "B?"])
    }

    @Test func umHistoricoQueNaoSeLeNaoEApagado() throws {
        let p = try pasta()
        defer { try? FileManager.default.removeItem(at: p) }
        let ficheiro = p.appending(path: Disco.perguntasJSON)
        try Data("a meio de chegar".utf8).write(to: ficheiro)
        #expect(Disco.lerPerguntasSePossivel(p) == nil)
        #expect(throws: (any Error).self) { try Disco.juntarPergunta(PerguntaAula(pergunta: "A?", resposta: "a"), em: p) }
        #expect(try String(contentsOf: ficheiro, encoding: .utf8) == "a meio de chegar")
    }
}
