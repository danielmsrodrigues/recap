import Foundation
import Testing
@testable import Apontamentos

/// Regenera os apontamentos de todas as aulas da pasta Aulas com as definições da app, pelo mesmo pipeline do botão
/// "Gerar apontamentos de novo" (sem ecrã). Só com `APONTAMENTOS_REGENERAR=1`; `APONTAMENTOS_REGISTO=<ficheiro>`
/// recebe uma linha por aula; `APONTAMENTOS_APENAS=<a>,<b>` limita às aulas cujo caminho contém um destes textos.
/// A app instalada deve estar fechada.
@MainActor
struct RegenerarTodasTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_REGENERAR"] != nil), .timeLimit(.minutes(180)))
    func regeneraTodas() async throws {
        let definicoes = Definicoes()
        let library = Library(raiz: definicoes.raizAulas, organizacao: definicoes.organizacao,
                              iniciosPeriodos: definicoes.iniciosPeriodos, duracaoCurso: definicoes.duracaoCurso)
        library.recarregar()
        let fichas = Fichas(library: library, definicoes: definicoes)
        let estudo = Estudo(library: library, definicoes: definicoes)
        let runner = PipelineRunner(library: library, definicoes: definicoes, fichas: fichas, estudo: estudo)
        let registo = ProcessInfo.processInfo.environment["APONTAMENTOS_REGISTO"]
        var linhas: [String] = []
        let apenas = ProcessInfo.processInfo.environment["APONTAMENTOS_APENAS"]?.split(separator: ",").map(String.init) ?? []
        let aulas = library.cadeiras.flatMap(\.aulas).filter { aula in
            Disco.lerTranscricao(aula.pasta) != nil && (apenas.isEmpty || apenas.contains { aula.pasta.path.contains($0) })
        }
        for aula in aulas {
            let job = Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: nil, gerarApontamentos: true, soApontamentos: true)
            await runner.executar(job)
            linhas.append("\(aula.cadeira) / \(aula.pasta.lastPathComponent): \(job.estado)\(job.aviso.map { " — aviso: \($0)" } ?? "")")
            if let registo { try linhas.joined(separator: "\n").write(toFile: registo, atomically: true, encoding: .utf8) }
        }
        // As fichas e as ligações entre aulas correm depois de cada aula, em fundo.
        try await Task.sleep(for: .seconds(180))
        #expect(linhas.count == aulas.count)
    }
}
