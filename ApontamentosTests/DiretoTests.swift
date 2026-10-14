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
}
