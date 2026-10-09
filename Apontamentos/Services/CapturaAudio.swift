import AppKit
import AVFoundation
import ScreenCaptureKit
import VideoToolbox

enum ErroCaptura: LocalizedError {
    case semPermissao
    case appNaoEncontrada
    case falhou(String)

    var errorDescription: String? {
        switch self {
        case .semPermissao:
            "O Recap precisa de autorização para ouvir o áudio do Mac. Em Definições do Sistema → Privacidade e Segurança → Gravação de ecrã e áudio do sistema, ativa o Recap e volta a abri-lo."
        case .appNaoEncontrada:
            "A aplicação escolhida já não está aberta."
        case .falhou(let detalhe):
            "Não foi possível ouvir o áudio: \(detalhe)"
        }
    }
}

/// Uma janela onde corre a aula (o browser, o Zoom…). O som vem da aplicação dona da janela;
/// as imagens para os slides vêm só desta janela.
struct FonteAudio: Identifiable, Hashable, Sendable {
    var id: CGWindowID { janela }
    let bundleID: String
    let nome: String
    let janela: CGWindowID
    let tituloJanela: String
    let pid: pid_t

    /// Browser, Zoom ou Teams: onde as aulas costumam correr.
    var ehConhecida: Bool { Self.browsersConhecidos.contains(bundleID) }

    static let browsersConhecidos = ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
                                     "org.mozilla.firefox", "com.brave.Browser", "us.zoom.xos", "com.microsoft.teams2"]
}

/// Ouve só o áudio de uma aplicação (nunca o microfone) com o ScreenCaptureKit e entrega-o em buffers PCM.
final class CapturaAudio: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let fila = DispatchQueue(label: "pt.danielrodrigues.Recap.captura")
    private let aoReceber: @Sendable (AVAudioPCMBuffer) -> Void
    private let aoParar: @Sendable (Error?) -> Void
    /// Recebe uma imagem da janela escolhida quando ela muda (para os slides). nil = só som.
    private let aoFrame: (@Sendable (CGImage) -> Void)?
    /// A captura da janela parou (fechada, minimizada…) mas o som continua.
    private let aoPararJanela: (@Sendable (Error) -> Void)?
    private let trinco = NSLock()
    private var stream: SCStream?
    private var streamJanela: SCStream?

    init(aoReceber: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
         aoFrame: (@Sendable (CGImage) -> Void)? = nil,
         aoPararJanela: (@Sendable (Error) -> Void)? = nil,
         aoParar: @escaping @Sendable (Error?) -> Void) {
        self.aoReceber = aoReceber
        self.aoFrame = aoFrame
        self.aoPararJanela = aoPararJanela
        self.aoParar = aoParar
    }

    /// Janelas normais das aplicações abertas (sem processos auxiliares nem painéis), com os browsers e o Zoom primeiro.
    static func fontes() async throws -> [FonteAudio] {
        let conteudo = try await partilhavel()
        let proprio = Bundle.main.bundleIdentifier
        let fontes = conteudo.windows.compactMap { j -> FonteAudio? in
            guard let app = j.owningApplication, app.bundleIdentifier != proprio, !app.applicationName.isEmpty,
                  // 0 = janelas normais; 3 = flutuantes, como o picture-in-picture do browser.
                  j.windowLayer == 0 || j.windowLayer == 3, j.frame.width >= 200, j.frame.height >= 110,
                  let titulo = j.title?.trimmingCharacters(in: .whitespaces), !titulo.isEmpty,
                  NSRunningApplication(processIdentifier: app.processID)?.activationPolicy == .regular
            else { return nil }
            return FonteAudio(bundleID: app.bundleIdentifier, nome: app.applicationName, janela: j.windowID, tituloJanela: titulo, pid: app.processID)
        }
        let ordem = FonteAudio.browsersConhecidos
        return fontes.sorted {
            let a = ordem.firstIndex(of: $0.bundleID) ?? Int.max, b = ordem.firstIndex(of: $1.bundleID) ?? Int.max
            if a != b { return a < b }
            if $0.nome != $1.nome { return $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
            return $0.tituloJanela.localizedStandardCompare($1.tituloJanela) == .orderedAscending
        }
    }

    /// Miniaturas das janelas, para escolher a da aula a ver o conteúdo. Janelas minimizadas não têm imagem.
    @concurrent
    static func miniaturas(_ ids: [CGWindowID], largura: Int = 480) async -> [CGWindowID: CGImage] {
        guard let conteudo = try? await partilhavel() else { return [:] }
        var resultado: [CGWindowID: CGImage] = [:]
        for janela in conteudo.windows where ids.contains(janela.windowID) {
            let filtro = SCContentFilter(desktopIndependentWindow: janela)
            let config = SCStreamConfiguration()
            (config.width, config.height) = Self.tamanho(janela, filtro, largura: largura)
            config.showsCursor = false
            if let imagem = try? await SCScreenshotManager.captureImage(contentFilter: filtro, configuration: config),
               !uniforme(imagem) {
                resultado[janela.windowID] = imagem
            }
        }
        return resultado
    }

    /// Tamanho da captura: até `largura` px, sem passar dos píxeis reais da janela. Maior do que a janela,
    /// o ScreenCaptureKit não amplia: a imagem ficava num canto (acontece com o picture-in-picture).
    private static func tamanho(_ janela: SCWindow, _ filtro: SCContentFilter, largura: Int) -> (Int, Int) {
        let pixeis = janela.frame.width * CGFloat(filtro.pointPixelScale)
        let w = max(1, min(largura, Int(pixeis)))
        return (w, max(1, Int(janela.frame.height * CGFloat(w) / max(1, janela.frame.width))))
    }

    /// O centro da imagem está todo preto: é o que se capta quando o Chrome deixa de desenhar o vídeo
    /// (janela escondida atrás de outras, noutro desktop…).
    static func centroPreto(_ imagem: CGImage) -> Bool {
        let lado = 16
        guard let recorte = imagem.cropping(to: CGRect(x: imagem.width / 4, y: imagem.height / 4,
                                                       width: imagem.width / 2, height: imagem.height / 2)),
              let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0), let dados = ctx.data else { return false }
        ctx.draw(recorte, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        let escuros = (0..<lado * lado).filter { dados.load(fromByteOffset: $0, as: UInt8.self) < 10 }.count
        return escuros >= lado * lado * 95 / 100
    }

    /// Imagem toda da mesma cor: é o que o macOS devolve para uma janela minimizada.
    static func uniforme(_ imagem: CGImage) -> Bool {
        let lado = 16
        guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: lado,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0), let dados = ctx.data else { return false }
        ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        let valores = (0..<lado * lado).map { Int(dados.load(fromByteOffset: $0, as: UInt8.self)) }.sorted()
        // Quase tudo igual à mediana (os cantos arredondados e a sombra não contam).
        let mediana = valores[valores.count / 2]
        return valores.filter { abs($0 - mediana) <= 4 }.count >= valores.count * 9 / 10
    }

    private static func partilhavel() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            throw ErroCaptura.semPermissao
        }
    }

    func iniciar(_ fonte: FonteAudio) async throws {
        let conteudo = try await Self.partilhavel()
        guard let app = conteudo.applications.first(where: { $0.bundleIdentifier == fonte.bundleID }) else { throw ErroCaptura.appNaoEncontrada }
        guard let ecra = conteudo.displays.first else { throw ErroCaptura.falhou("nenhum ecrã") }

        // O som: o ScreenCaptureKit só separa o áudio por aplicação, não por janela nem separador.
        let filtro = SCContentFilter(display: ecra, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // Só queremos o som; o vídeo deste stream fica no mínimo possível.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let s = SCStream(filter: filtro, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: fila)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: fila)
            try await s.startCapture()
        } catch {
            throw ErroCaptura.falhou(error.localizedDescription)
        }
        trinco.withLock { stream = s }

        // As imagens para os slides: só a janela escolhida, mesmo que fique tapada por outras.
        if aoFrame != nil, let janela = conteudo.windows.first(where: { $0.windowID == fonte.janela }) {
            let filtroJanela = SCContentFilter(desktopIndependentWindow: janela)
            let config = SCStreamConfiguration()
            // 1920 px: o texto de um ecrã partilhado dentro do leitor ainda se lê depois de recortado.
            (config.width, config.height) = Self.tamanho(janela, filtroJanela, largura: 1920)
            config.minimumFrameInterval = CMTime(value: 2, timescale: 1)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.queueDepth = 3
            let v = SCStream(filter: filtroJanela, configuration: config, delegate: self)
            // Registado antes de começar, para as primeiras imagens e erros já serem reconhecidos como da janela.
            trinco.withLock { streamJanela = v }
            do {
                try v.addStreamOutput(self, type: .screen, sampleHandlerQueue: fila)
                try await v.startCapture()
            } catch {
                trinco.withLock { streamJanela = nil }
                // Sem imagens a aula continua a ser captada; só fica sem slides.
                aoPararJanela?(error)
            }
        }
    }

    func parar() async {
        let (s, v) = trinco.withLock { () -> (SCStream?, SCStream?) in
            defer { stream = nil; streamJanela = nil }
            return (stream, streamJanela)
        }
        try? await s?.stopCapture()
        try? await v?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer amostras: CMSampleBuffer, of tipo: SCStreamOutputType) {
        if tipo == .screen {
            if stream === trinco.withLock({ streamJanela }) { entregarFrame(amostras) }
            return
        }
        guard tipo == .audio, amostras.isValid, let descricao = amostras.formatDescription else { return }
        let formato = AVAudioFormat(cmAudioFormatDescription: descricao)
        let n = AVAudioFrameCount(amostras.numSamples)
        guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n) else { return }
        buffer.frameLength = n
        let estado = CMSampleBufferCopyPCMDataIntoAudioBufferList(amostras, at: 0, frameCount: Int32(n), into: buffer.mutableAudioBufferList)
        guard estado == noErr else { return }
        aoReceber(buffer)
    }

    private func entregarFrame(_ amostras: CMSampleBuffer) {
        guard let aoFrame, amostras.isValid,
              let anexos = CMSampleBufferGetSampleAttachmentsArray(amostras, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let estado = (anexos.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)), estado == .complete,
              let pixels = amostras.imageBuffer
        else { return }
        var imagem: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &imagem)
        if let imagem { aoFrame(imagem) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        // A janela fechada só tira os slides; o som continua.
        let daJanela = trinco.withLock { () -> Bool in
            guard stream === streamJanela else { return false }
            streamJanela = nil
            return true
        }
        if daJanela { aoPararJanela?(error) } else { aoParar(error) }
    }
}

/// Converte o áudio captado para 16 kHz mono (o formato do Whisper), escreve-o num ficheiro temporário
/// e mede o nível, para o medidor e para parar sozinho depois de um silêncio longo.
/// É chamado na fila da captura; o estado está protegido por um lock.
final class GravadorTemporario: @unchecked Sendable {
    let url: URL
    private let ficheiro: AVAudioFile
    private let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioExtractor.taxa, channels: 1, interleaved: false)!
    private let trinco = NSLock()
    private var conversor: AVAudioConverter?
    private var origem: AVAudioFormat?
    private var amostras: Int64 = 0
    private var pausado = false
    private var nivelAtual: Float = -120
    /// Amostra em que se ouviu som pela última vez (nil = ainda não houve som).
    private var ultimoSom: Int64?

    /// Abaixo disto conta como silêncio (dBFS).
    static let limiarSom: Float = -45

    var nivel: Float { trinco.withLock { nivelAtual } }
    var houveSom: Bool { trinco.withLock { ultimoSom != nil } }
    var segundosEmSilencio: Double {
        trinco.withLock { Double(amostras - (ultimoSom ?? amostras)) } / AudioExtractor.taxa
    }

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "Recap-direto-\(UUID().uuidString).caf")
        ficheiro = try AVAudioFile(forWriting: url, settings: formato.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var segundos: Double { trinco.withLock { Double(amostras) } / AudioExtractor.taxa }

    func definirPausa(_ valor: Bool) { trinco.withLock { pausado = valor } }

    /// Segundos já captados, ou nil em pausa (para alinhar as capturas de slides com o áudio).
    var segundosSeAtivo: Double? { trinco.withLock { pausado ? nil : Double(amostras) / AudioExtractor.taxa } }

    /// Escreve o áudio e devolve o nível RMS em dBFS, ou nil se estiver em pausa.
    func escrever(_ entrada: AVAudioPCMBuffer) -> Float? {
        trinco.withLock { () -> Float? in
            guard !pausado else { return nil }
            if origem != entrada.format {
                origem = entrada.format
                conversor = AVAudioConverter(from: entrada.format, to: formato)
            }
            guard let conversor else { return nil }
            let capacidade = AVAudioFrameCount(Double(entrada.frameLength) * formato.sampleRate / entrada.format.sampleRate) + 32
            guard let saida = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: capacidade) else { return nil }
            var entregue = false
            var erro: NSError?
            conversor.convert(to: saida, error: &erro) { _, estadoEntrada in
                if entregue { estadoEntrada.pointee = .noDataNow; return nil }
                entregue = true
                estadoEntrada.pointee = .haveData
                return entrada
            }
            guard erro == nil, saida.frameLength > 0 else { return nil }
            try? ficheiro.write(from: saida)
            amostras += Int64(saida.frameLength)
            nivelAtual = Self.nivel(saida)
            if nivelAtual > Self.limiarSom { ultimoSom = amostras }
            return nivelAtual
        }
    }

    static func nivel(_ b: AVAudioPCMBuffer) -> Float {
        guard let dados = b.floatChannelData?[0], b.frameLength > 0 else { return -120 }
        var soma: Float = 0
        for i in 0..<Int(b.frameLength) { soma += dados[i] * dados[i] }
        let rms = (soma / Float(b.frameLength)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -120
    }

    func apagar() { try? FileManager.default.removeItem(at: url) }
}

/// Guarda as imagens da janela da aula numa pasta temporária, com o tempo de áudio correspondente.
/// O ScreenCaptureKit só envia imagens quando a janela muda; por isso fica-se com a última e grava-se
/// uma a cada `intervalo` segundos de áudio, também enquanto o slide está parado (o SlideExtractor
/// precisa de várias imagens iguais seguidas para reconhecer um slide).
/// No fim, o SlideExtractor escolhe os slides e a pasta é apagada.
final class GravadorFrames: @unchecked Sendable {
    let pasta: URL
    static let intervalo: Double = 2
    private let trinco = NSLock()
    private let escrita = DispatchQueue(label: "pt.danielrodrigues.Recap.frames", qos: .utility)
    private var ultima: CGImage?
    private var ultimoTempo = -Double.infinity
    private var gravadas = 0
    /// A última imagem gravada e o ficheiro: se não mudou, a captura seguinte é uma ligação a esse ficheiro.
    private var ultimaGravada: (CGImage, URL)?

    init() throws {
        pasta = FileManager.default.temporaryDirectory.appending(path: "Recap-slides-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    }

    /// A última imagem da janela (para a pré-visualização na janela "Em direto").
    var ultimaImagem: CGImage? { trinco.withLock { ultima } }

    /// Já chegou alguma imagem da janela (uma janela minimizada não envia nenhuma).
    var temImagem: Bool { trinco.withLock { ultima != nil } }

    /// Imagens gravadas até agora.
    var quantidade: Int { trinco.withLock { gravadas } }

    /// Nova imagem da janela (chega só quando a janela muda).
    func receber(_ imagem: CGImage) { trinco.withLock { ultima = imagem } }

    /// Chamado com frequência (relógio da sessão): grava a última imagem se já passou o intervalo.
    func gravarSeDevido(segundos: Double) {
        let url = pasta.appending(path: FontePasta.nome(segundos))
        let pedido = trinco.withLock { () -> (CGImage, URL?)? in
            guard let ultima, segundos - ultimoTempo >= Self.intervalo else { return nil }
            ultimoTempo = segundos
            gravadas += 1
            let anterior = ultimaGravada.flatMap { $0.0 === ultima ? $0.1 : nil }
            ultimaGravada = (ultima, anterior ?? url)
            return (ultima, anterior)
        }
        guard let (imagem, anterior) = pedido else { return }
        escrita.async {
            if let anterior, (try? FileManager.default.linkItem(at: anterior, to: url)) != nil { return }
            try? SlideExtractor.gravarJPEG(imagem, em: url, qualidade: 0.6)
        }
    }

    /// Espera que as imagens em escrita terminem (antes de o SlideExtractor ler a pasta).
    func concluir() { escrita.sync {} }

    func apagar() { escrita.sync {}; try? FileManager.default.removeItem(at: pasta) }
}
