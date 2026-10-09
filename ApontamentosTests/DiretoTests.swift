import AVFoundation
import Testing
@testable import Apontamentos

struct DiretoTests {
    private func buffer(segundos: Double, amplitude: Float, taxa: Double = 48_000) -> AVAudioPCMBuffer {
        let formato = AVAudioFormat(standardFormatWithSampleRate: taxa, channels: 1)!
        let n = AVAudioFrameCount(segundos * taxa)
        let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n)!
        b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = amplitude * sin(Float(i) * 2 * .pi * 440 / Float(taxa)) }
        return b
    }

    @Test func gravadorConverteEMedeSilencio() throws {
        let g = try GravadorTemporario()
        defer { g.apagar() }
        #expect(!g.houveSom)
        for _ in 0..<10 { _ = g.escrever(buffer(segundos: 0.1, amplitude: 0.3)) } // 1 s de som
        #expect(g.houveSom)
        #expect(abs(g.segundos - 1) < 0.05)
        #expect(g.nivel > GravadorTemporario.limiarSom)
        for _ in 0..<20 { _ = g.escrever(buffer(segundos: 0.1, amplitude: 0)) } // 2 s de silêncio
        #expect(abs(g.segundosEmSilencio - 2) < 0.1)
        g.definirPausa(true)
        #expect(g.escrever(buffer(segundos: 0.1, amplitude: 0.3)) == nil)
        #expect(abs(g.segundos - 3) < 0.1)

        // O ficheiro fica a 16 kHz mono, pronto para o Whisper.
        let ficheiro = try AVAudioFile(forReading: g.url)
        #expect(ficheiro.fileFormat.sampleRate == 16_000)
        #expect(ficheiro.fileFormat.channelCount == 1)
    }

    @Test func timestampsCorrigidosPelaVelocidade() {
        let s = [Segmento(inicio: 10, fim: 20, texto: "a")]
        #expect(PipelineRunner.ajustarVelocidade(s, 1.5) == [Segmento(inicio: 15, fim: 30, texto: "a")])
        #expect(PipelineRunner.ajustarVelocidade(s, 1) == s)
    }

    /// O ScreenCaptureKit só envia imagens quando a janela muda: um slide parado tem de dar várias capturas.
    @Test func slideParadoGravaUmaImagemACada2s() async throws {
        let f = try GravadorFrames()
        defer { f.apagar() }
        let contexto = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        f.gravarSeDevido(segundos: 0) // ainda sem imagem
        f.receber(contexto.makeImage()!)
        for s in stride(from: 0.5, through: 9, by: 0.5) { f.gravarSeDevido(segundos: s) }
        f.concluir()
        #expect(f.quantidade == 5)
        let tempos = try await FontePasta(pasta: f.pasta).tempos(intervalo: 0)
        #expect(tempos == [0.5, 2.5, 4.5, 6.5, 8.5])
    }

    /// Página à volta com o vídeo preto no meio (Chrome escondido) vs. um slide normal.
    @Test func detetaVideoPretoNoCentro() {
        func imagem(_ centro: CGFloat) -> CGImage {
            let ctx = CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
            ctx.setFillColor(gray: centro, alpha: 1); ctx.fill(CGRect(x: 30, y: 15, width: 100, height: 70))
            return ctx.makeImage()!
        }
        #expect(CapturaAudio.centroPreto(imagem(0)))
        #expect(!CapturaAudio.centroPreto(imagem(0.9)))
    }

    /// Só a zona do leitor muda; a barra do browser e as margens ficam iguais e são recortadas.
    @Test func zonaAtivaEncontraOLeitor() {
        let (c, l) = (SlideExtractor.colunasFinas, SlideExtractor.linhasFinas)
        let grelhas = (0..<5).map { n in
            (0..<(c * l)).map { i -> Float in
                let x = i % c, y = i / c
                return (24..<72).contains(x) && (15..<40).contains(y) ? Float((x * 7 + y * 3 + n * 11) % 10) / 10 : 1
            }
        }
        let zona = try! #require(SlideExtractor.zonaAtiva(grelhas))
        #expect(abs(zona.minX - 23.0 / Double(c)) < 0.001)
        #expect(abs(zona.minY - 14.0 / Double(l)) < 0.001)
        #expect(abs(zona.maxX - 73.0 / Double(c)) < 0.001)
        #expect(abs(zona.maxY - 41.0 / Double(l)) < 0.001)
        // Nada muda: sem recorte.
        #expect(SlideExtractor.zonaAtiva(Array(repeating: grelhas[0], count: 5)) == nil)
    }
}
