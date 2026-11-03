import Foundation
import Synchronization
import Testing
@testable import Apontamentos

/// Com "Otimizar armazenamento", o iCloud pode tirar os ficheiros do Mac. As aulas têm de voltar sozinhas à lista,
/// e não podem ficar escondidas sem aviso enquanto não chegam.
@MainActor
struct AulasNaNuvemTests {
    private func raizComAula() throws -> (raiz: URL, aula: URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let aula = raiz.appending(path: "Cálculo/2026-09-01_Límites")
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        return (raiz, aula)
    }

    /// Só existe "na nuvem" o `aula.json` que ainda não está na pasta.
    nonisolated private static func naNuvem(_ url: URL) -> Bool {
        url.lastPathComponent == Disco.aulaJSON && !FileManager.default.fileExists(atPath: url.path)
    }

    nonisolated private static func chegar(_ url: URL) throws {
        try Disco.escreverMeta(AulaMeta(titulo: "Límites", data: .now, video: nil), em: url.deletingLastPathComponent())
    }

    private func esperar(_ condicao: () -> Bool) async throws {
        for _ in 0..<300 where !condicao() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aulaNaNuvemAvisaEVoltaSozinhaALista() async throws {
        let (raiz, aula) = try raizComAula()
        defer { try? FileManager.default.removeItem(at: raiz) }

        let library = Library(raiz: raiz, porDescarregar: Self.naNuvem, trazer: Self.chegar)
        #expect(library.aulasNaNuvem == 1)
        #expect(library.aula(em: aula) == nil)

        try await esperar { library.aula(em: aula) != nil }
        #expect(library.aula(em: aula)?.meta.titulo == "Límites")
        #expect(library.aulasNaNuvem == 0)
    }

    @Test func tentaOutraVezQuandoODownloadFalha() async throws {
        let (raiz, aula) = try raizComAula()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let tentativas = Mutex(0)

        let library = Library(raiz: raiz, porDescarregar: Self.naNuvem, trazer: { url in
            let n = tentativas.withLock { $0 += 1; return $0 }
            if n == 1 { throw CocoaError(.fileReadUnknown) }
            try Self.chegar(url)
        }, esperaAoFalhar: .milliseconds(10))

        try await esperar { library.aula(em: aula) != nil }
        #expect(library.aula(em: aula) != nil)
        #expect(tentativas.withLock { $0 } == 2)
    }

    @Test func pastaSemAulaNaoContaComoNuvem() throws {
        let (raiz, aula) = try raizComAula()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo/lixo"), withIntermediateDirectories: true)
        try Self.chegar(aula.appending(path: Disco.aulaJSON))

        let library = Library(raiz: raiz)
        #expect(library.aulasNaNuvem == 0)
        #expect(library.aula(em: aula) != nil)
    }

    @Test func abrirAulaTrazSoOQueFalta() throws {
        let (raiz, aula) = try raizComAula()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let slides = aula.appending(path: Disco.pastaSlides)
        try FileManager.default.createDirectory(at: slides, withIntermediateDirectories: true)
        for f in [aula.appending(path: Disco.apontamentosMD), aula.appending(path: Disco.slidesJSON), slides.appending(path: "1.jpg")] {
            try Data().write(to: f)
        }
        let naNuvem: Set<String> = [Disco.apontamentosMD, "1.jpg"]
        var trazidos: [String] = []

        let n = Disco.trazerPasta(aula, porDescarregar: { naNuvem.contains($0.lastPathComponent) }, trazer: { trazidos.append($0.lastPathComponent) })

        #expect(n == 2)
        #expect(Set(trazidos) == naNuvem)
    }
}
