import Foundation
import Observation

/// Processa um job de cada vez, pela ordem em que entraram.
@MainActor @Observable
final class ProcessingQueue {
    private(set) var jobs: [Job] = []
    private let runner: PipelineRunner
    private var aCorrer = false
    /// Enquanto uma aula é captada em direto, não começa trabalho pesado (a chamada não fica lenta).
    var emEspera = false {
        didSet { if !emEspera { avancar() } }
    }

    init(runner: PipelineRunner) {
        self.runner = runner
    }

    func adicionar(_ job: Job) {
        // Uma aula só tem um job ativo de cada vez.
        if jobs.contains(where: { $0.pastaAula.mesmoCaminho(job.pastaAula) && $0.ativo }) { return }
        jobs.removeAll { $0.pastaAula.mesmoCaminho(job.pastaAula) }
        jobs.append(job)
        avancar()
    }

    func job(para pasta: URL) -> Job? {
        jobs.last { $0.pastaAula.mesmoCaminho(pasta) }
    }

    func cancelar(_ job: Job) {
        if job.estado == .aCorrer {
            job.task?.cancel()
        } else if job.estado == .emEspera {
            job.cancelar()
        }
    }

    func repetir(_ job: Job) {
        guard !job.ativo else { return }
        job.reiniciar()
        avancar()
    }

    func remover(_ job: Job) {
        guard !job.ativo else { return }
        jobs.removeAll { $0.id == job.id }
    }

    private func avancar() {
        guard !aCorrer, !emEspera, let proximo = jobs.first(where: { $0.estado == .emEspera }) else {
            if !aCorrer, !jobs.contains(where: \.ativo) { runner.filaVazia() }
            return
        }
        aCorrer = true
        proximo.estado = .aCorrer
        proximo.task = Task {
            await runner.executar(proximo)
            proximo.task = nil
            aCorrer = false
            avancar()
        }
    }
}
