import Foundation
import Observation
import Synchronization
import Testing
@testable import Apontamentos

@MainActor
struct PerguntaPDFTests {
    @Test func respostaPedidaEmPDF() {
        let pdf = PerguntaAula(pergunta: "Faz-me um PDF", resposta: "\n<!-- pdf -->\n# Resumen\n\nTexto")
        #expect(pdf.documentoPDF == "# Resumen\n\nTexto")
        #expect(PerguntaAula(pergunta: "p", resposta: "Uma resposta normal").documentoPDF == nil)
        #expect(Estudo.sistemaPerguntas.contains("`<!-- pdf -->`"))
    }
}

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

    /// A aula (e a sua toolbar) só lê a fase: o progresso e o texto a chegar não a podem redesenhar.
    @Test func faseNaoMudaComOProgresso() {
        let job = Job(pastaAula: URL(filePath: "/tmp/aula"), titulo: "Aula", video: nil, gerarApontamentos: true)
        job.iniciar(.transcricao, progresso: 0)
        job.iniciar(.slides, progresso: 0)
        let mudou = Mutex(false)
        withObservationTracking {
            _ = job.estado
            _ = job.faseDe(.apontamentos)
        } onChange: { mudou.withLock { $0 = true } }

        job.atualizar(.transcricao, progresso: 0.5)
        job.atualizar(.slides, progresso: 0.9)
        job.atualizar(.transcricao, progresso: 0.6, detalhe: nil)
        #expect(!mudou.withLock { $0 })
        #expect(job.estadoDe(.slides).progresso == 0.9)

        job.iniciar(.apontamentos)
        #expect(mudou.withLock { $0 })
    }
}
