import Foundation
import Testing
@testable import Apontamentos

/// A pasta das aulas partilhada com o iPad e o iPhone pelo iCloud Drive.
@MainActor
struct PastaPartilhadaTests {
    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "partilhada-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func definicoes() -> Definicoes {
        Definicoes(defaults: UserDefaults(suiteName: "partilhada-\(UUID().uuidString)")!)
    }

    @Test func aPastaDoSistemaNaoEUmaCadeira() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        try lib.criarCadeira(nome: "Cálculo")
        try DefinicoesPartilhadas.escrever(definicoes().partilhadas, raiz: raiz)
        lib.recarregar()
        #expect(lib.cadeiras.map(\.nome) == ["Cálculo"])
    }

    @Test func oIOSFicaComAsDefinicoesDoMac() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let mac = definicoes()
        mac.contextoCurso = "Licenciatura em Física, 1.º ano"
        mac.linguaApontamentos = try #require(LinguaApontamentos.allCases.last)
        mac.idiomaAulas = try #require(IdiomaAula.allCases.last)
        mac.organizacao = try #require(OrganizacaoCurso.allCases.last)
        mac.modeloClaude = "claude-opus-5-5"
        mac.duracaoCurso = 3
        try DefinicoesPartilhadas.escrever(mac.partilhadas, raiz: raiz)

        let ios = definicoes()
        ios.aplicar(try #require(DefinicoesPartilhadas.ler(raiz: raiz)))
        #expect(ios.partilhadas == mac.partilhadas)
    }

    @Test func soEscreveQuandoMuda() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let d = definicoes()
        try DefinicoesPartilhadas.escrever(d.partilhadas, raiz: raiz)
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        let antiga = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: antiga], ofItemAtPath: url.path)
        try DefinicoesPartilhadas.escrever(d.partilhadas, raiz: raiz)
        // O `URL` guarda em cache a data: lê-se sempre do disco.
        func modificado() throws -> Date? { try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date }
        #expect(try modificado() == antiga)
        d.duracaoCurso = 5
        try DefinicoesPartilhadas.escrever(d.partilhadas, raiz: raiz)
        #expect(try modificado() != antiga)
    }

    @Test func valoresDesconhecidosNaoEstragamAsDefinicoes() throws {
        let d = definicoes()
        let antes = d.partilhadas
        var p = antes
        p.linguaApontamentos = "klingon"
        p.organizacao = "por-luas"
        p.iniciosPeriodos = []
        d.aplicar(p)
        #expect(d.linguaApontamentos.rawValue == antes.linguaApontamentos)
        #expect(d.organizacao.rawValue == antes.organizacao)
        #expect(d.iniciosPeriodos == antes.iniciosPeriodos)
    }

    @Test func gravarFicaRegistadoParaIgnorarOEco() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let url = raiz.appending(path: "apontamentos.md")
        #expect(!Disco.gravadoHaPouco(url))
        try Disco.gravar("# Límites", em: url)
        #expect(Disco.gravadoHaPouco(url))
        #expect(try Disco.lerTexto(url) == "# Límites")
    }

    /// O que chega de fora (outro processo, como o iCloud) avisa; o que a própria app grava não.
    @Test func observadorSoAvisaMudancasDeFora() async throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var avisos = 0
        let observador = ObservadorPasta(raiz) { avisos += 1 }
        defer { withExtendedLifetime(observador) {} }

        try Disco.gravar("nossa", em: raiz.appending(path: "nossa.md"))
        try await Task.sleep(for: .seconds(3))
        #expect(avisos == 0)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "echo fora > \"$0\"", raiz.appending(path: "fora.md").path]
        try p.run()
        p.waitUntilExit()
        for _ in 0..<40 where avisos == 0 { try await Task.sleep(for: .milliseconds(250)) }
        #expect(avisos == 1)
    }
}
