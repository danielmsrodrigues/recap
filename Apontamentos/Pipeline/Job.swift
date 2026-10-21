import Foundation
import Observation

enum Etapa: Int, CaseIterable, Identifiable, Sendable {
    case audio, transcricao, slides, apontamentos

    var id: Int { rawValue }

    var nome: String {
        switch self {
        case .audio: "Extrair áudio"
        case .transcricao: "Transcrever"
        case .slides: "Extrair slides"
        case .apontamentos: "Gerar apontamentos"
        }
    }
}

struct EstadoEtapa: Equatable, Sendable {
    enum Fase: Equatable, Sendable { case pendente, emCurso, concluida, saltada, falhou }
    var fase: Fase = .pendente
    /// nil = indeterminado
    var progresso: Double?
    var detalhe: String?
}

/// Um vídeo (ou uma regeneração) na fila de processamento.
@MainActor @Observable
final class Job: Identifiable {
    enum Estado: Equatable {
        case emEspera, aCorrer, concluido, cancelado
        case falhou(String)
    }

    let id = UUID()
    let pastaAula: URL
    let titulo: String
    let video: URL?
    /// Áudio captado em direto (ficheiro temporário, apagado depois de transcrito).
    let audioDireto: URL?
    /// Velocidade a que a gravação tocou durante a captação; os timestamps são corrigidos por este fator.
    let velocidade: Double
    /// Capturas das janelas da aula feitas em direto (pasta temporária, apagada depois de escolhidos os slides).
    let framesDireto: URL?
    /// Gerar apontamentos no fim (desligado = só transcrever).
    let gerarApontamentos: Bool
    /// Regenerar: a transcrição tem de existir, as outras etapas são saltadas.
    let soApontamentos: Bool

    var estado: Estado = .emEspera
    /// Fase e detalhe de cada etapa. O progresso vive à parte, em `progressos`: muda várias vezes por segundo,
    /// e quem só quer a fase (a aula e a sua toolbar) não deve ser redesenhado a cada passo.
    private var etapas: [Etapa: EstadoEtapa] = [:]
    private var progressos: [Etapa: Double] = [:]
    var textoEmCurso = ""
    var aviso: String?
    var task: Task<Void, Never>?

    init(pastaAula: URL, titulo: String, video: URL?, gerarApontamentos: Bool, soApontamentos: Bool = false,
         audioDireto: URL? = nil, velocidade: Double = 1, framesDireto: URL? = nil) {
        self.pastaAula = pastaAula
        self.titulo = titulo
        self.video = video
        self.audioDireto = audioDireto
        self.velocidade = velocidade
        self.framesDireto = framesDireto
        self.gerarApontamentos = gerarApontamentos || soApontamentos
        self.soApontamentos = soApontamentos
        reiniciar()
    }

    var ativo: Bool { estado == .emEspera || estado == .aCorrer }

    func estadoDe(_ e: Etapa) -> EstadoEtapa {
        var estado = etapas[e] ?? EstadoEtapa()
        estado.progresso = progressos[e]
        return estado
    }

    func faseDe(_ e: Etapa) -> EstadoEtapa.Fase { etapas[e]?.fase ?? .pendente }

    func reiniciar() {
        estado = .emEspera
        aviso = nil
        textoEmCurso = ""
        for e in Etapa.allCases { etapas[e] = EstadoEtapa() }
        progressos = [:]
        if soApontamentos { etapas[.audio]?.fase = .saltada; etapas[.transcricao]?.fase = .saltada }
        if !gerarApontamentos { etapas[.apontamentos]?.fase = .saltada }
    }

    func iniciar(_ e: Etapa, detalhe: String? = nil, progresso: Double? = nil) {
        etapas[e] = EstadoEtapa(fase: .emCurso, detalhe: detalhe)
        progressos[e] = progresso
    }

    func atualizar(_ e: Etapa, progresso: Double?, detalhe: String? = nil) {
        guard etapas[e]?.fase == .emCurso else { return }
        if let detalhe, etapas[e]?.detalhe != detalhe { etapas[e]?.detalhe = detalhe }
        // O Whisper e os slides chamam isto muitas vezes por segundo; abaixo de meio ponto não se vê na barra
        // e só obrigava a redesenhar a fila e a barra lateral.
        if detalhe == nil, let p = progresso, let atual = progressos[e], p < 1, abs(p - atual) < 0.005 { return }
        if progressos[e] != progresso { progressos[e] = progresso }
    }

    func concluir(_ e: Etapa, detalhe: String? = nil) {
        etapas[e] = EstadoEtapa(fase: .concluida, detalhe: detalhe)
        progressos[e] = 1
    }

    func saltar(_ e: Etapa, detalhe: String? = nil) {
        etapas[e] = EstadoEtapa(fase: .saltada, detalhe: detalhe)
        progressos[e] = nil
    }

    /// Marca como falhada a etapa em curso.
    func falhar(_ mensagem: String) {
        if let e = Etapa.allCases.first(where: { etapas[$0]?.fase == .emCurso }) {
            etapas[e]?.fase = .falhou
        }
        estado = .falhou(mensagem)
    }

    func cancelar() {
        for e in Etapa.allCases where etapas[e]?.fase == .emCurso { etapas[e]?.fase = .pendente }
        estado = .cancelado
    }
}
