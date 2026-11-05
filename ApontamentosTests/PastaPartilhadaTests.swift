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

    @Test func aPastaDoSistemaNaoEUmaCadeira() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        try lib.criarCadeira(nome: "Cálculo")
        try DefinicoesPartilhadas.escrever(.porDefeito, raiz: raiz)
        lib.recarregar()
        #expect(lib.cadeiras.map(\.nome) == ["Cálculo"])
    }

    @Test func oIOSFicaComAsDefinicoesDoMac() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let mac = Library(raiz: raiz)
        let lingua = try #require(LinguaApontamentos.allCases.last)
        let idioma = try #require(IdiomaAula.allCases.last)
        let organizacao = try #require(OrganizacaoCurso.allCases.last)
        try mac.alterarPreferencias {
            $0.contextoCurso = "Licenciatura em Física, 1.º ano"
            $0.lingua = lingua
            $0.idioma = idioma
            $0.organizacaoCurso = organizacao
            $0.duracao = 3
        }

        let ios = Library(raiz: raiz)
        #expect(ios.preferencias == mac.preferencias)
        #expect(ios.contextoCurso == "Licenciatura em Física, 1.º ano")
        #expect(ios.linguaApontamentos == lingua)
        #expect(ios.idiomaAulas == idioma)
        #expect(ios.organizacao == organizacao)
        #expect(ios.duracaoCurso == 3)
    }

    @Test func soEscreveQuandoMuda() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var d = DefinicoesPartilhadas.porDefeito
        try DefinicoesPartilhadas.escrever(d, raiz: raiz)
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        let antiga = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: antiga], ofItemAtPath: url.path)
        try DefinicoesPartilhadas.escrever(d, raiz: raiz)
        // O `URL` guarda em cache a data: lê-se sempre do disco.
        func modificado() throws -> Date? { try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date }
        #expect(try modificado() == antiga)
        d.duracao = 5
        try DefinicoesPartilhadas.escrever(d, raiz: raiz)
        #expect(try modificado() != antiga)
    }

    /// Um ficheiro ainda por descarregar lê-se como nil: não pode parecer diferente e ser substituído.
    @Test func naoSubstituiUmFicheiroPorDescarregar() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var d = DefinicoesPartilhadas.porDefeito
        d.contextoCurso = "O que vem a caminho"
        try DefinicoesPartilhadas.escrever(d, raiz: raiz)

        var outro = DefinicoesPartilhadas.porDefeito
        outro.contextoCurso = "Valores deste aparelho"
        try DefinicoesPartilhadas.escrever(outro, raiz: raiz) { _ in true }
        #expect(DefinicoesPartilhadas.ler(raiz: raiz)?.contextoCurso == "O que vem a caminho")

        // Já descarregado, escreve-se como sempre.
        try DefinicoesPartilhadas.escrever(outro, raiz: raiz) { _ in false }
        #expect(DefinicoesPartilhadas.ler(raiz: raiz)?.contextoCurso == "Valores deste aparelho")
    }

    /// Um campo em falta não invalida o ficheiro nem leva o resto das preferências atrás.
    @Test func umCampoEmFaltaNaoInvalidaOFicheiro() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"contextoCurso":"Mestrado em Gestão","duracaoCurso":1}"#.utf8).write(to: url)

        let lidas = try #require(DefinicoesPartilhadas.ler(raiz: raiz))
        #expect(lidas.contextoCurso == "Mestrado em Gestão")
        #expect(lidas.duracaoCurso == 1)

        // Os outros ficam como numa instalação nova.
        let novo = DefinicoesPartilhadas.porDefeito
        #expect(lidas.linguaApontamentos == novo.linguaApontamentos)
        #expect(lidas.idiomaAulas == novo.idiomaAulas)
        #expect(lidas.organizacao == novo.organizacao)
        #expect(lidas.iniciosPeriodos == novo.iniciosPeriodos)
    }

    /// Um campo que esta versão não conhece (escrito por uma versão mais recente) é ignorado.
    @Test func umCampoDesconhecidoEIgnorado() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"contextoCurso":"Fintech360","campoDoFuturo":true}"#.utf8).write(to: url)
        #expect(DefinicoesPartilhadas.ler(raiz: raiz)?.contextoCurso == "Fintech360")
    }

    /// O que se escreve lê-se igual: a leitura tolerante não perde nada.
    @Test func escreverELerDaOMesmo() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var d = DefinicoesPartilhadas.porDefeito
        d.contextoCurso = "Licenciatura"
        d.duracao = 3
        d.inicios = try #require(CalendarioLetivo.opcoes.last?.inicios)
        d.organizacaoCurso = try #require(OrganizacaoCurso.allCases.last)
        try DefinicoesPartilhadas.escrever(d, raiz: raiz)
        #expect(DefinicoesPartilhadas.ler(raiz: raiz) == d)
    }

    /// Valores que esta versão não conhece: lê-se o valor por defeito, mas o ficheiro guarda-os até alguém mudar esse campo.
    @Test func valoresDesconhecidosNaoEstragamAsDefinicoes() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var p = DefinicoesPartilhadas.porDefeito
        p.linguaApontamentos = "klingon"
        p.organizacao = "por-luas"
        p.iniciosPeriodos = []
        p.duracaoCurso = 0
        try DefinicoesPartilhadas.escrever(p, raiz: raiz)

        let lib = Library(raiz: raiz)
        #expect(lib.linguaApontamentos == .ptPT)
        #expect(lib.organizacao == .anoESemestre)
        #expect(lib.iniciosPeriodos == CalendarioLetivo.porDefeito)
        #expect(lib.duracaoCurso == 1)

        try lib.alterarPreferencias { $0.contextoCurso = "Mestrado" }
        let lidas = try #require(DefinicoesPartilhadas.ler(raiz: raiz))
        #expect(lidas.contextoCurso == "Mestrado")
        #expect(lidas.linguaApontamentos == "klingon")
        #expect(lidas.organizacao == "por-luas")
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

    @Test func reconheceAPastaDasAulas() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let recap = raiz.appending(path: "Recap"), aulas = recap.appending(path: "Aulas")
        let lib = Library(raiz: aulas)
        try lib.criarCadeira(nome: "Cálculo")
        let cadeira = aulas.appending(path: "Cálculo")
        let aula = cadeira.appending(path: "2026-10-27_Aula 1")
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        try Disco.escreverMeta(AulaMeta(titulo: "Aula 1", data: .now, video: nil), em: aula)

        #expect(Disco.problemaPastaAulas(aulas) == nil)
        #expect(Disco.problemaPastaAulas(recap)?.contains("abre a pasta Aulas") == true)
        #expect(Disco.problemaPastaAulas(cadeira)?.contains("é uma cadeira") == true)
        #expect(Disco.problemaPastaAulas(aula)?.contains("é uma aula") == true)
        #expect(Disco.problemaPastaAulas(raiz)?.contains("não tem aulas do Recap") == true)
    }
}
