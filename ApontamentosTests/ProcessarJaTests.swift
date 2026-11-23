import Foundation
import Testing
@testable import Apontamentos

/// Durante uma aula em direto a fila fica em pausa; "Processar já" deixa-a avançar.
@MainActor
struct ProcessarJaTests {
    private func fila() throws -> ProcessingQueue {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "processar-ja-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let d = Definicoes(defaults: try #require(UserDefaults(suiteName: "processar-ja-\(UUID().uuidString)")))
        let library = Library(raiz: raiz)
        return ProcessingQueue(runner: PipelineRunner(library: library, definicoes: d, fichas: Fichas(library: library, definicoes: d),
                                                      estudo: Estudo(library: library, definicoes: d)))
    }

    private func job() -> Job {
        Job(pastaAula: FileManager.default.temporaryDirectory.appending(path: "aula-\(UUID().uuidString)"),
            titulo: "Aula", video: nil, gerarApontamentos: false)
    }

    @Test func emDiretoAFilaEsperaAteProcessarJa() throws {
        let f = try fila()
        f.emEspera = true
        let j = job()
        f.adicionar(j)
        #expect(j.estado == .emEspera)
        #expect(f.pausada)

        f.processarJa()
        #expect(j.estado == .aCorrer)
        #expect(!f.pausada)
        f.cancelar(j)
    }

    @Test func novaAulaEmDiretoVoltaAPausar() throws {
        let f = try fila()
        f.emEspera = true
        f.processarJa()
        f.emEspera = true   // a mesma aula muda de estado (ex.: em pausa): continua forçada
        #expect(f.processarDuranteDireto)
        f.emEspera = false
        f.emEspera = true   // aula seguinte
        #expect(!f.processarDuranteDireto)
        let j = job()
        f.adicionar(j)
        #expect(j.estado == .emEspera)
        #expect(f.pausada)
    }
}
