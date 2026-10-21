import Foundation
import Testing
@testable import Apontamentos

@MainActor
struct JobTests {
    @Test func progressoSoMudaQuandoSeVe() {
        let job = Job(pastaAula: URL(filePath: "/tmp/aula"), titulo: "Aula", video: nil, gerarApontamentos: false)
        job.iniciar(.transcricao, progresso: 0)

        // Os passos pequenos do Whisper não redesenham a fila; somados, passam a contar.
        job.atualizar(.transcricao, progresso: 0.001)
        job.atualizar(.transcricao, progresso: 0.004)
        #expect(job.estadoDe(.transcricao).progresso == 0)
        job.atualizar(.transcricao, progresso: 0.006)
        #expect(job.estadoDe(.transcricao).progresso == 0.006)

        // Um detalhe novo, o indeterminado e o fim passam sempre.
        job.atualizar(.transcricao, progresso: 0.007, detalhe: "A transcrever…")
        #expect(job.estadoDe(.transcricao).detalhe == "A transcrever…")
        job.atualizar(.transcricao, progresso: nil)
        #expect(job.estadoDe(.transcricao).progresso == nil)
        job.atualizar(.transcricao, progresso: 0.998)
        job.atualizar(.transcricao, progresso: 1)
        #expect(job.estadoDe(.transcricao).progresso == 1)
    }
}
