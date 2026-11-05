import Foundation
import Testing
@testable import Apontamentos

/// A pasta das aulas e o curso a que pertence cada caminho.
@MainActor
struct BibliotecaTests {
    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "biblioteca-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func definicoes() throws -> Definicoes {
        Definicoes(defaults: try #require(UserDefaults(suiteName: "biblioteca-\(UUID().uuidString)")))
    }

    @Test func oCursoDeUmCaminhoEODaPasta() throws {
        let raiz = try pasta(), fora = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: fora) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let aula = try b.ativo.library.criarAula(cadeira: "Cálculo", titulo: "Límites", data: .now, video: nil)

        #expect(b.servicos(de: aula) === b.ativo)
        #expect(b.servicos(de: raiz) === b.ativo)
        #expect(b.servicos(de: fora) == nil)
        // Só com o nome a começar igual, não está lá dentro.
        #expect(b.servicos(de: URL(fileURLWithPath: raiz.path + "-outra")) == nil)
    }

    /// O mesmo caminho noutra normalização Unicode: os acentos podem vir decompostos do disco.
    @Test func estaDentroIgnoraANormalizacaoDosAcentos() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let composta = raiz.appending(path: "Cálculo".precomposedStringWithCanonicalMapping)
        let decomposta = raiz.appending(path: "Cálculo".decomposedStringWithCanonicalMapping)

        #expect(decomposta.appending(path: "aula").estaDentro(de: composta))
        #expect(composta.appending(path: "aula").estaDentro(de: decomposta))
        #expect(!composta.estaDentro(de: composta))
    }

    /// Sem saber de que curso é a aula, o job não começa: com o de outro, o glossário e a língua sairiam errados sem erro.
    @Test func umJobForaDaBibliotecaFalhaEMantemOAudio() async throws {
        let raiz = try pasta(), fora = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: fora) }
        let d = try definicoes()
        let runner = PipelineRunner(biblioteca: Biblioteca(raiz: raiz, definicoes: d), definicoes: d)
        let audio = fora.appending(path: "audio.caf")
        try Data("som".utf8).write(to: audio)

        let job = Job(pastaAula: fora.appending(path: "Cálculo/2026-09-01_Límites"), titulo: "Límites", video: nil,
                      gerarApontamentos: true, audioDireto: audio)
        await runner.executar(job)

        #expect(job.estado == .falhou("Esta aula já não está na pasta das aulas."))
        #expect(job.faseDe(.transcricao) == .pendente)
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    @Test func umJobDaBibliotecaEncontraOCursoDaAula() async throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let d = try definicoes()
        let b = Biblioteca(raiz: raiz, definicoes: d)
        let aula = try b.ativo.library.criarAula(cadeira: "Cálculo", titulo: "Límites", data: .now, video: nil)
        // Uma aula sem vídeo nem transcrição: chega à verificação da aula e falha ali, não por não ter curso.
        let job = Job(pastaAula: aula, titulo: "Límites", video: nil, gerarApontamentos: false)
        await PipelineRunner(biblioteca: b, definicoes: d).executar(job)

        guard case .falhou(let motivo) = job.estado else {
            Issue.record("O job devia ter falhado por não ter vídeo.")
            return
        }
        #expect(motivo.contains("vídeo"))
    }

    /// Mudar a pasta das aulas leva tudo o que está lá, incluindo o que está dentro de `_recap`.
    @Test func mudarAPastaLevaABibliotecaToda() throws {
        let raiz = try pasta()
        let nova = FileManager.default.temporaryDirectory.appending(path: "biblioteca-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: nova) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        _ = try b.ativo.library.criarAula(cadeira: "Cálculo", titulo: "Límites", data: .now, video: nil)
        try b.ativo.library.alterarPreferencias { $0.contextoCurso = "Mestrado" }
        let dentroDoSistema = raiz.appending(path: "_recap/cursos/Fintech360/_recap")
        try FileManager.default.createDirectory(at: dentroDoSistema, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dentroDoSistema.appending(path: "curso.json"))
        let curso = b.ativo

        try b.mudarRaiz(para: nova, mover: true)

        #expect(b.raiz.mesmoCaminho(nova))
        #expect(b.ativo === curso)
        #expect(b.ativo.library.cadeira(nome: "Cálculo")?.aulas.count == 1)
        #expect(b.ativo.library.contextoCurso == "Mestrado")
        #expect(FileManager.default.fileExists(atPath: nova.appending(path: "_recap/cursos/Fintech360/_recap/curso.json").path))
        #expect(!FileManager.default.fileExists(atPath: raiz.appending(path: "_recap").path))
    }

    @Test func sePrimeiroFalharAPastaFicaComoEstava() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())

        #expect(throws: ErroPasta.self) { try b.mudarRaiz(para: raiz.appending(path: "dentro"), mover: true) }
        #expect(b.raiz.mesmoCaminho(raiz))
    }

    /// Um pedido do iPhone chega ao curso pela caixa da sua pasta.
    @Test func aPonteRespondeNaCaixaDoCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let d = try definicoes()
        let b = Biblioteca(raiz: raiz, definicoes: d)
        let pedido = PedidoMac(tipo: .exercicios, aula: "Cálculo/nao-existe")
        try CaixaPedidos.enviar(pedido, raiz: raiz)

        PonteMac(biblioteca: b, definicoes: d).verificar()

        let estado = try #require(CaixaPedidos.estado(pedido.id, raiz: raiz))
        #expect(estado.fase == .erro)
        #expect(estado.erro?.contains("não está no Mac") == true)
    }
}
