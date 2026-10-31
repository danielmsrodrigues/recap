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
    /// Os bocados (tempo de aula) marcados com "Não estou a perceber", por ordem; o último pode estar aberto.
    private(set) var naoPercebi: [IntervaloNaoPercebi] = []
    /// "Não estou a perceber" está ligado: o botão passa a "Já percebi".
    var aNaoPerceber: Bool { naoPercebi.last.map { $0.fim == nil } ?? false }
    /// A janela "Em direto" está a mostrar as janelas para mudar (#39). Enquanto se escolhe, não termina sozinha
    /// por silêncio (o aviso não se vê); fecha quando a captação acaba.
    var escolherJanela = false
    private var aMudarJanela = false

    private var pastaAula: URL?
    private var gerarApontamentos = true
    private var captura: (any Captacao)?
    private let criarCaptacao: (EventosCaptacao) -> any Captacao
    private var gravador: GravadorTemporario?
    private var frames: GravadorFrames?
    /// Onde ficam o áudio e as imagens, com a ficha da aula (ver `CaptacaoGuardada`).
    private var guardada: CaptacaoGuardada?
    private var relogio: Task<Void, Never>?
    private weak var library: Library?
    private weak var fila: ProcessingQueue?

    init(criarCaptacao: @escaping (EventosCaptacao) -> any Captacao = { CapturaAudio($0) }) {
        self.criarCaptacao = criarCaptacao
    }

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
        naoPercebi = []
        do {
            let c0 = try CaptacaoGuardada.criar()
            guardada = c0
            let g = try GravadorTemporario(url: c0.audio)
            let f = capturarSlides ? try GravadorFrames(janela: fonte.janela, pasta: c0.frames) : nil
            var aoFrame: (@Sendable (CGImage) -> Void)?
            var aoMudarJanela: (@Sendable (CGWindowID) -> Void)?
            if let f {
                aoFrame = { imagem in f.receber(imagem) }
                aoMudarJanela = { janela in f.novoTroco(janela: janela) }
            }
            let c = criarCaptacao(EventosCaptacao(
                aoReceber: { buffer in _ = g.escrever(buffer) },
                aoFrame: aoFrame,
                aoPararJanela: { [weak self] _ in Task { @MainActor in self?.semJanela() } },
                aoParar: { [weak self] erro in Task { @MainActor in self?.interrompida(erro) } },
                aoMudarJanela: aoMudarJanela))
            gravador = g
            frames = f
            try await c.iniciar(fonte)
            captura = c
            let aula = try library.criarAula(cadeira: cadeira, titulo: titulo, data: data, video: nil)
            pastaAula = aula
            // A partir daqui, se a app fechar, a captação volta à fila ao abrir.
            try? c0.guardar(.init(pastaAula: aula, titulo: titulo, velocidade: velocidade, gerarApontamentos: gerarApontamentos))
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

    /// Passa a captar outra janela sem parar (#39): o som, o tempo e a aula continuam. Se a janela for de outra
    /// aplicação, o som passa a vir dela. As imagens da janela nova vão para outro troço (ver `SlidesDireto`).
    func mudarJanela(_ nova: FonteAudio) async {
        guard ativa, let captura, let atual = fonte, nova.id != atual.id, !aMudarJanela else { return }
        aMudarJanela = true
        defer { aMudarJanela = false }
        do {
            let comImagens = try await captura.mudar(para: nova)
            // O silêncio da aplicação anterior (o motivo habitual para mudar) não conta para terminar.
            if nova.bundleID != atual.bundleID { gravador?.reiniciarSilencio() }
            fonte = nova
            previa = nil
            pretaDesde = nil
            avisoPreto = false
            aviso = comImagens || frames == nil ? nil
                : "Passei para \"\(nova.tituloJanela)\", mas não consigo captar a imagem dela (minimizada?): a partir daqui não há slides. O som continua a ser captado."
        } catch {
            aviso = "Não consegui mudar para \"\(nova.tituloJanela)\": \(error.localizedDescription) Continua a ser captada a janela anterior."
        }
    }

    /// "Não estou a perceber" abre um bocado da aula; "Já percebi" fecha-o. Fica logo na aula (se a app fechar, não se
    /// perde), e os apontamentos explicam esse tema outra vez. O tempo é o do gravador nesse instante, não o do relógio
    /// da janela (atualizado de meio em meio segundo).
    func alternarNaoPercebi() {
        guard ativa, let gravador else { return }
        let agora = (gravador.segundos * velocidade).rounded()
        if aNaoPerceber {
            naoPercebi[naoPercebi.count - 1].fim = max(agora, naoPercebi[naoPercebi.count - 1].inicio)
        } else {
            naoPercebi.append(IntervaloNaoPercebi(inicio: agora))
        }
        guardarNaoPercebi()
    }

    /// Um "Não estou a perceber" ainda aberto fecha no fim da captação.
    func fecharNaoPercebi() {
        guard aNaoPerceber, let gravador else { return }
        naoPercebi[naoPercebi.count - 1].fim = max((gravador.segundos * velocidade).rounded(), naoPercebi[naoPercebi.count - 1].inicio)
        guardarNaoPercebi()
    }

    private func guardarNaoPercebi() {
        guard let pastaAula else { return }
        do {
            var meta = try Disco.lerMeta(pastaAula)
            meta.naoPercebi = naoPercebi
            try Disco.escreverMeta(meta, em: pastaAula)
        } catch {
            aviso = "Não consegui guardar o bocado que não percebeste: \(error.localizedDescription)"
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
        gravador.fechar()
        fecharNaoPercebi()
        fila?.adicionar(Job(pastaAula: pastaAula, titulo: titulo, video: nil, gerarApontamentos: gerarApontamentos,
                            audioDireto: gravador.url, velocidade: velocidade, framesDireto: frames?.pasta))
        self.gravador = nil
        frames = nil
        guardada = nil
        previa = nil
        captura = nil
        escolherJanela = false
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
        // Disco cheio (ou outro erro a gravar): termina com o que já foi captado, em vez de perder o resto calado.
        if let erro = gravador.erroEscrita, estado == .aOuvir || estado == .emPausa {
            aviso = "Não consegui continuar a gravar o áudio (\(erro)). O que já foi captado vai ser transcrito."
            Task { await terminar() }
            return
        }
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
        if estado == .aOuvir, houveSom, silencio >= Self.limiteSilencio, !escolherJanela, !aMudarJanela {
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
        guardada?.apagar()
        guardada = nil
        frames = nil
        previa = nil
        if apagarAula, let pastaAula { try? library?.moverParaLixo(pastaAula) }
        captura = nil
        gravador = nil
        pastaAula = nil
        escolherJanela = false
    }
}
