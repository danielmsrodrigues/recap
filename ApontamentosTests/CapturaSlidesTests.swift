import AppKit
import Foundation
import Testing
import Vision
@testable import Apontamentos

/// Slides de uma aula captada em direto em que o professor partilha o ecrã todo (o PowerPoint em modo de edição):
/// o slide é só uma parte da janela, com o chat e a lista de participantes à volta.
struct CapturaSlidesTests {
    private let c = SlideExtractor.colunasFinas, l = SlideExtractor.linhasFinas

    /// Grelha fina com o "slide" (colunas 5–55, linhas 15–45) a mudar em `trocas` e o resto parado,
    /// salvo uma linha do chat (colunas 75–90) que muda em todas as capturas.
    private func grelhas(trocas: Set<Int>, total: Int = 12) -> [[Float]] {
        var conteudo: Float = 0.2
        return (0..<total).map { n in
            if trocas.contains(n) { conteudo = conteudo == 0.2 ? 0.8 : 0.2 }
            return (0..<(c * l)).map { i -> Float in
                let x = i % c, y = i / c
                if (5..<55).contains(x), (15..<45).contains(y) { return (x + y) % 3 == 0 ? conteudo : 1 }
                if (75..<90).contains(x), y == 10 + n % 30 { return Float(n % 2) }
                return 0.5
            }
        }
    }

    @Test func zonaDoSlideFicaNoSlideENaoNoChat() throws {
        let zona = try #require(SlideExtractor.zonaDoSlide(grelhas(trocas: [3, 6, 9])))
        // Contém o slide (colunas 5–55 de 96, linhas 15–45 de 54)…
        #expect(zona.minX <= 5.0 / Double(c) + 0.001)
        #expect(zona.maxX >= 55.0 / Double(c) - 0.001)
        #expect(zona.minY <= 15.0 / Double(l) + 0.001)
        #expect(zona.maxY >= 45.0 / Double(l) - 0.001)
        // …e não chega ao chat (coluna 75).
        #expect(zona.maxX < 75.0 / Double(c))
    }

    /// Um chat maior do que o slide, que desliza uma linha de vez em quando (o painel muda todo de uma vez).
    @Test func chatADeslizarNaoEZonaDoSlide() throws {
        var slide: Float = 0.2, deslocamento = 0
        let trocasSlide: Set<Int> = [3, 7, 11], deslizes: Set<Int> = [2, 5, 9, 13]
        let grelhas = (0..<16).map { n -> [Float] in
            if trocasSlide.contains(n) { slide = slide == 0.2 ? 0.8 : 0.2 }
            if deslizes.contains(n) { deslocamento += 2 }
            return (0..<(c * l)).map { i -> Float in
                let x = i % c, y = i / c
                if (12..<52).contains(x), (18..<40).contains(y) { return (x + y) % 3 == 0 ? slide : 1 }
                // Linhas de texto do chat (de 3 em 3 linhas da grelha), que sobem quando o chat desliza.
                if (60..<96).contains(x), (4..<54).contains(y) { return (y + deslocamento) % 3 == 0 && (x * 7 + (y + deslocamento) * 5) % 4 != 0 ? 0.1 : 0.95 }
                return 0.5
            }
        }
        let zona = try #require(SlideExtractor.zonaDoSlide(grelhas))
        #expect(zona.maxX < 60.0 / Double(c), "\(zona)")
        #expect(zona.minX <= 12.0 / Double(c) + 0.001)
    }

    @Test func deslocamentoVerticalReconhecido() {
        let caixa = SlideExtractor.Caixa(minX: 0, minY: 0, maxX: c, maxY: l)
        let a = (0..<(c * l)).map { i -> Float in (i / c) % 4 == 0 ? 0 : 1 }
        let subido = (0..<(c * l)).map { i -> Float in (i / c + 2) % 4 == 0 ? 0 : 1 }
        #expect(SlideExtractor.eDeslocamento(a, subido, caixa: caixa, colunas: c))
        let outro = (0..<(c * l)).map { i -> Float in (i % c + i / c) % 3 == 0 ? 0 : 1 }
        #expect(!SlideExtractor.eDeslocamento(a, outro, caixa: caixa, colunas: c))
    }

    @Test func revelarLinhasSoAcrescenta() {
        let fundo = [Float](repeating: 1, count: 100)
        var umaLinha = fundo; for i in 0..<10 { umaLinha[i] = 0 }
        var duasLinhas = umaLinha; for i in 20..<30 { duasLinhas[i] = 0 }
        var outro = fundo; for i in 5..<15 { outro[i] = 0 }
        #expect(SlideExtractor.soAcrescenta(umaLinha, duasLinhas))
        #expect(!SlideExtractor.soAcrescenta(duasLinhas, umaLinha))
        #expect(!SlideExtractor.soAcrescenta(umaLinha, outro))
    }

    @Test func semTrocasDeSlideNaoHaZona() {
        // Só o chat a mudar: nenhuma troca de slide.
        #expect(SlideExtractor.zonaDoSlide(grelhas(trocas: [])) == nil)
    }

    @Test func maiorBlocoJuntaLetrasProximas() {
        var marcadas = [Bool](repeating: false, count: 20 * 10)
        // Duas "letras" separadas por duas células vazias, e um ponto solto longe.
        for (x, y) in [(2, 2), (3, 2), (6, 2), (7, 3), (18, 9)] { marcadas[y * 20 + x] = true }
        #expect(SlideExtractor.maiorBloco(marcadas, colunas: 20, linhas: 10, dilatar: 2) == .init(minX: 2, minY: 2, maxX: 8, maxY: 4))
        #expect(SlideExtractor.maiorBloco(marcadas, colunas: 20, linhas: 10, dilatar: 0) == .init(minX: 2, minY: 2, maxX: 4, maxY: 3))
    }

    // MARK: De ponta a ponta, com imagens desenhadas

    private static let largura = 1280, altura = 720
    private static let rectSlide = CGRect(x: 60, y: 190, width: 640, height: 360)

    /// Uma captura da janela: friso em cima, o slide `n` (nil = a câmara de alguém), o chat à direita com `mensagens` linhas.
    private static func captura(slide n: Int?, mensagens: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: largura, height: altura, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        ctx.translateBy(x: 0, y: CGFloat(altura)); ctx.scaleBy(x: 1, y: -1)
        func texto(_ s: String, _ x: CGFloat, _ y: CGFloat, _ tamanho: CGFloat, cor: NSColor = .black) {
            NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: tamanho), .foregroundColor: cor]).draw(at: CGPoint(x: x, y: y))
        }
        NSColor(white: 0.88, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: largura, height: altura).fill()
        NSColor(white: 0.25, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: largura, height: 60).fill()
        texto("Inicio   Insertar   Diseño   Transiciones   Animaciones", 20, 20, 16, cor: .white)
        if let n {
            NSColor.white.setFill(); rectSlide.fill()
            let r = rectSlide
            texto("Tema \(n): \(["Empresa", "Valor", "Setores", "Tamanho", "Finalidade", "Impostos"][n - 1])", r.minX + 30, r.minY + 30, 34, cor: .systemOrange)
            for k in 0..<4 {
                texto("Ponto \(k + 1) do slide \(n), com texto diferente em cada um", r.minX + 40 + CGFloat(n * 6), r.minY + 110 + CGFloat(k * 50), 20)
            }
            texto("Atividade Empresarial", r.minX + 20, r.maxY - 30, 12)
        } else {
            // A câmara ocupa só o palco (menos de 60% da janela), como no Collaborate.
            NSColor(white: 0.15, alpha: 1).setFill(); CGRect(x: 0, y: 60, width: 800, height: 600).fill()
            NSColor(white: 0.6, alpha: 1).setFill(); NSBezierPath(ovalIn: CGRect(x: 340, y: 230, width: 200, height: 200)).fill()
        }
        // O chat e os participantes, que vão mudando.
        NSColor.white.setFill(); CGRect(x: 900, y: 60, width: 380, height: altura - 60).fill()
        for k in 0..<min(mensagens, 24) { texto("Aluno \(k): mensagem do chat número \(k)", 910, 80 + CGFloat(k * 26), 13) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    @Test(.timeLimit(.minutes(3))) func slidesDoEcraPartilhadoSaemRecortadosESemChat() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "captura-\(UUID().uuidString)")
        let capturas = base.appending(path: "capturas"), aula = base.appending(path: "aula")
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // 6 slides com 8 capturas cada, e a câmara (sem partilha) entre o 3.º e o 4.º.
        var t = 0.0, mensagens = 0
        let sequencia: [Int?] = [1, 2, 3].flatMap { Array(repeating: $0, count: 8) } + Array(repeating: nil, count: 6)
            + [4, 5, 6].flatMap { Array(repeating: $0, count: 8) }
        for n in sequencia {
            if Int(t) % 6 == 0 { mensagens += 1 }
            try SlideExtractor.gravarJPEG(Self.captura(slide: n, mensagens: mensagens), em: capturas.appending(path: FontePasta.nome(t)), qualidade: 0.6)
            t += 2
        }

        var config = ConfigSlides()
        config.recortarZonaAtiva = true
        let slides = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: capturas), para: aula) { _ in }
        #expect(slides.count == 6)
        for s in slides {
            let imagem = try #require(FontePasta.ler(Disco.urlSlide(s, em: aula), maxLado: 2000))
            var ocr = RecognizeTextRequest()
            ocr.recognitionLevel = .accurate
            let lido = try await ocr.perform(on: imagem).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            #expect(lido.contains("Tema"), "\(s.ficheiro): \(lido)")
            #expect(!lido.localizedCaseInsensitiveContains("chat"), "\(s.ficheiro): \(lido)")
            #expect(!lido.contains("Insertar"), "\(s.ficheiro): \(lido)")
            // Recortado à volta do slide (640×360 numa janela de 1280×720), não a janela inteira.
            #expect(imagem.width < Self.largura * 7 / 10)
        }
    }

    @Test func semZonaDeSlideNaoGuardaAJanela() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "captura-\(UUID().uuidString)")
        let capturas = base.appending(path: "capturas"), aula = base.appending(path: "aula")
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        // Sempre o mesmo slide: só o chat muda. Sem trocas não se sabe onde está o slide, e a janela inteira
        // (ou a zona que mexe, que é o chat) não serve.
        for k in 0..<10 {
            try SlideExtractor.gravarJPEG(Self.captura(slide: 1, mensagens: k * 2), em: capturas.appending(path: FontePasta.nome(Double(k * 2))), qualidade: 0.6)
        }
        var config = ConfigSlides()
        config.recortarZonaAtiva = true
        let slides = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: capturas), para: aula) { _ in }
        #expect(slides.isEmpty)
        #expect(Disco.lerSlides(aula) == [])
    }
}
