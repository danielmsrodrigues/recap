import Foundation
import Testing
@testable import Apontamentos

/// Os conflitos verdadeiros só o iCloud os cria; aqui testa-se o que se decide com eles.
struct ConflitosICloudTests {
    @Test func asConversasJuntamSeSemRepetir() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let comum = PerguntaAula(pergunta: "Resume", resposta: "…", data: base)
        let doMac = PerguntaAula(pergunta: "E o juro simples?", resposta: "…", data: base.addingTimeInterval(60))
        let doIPad = PerguntaAula(pergunta: "Dá um exemplo", resposta: "…", data: base.addingTimeInterval(30))
        let juntas = ConflitosICloud.juntar([[comum, doMac], [comum, doIPad]])
        #expect(juntas.map(\.pergunta) == ["Resume", "Dá um exemplo", "E o juro simples?"])
    }

    @Test func aCopiaFicaAoLadoSemApagarOutra() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "conflitos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let url = pasta.appending(path: "apontamentos.md")
        var partes = DateComponents(year: 2026, month: 10, day: 29, hour: 9, minute: 5)
        partes.timeZone = .current
        let data = try #require(Calendar(identifier: .gregorian).date(from: partes))
        let primeira = ConflitosICloud.nomeCopia(url, data: data)
        #expect(primeira.lastPathComponent == "apontamentos.conflito-2026-10-29-0905.md")
        try Data().write(to: primeira)
        #expect(ConflitosICloud.nomeCopia(url, data: data).lastPathComponent == "apontamentos.conflito-2026-10-29-0905 (2).md")
    }

    @Test func semConflitoNaoMexeEmNada() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "conflitos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        try Disco.escreverApontamentos("# Aula", em: pasta)
        #expect(ConflitosICloud.resolver(pasta.appending(path: Disco.apontamentosMD)).isEmpty)
        ConflitosICloud.resolverPerguntas(pasta)
        #expect(try FileManager.default.contentsOfDirectory(atPath: pasta.path) == [Disco.apontamentosMD])
    }
}
