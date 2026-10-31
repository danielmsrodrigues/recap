import AVFoundation
import Testing
@testable import Apontamentos

/// A captação em direto: o áudio a 16 bits (metade do espaço), as capturas iguais da janela ligadas ao mesmo ficheiro,
/// e uma captação por processar (a app fechou-se) volta à fila ao abrir.
struct CaptacaoGuardadaTests {
    private func pasta() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "captacao-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func som(segundos: Double) -> AVAudioPCMBuffer {
        let formato = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let n = AVAudioFrameCount(segundos * 48_000)
        let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n)!
        b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = 0.3 * sin(Float(i) * 2 * .pi * 440 / 48_000) }
        return b
    }

    @Test func oAudioFicaA16BitsELeSeIgual() async throws {
        let g = try GravadorTemporario()
        defer { g.apagar() }
        for _ in 0..<20 { _ = g.escrever(som(segundos: 0.1)) } // 2 s
        g.fechar()
        let ficheiro = try AVAudioFile(forReading: g.url)
        #expect(ficheiro.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(ficheiro.fileFormat.settings[AVLinearPCMIsFloatKey] as? Bool == false)
        let tamanho = try #require(try g.url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(tamanho < 2 * 16_000 * 2 + 8_192) // 2 bytes por amostra (eram 4)
        let lido = try await AudioExtractor().extrair(de: g.url)
        #expect(abs(Double(lido.amostras.count) / AudioExtractor.taxa - 2) < 0.05)
        #expect((lido.amostras.map { abs($0) }.max() ?? 0) > 0.25)
    }

    /// A app fechou-se a meio da captação: o ficheiro nunca foi fechado, mas o áudio que lá está lê-se na mesma.
    @Test func oAudioDeUmaCaptacaoInterrompidaLeSe() async throws {
        let pasta = try pasta()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let url = pasta.appending(path: "audio.caf")
        let g = try GravadorTemporario(url: url)
        for _ in 0..<15 { _ = g.escrever(som(segundos: 0.1)) } // 1,5 s, sem fechar
        let lido = try await AudioExtractor().extrair(de: url)
        #expect(abs(Double(lido.amostras.count) / AudioExtractor.taxa - 1.5) < 0.1)
        _ = g
    }

    /// Duas imagens iguais (objetos diferentes, como chegam do ScreenCaptureKit quando algo mexe sem mudar o slide):
    /// a segunda é uma ligação ao mesmo ficheiro e não uma cópia.
    @Test func capturasIguaisNaoOcupamEspacoDuasVezes() throws {
        let f = try GravadorFrames()
        defer { f.apagar() }
        func imagem(_ cinza: CGFloat) -> CGImage {
            let ctx = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(gray: cinza, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 40, y: 40, width: 120, height: 20))
            return ctx.makeImage()!
        }
        f.receber(imagem(1)); f.gravarSeDevido(segundos: 0)
        f.receber(imagem(1)); f.gravarSeDevido(segundos: 2)
        f.receber(imagem(0.4)); f.gravarSeDevido(segundos: 4)
        f.concluir()
        let ficheiros = try FileManager.default.contentsOfDirectory(at: f.pasta, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(ficheiros.count == 3)
        let inodes = try ficheiros.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.systemFileNumber] as? Int }
        #expect(inodes[0] == inodes[1])
        #expect(inodes[1] != inodes[2])
    }

    @Test func umaCaptacaoPorProcessarVoltaAFila() throws {
        let raiz = try pasta(), aula = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: aula) }
        let c = try CaptacaoGuardada.criar(em: raiz)
        try Data("som".utf8).write(to: c.audio)
        try FileManager.default.createDirectory(at: c.frames, withIntermediateDirectories: true)
        try c.guardar(.init(pastaAula: aula, titulo: "Aula 3", velocidade: 1.5, gerarApontamentos: true))

        let pendentes = CaptacaoGuardada.pendentes(em: raiz) { _ in true }
        #expect(pendentes.count == 1)
        #expect(pendentes.first?.ficha.titulo == "Aula 3")
        #expect(pendentes.first?.ficha.velocidade == 1.5)
        #expect(pendentes.first?.captacao.pasta.lastPathComponent == c.pasta.lastPathComponent)
    }

    /// Sem áudio (já transcrito) ou com a aula apagada, não há nada a recuperar: a pasta vai-se.
    @Test func semAudioOuSemAulaAPastaEApagada() throws {
        let raiz = try pasta(), aula = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: aula) }
        let jaTranscrita = try CaptacaoGuardada.criar(em: raiz)
        try jaTranscrita.guardar(.init(pastaAula: aula, titulo: "A", velocidade: 1, gerarApontamentos: true))
        let semAula = try CaptacaoGuardada.criar(em: raiz)
        try Data("som".utf8).write(to: semAula.audio)
        try semAula.guardar(.init(pastaAula: aula.appending(path: "apagada"), titulo: "B", velocidade: 1, gerarApontamentos: true))

        #expect(CaptacaoGuardada.pendentes(em: raiz) { FileManager.default.fileExists(atPath: $0.path) }.isEmpty)
        #expect((try FileManager.default.contentsOfDirectory(atPath: raiz.path)).isEmpty)
    }
}
