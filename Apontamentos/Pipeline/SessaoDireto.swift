import CoreGraphics
import Foundation
import Observation

/// Uma aula a ser captada em direto: o som da app escolhida (o browser com a gravação, o Zoom…) vai para
/// um ficheiro temporário; no fim entra na fila como qualquer outra aula e o ficheiro é apagado.
@MainActor @Observable
final class SessaoDireto {
    enum Estado: Equatable {
        case parada, aPreparar, aOuvir, emPausa
        case falhou(String)
    }

    /// Termina sozinha depois deste silêncio (a gravação acabou).
    static let limiteSilencio: Double = 180

    private(set) var estado: Estado = .parada {
        didSet { fila?.emEspera = ativa }
    }
    private(set) var fonte: FonteAudio?
    private(set) var titulo = ""
    private(set) var velocidade = 1.0
    private(set) var segundos = 0.0
    private(set) var nivel: Float = -120
    private(set) var silencio = 0.0
    private(set) var houveSom = false
    private(set) var aviso: String?
    /// A imagem captada está preta há algum tempo (janela da aula escondida).
    private(set) var avisoPreto = false
    private var pretaDesde: Double?
    /// O que está a ser captado da janela da aula (nil = sem slides ou ainda sem imagem).
    private(set) var previa: CGImage?

    private var pastaAula: URL?
    private var gerarApontamentos = true
    private var captura: CapturaAudio?
    private var gravador: GravadorTemporario?
    private var frames: GravadorFrames?
    private var relogio: Task<Void, Never>?
    private weak var library: Library?
    private weak var fila: ProcessingQueue?

    var ativa: Bool { [.aPreparar, .aOuvir, .emPausa].contains(estado) }
    /// Há som a chegar neste momento.
    var comSom: Bool { estado == .aOuvir && nivel > GravadorTemporario.limiarSom }
    /// Tempo de aula correspondente ao que já foi captado.
    var segundosDeAula: Double { segundos * velocidade }

    func comecar(fonte: FonteAudio, cadeira: String, titulo: String, data: Date, velocidade: Double,
                 gerarApontamentos: Bool, capturarSlides: Bool, library: Library, fila: ProcessingQueue) async {
        guard !ativa else { return }
        estado = .aPreparar
        aviso = nil
        self.fonte = fonte
        self.titulo = titulo
        self.velocidade = velocidade
        self.gerarApontamentos = gerarApontamentos
        self.library = library
        self.fila = fila
        fila.emEspera = true
        segundos = 0; silencio = 0; houveSom = false; nivel = -120; previa = nil; pretaDesde = nil; avisoPreto = false
        do {
            let g = try GravadorTemporario()
            let f = capturarSlides ? try GravadorFrames() : nil
            var aoFrame: (@Sendable (CGImage) -> Void)?
            if let f { aoFrame = { imagem in f.receber(imagem) } }
            let c = CapturaAudio(aoReceber: { buffer in _ = g.escrever(buffer) },
                                 aoFrame: aoFrame,
                                 aoPararJanela: { [weak self] _ in Task { @MainActor in self?.semJanela() } },
                                 aoParar: { [weak self] erro in Task { @MainActor in self?.interrompida(erro) } })
            gravador = g
            frames = f
            try await c.iniciar(fonte)
            captura = c
            pastaAula = try library.criarAula(cadeira: cadeira, titulo: titulo, data: data, video: nil)
            estado = .aOuvir
            relogio = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.atualizar()
                }
            }
        } catch {
            await limpar(apagarAula: true)
            estado = .falhou(error.localizedDescription)
        }
    }

    func pausar(_ pausar: Bool) {
        guard estado == .aOuvir || estado == .emPausa else { return }
        gravador?.definirPausa(pausar)
        estado = pausar ? .emPausa : .aOuvir
    }

    /// Para de ouvir e põe a aula na fila (transcrição e, se pedido, apontamentos).
    func terminar() async {
        guard ativa, let gravador, let pastaAula else { return }
        await captura?.parar()
        relogio?.cancel()
        if gravador.segundos < 5 || !gravador.houveSom {
            await limpar(apagarAula: true)
            estado = .falhou("Não se ouviu nada da aplicação escolhida. Confirma que a gravação estava a tocar e que o separador não estava silenciado.")
            return
        }
        frames?.concluir()
        fila?.adicionar(Job(pastaAula: pastaAula, titulo: titulo, video: nil, gerarApontamentos: gerarApontamentos,
                            audioDireto: gravador.url, velocidade: velocidade, framesDireto: frames?.pasta))
        self.gravador = nil
        frames = nil
        previa = nil
        captura = nil
        self.pastaAula = nil
        estado = .parada
    }

    /// Para sem guardar nada.
    func descartar() async {
        await limpar(apagarAula: true)
        estado = .parada
    }

    func fecharErro() {
        if case .falhou = estado { estado = .parada }
    }

    private func atualizar() {
        guard let gravador, ativa else { return }
        segundos = gravador.segundos
        nivel = gravador.nivel
        houveSom = gravador.houveSom
        silencio = houveSom ? gravador.segundosEmSilencio : 0
        // Cada imagem fica com o tempo de áudio já captado; em pausa não se guarda nada.
        if let frames, let s = gravador.segundosSeAtivo {
            frames.gravarSeDevido(segundos: s)
            let ultima = frames.ultimaImagem
            if ultima !== previa {
                previa = ultima
                pretaDesde = ultima.map(CapturaAudio.centroPreto) == true ? (pretaDesde ?? s) : nil
            }
            // Preto há mais de 10 s com som a tocar: o vídeo não está a ser desenhado.
            if let desde = pretaDesde, s - desde > 10, comSom {
                avisoPreto = true
            } else if pretaDesde == nil {
                avisoPreto = false
            }
            if s > 10, !frames.temImagem, aviso == nil {
                aviso = "Não está a chegar nenhuma imagem da janela da aula: se estiver minimizada, abre-a (pode ficar por trás de outras). Sem isso não há slides."
            }
        }
        if estado == .aOuvir, houveSom, silencio >= Self.limiteSilencio {
            Task { await terminar() }
        }
    }

    private func semJanela() {
        guard ativa else { return }
        aviso = "Deixei de ver a janela da aula (fechada ou minimizada): a partir daqui não há slides. O som continua a ser captado."
    }

    private func interrompida(_ erro: (any Error)?) {
        guard ativa else { return }
        aviso = "A captação parou: \(erro?.localizedDescription ?? "a aplicação fechou"). O que já foi captado vai ser transcrito."
        Task { await terminar() }
    }

    private func limpar(apagarAula: Bool) async {
        await captura?.parar()
        relogio?.cancel()
        gravador?.apagar()
        frames?.apagar()
        frames = nil
        previa = nil
        if apagarAula, let pastaAula { try? library?.moverParaLixo(pastaAula) }
        captura = nil
        gravador = nil
        pastaAula = nil
    }
}
