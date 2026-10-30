import CoreGraphics
import Foundation
import Testing
@testable import Apontamentos

/// Mudar a janela da aula a meio de uma captação em direto (#39): o som e o tempo continuam, e os slides de
/// cada janela são extraídos à parte (a zona do slide é outra noutra janela).
@MainActor
struct MudarJanelaTests {
    /// Uma captação a fingir: regista as janelas pedidas e pode recusar mudar.
    private final class CaptacaoFalsa: Captacao, @unchecked Sendable {
        var iniciadas: [FonteAudio] = []
        var mudancas: [FonteAudio] = []
        var recusar = false
        func iniciar(_ fonte: FonteAudio) async throws { iniciadas.append(fonte) }
        func mudar(para fonte: FonteAudio) async throws -> CGImage? {
            if recusar { throw ErroCaptura.janelaNaoEncontrada }
            mudancas.append(fonte)
            return nil
        }
        func parar() async {}
    }

    private func fonte(_ janela: CGWindowID, _ app: String = "com.google.Chrome") -> FonteAudio {
        FonteAudio(bundleID: app, nome: "Chrome", janela: janela, tituloJanela: "Aula \(janela)", pid: 1)
    }

    private func imagem(_ cinzento: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: cinzento, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        return ctx.makeImage()!
    }

    private func sessao(_ falsa: CaptacaoFalsa) throws -> (SessaoDireto, Library, ProcessingQueue, URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "direto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "direto-\(UUID().uuidString)")!)
        let library = Library(raiz: raiz)
        let fichas = Fichas(library: library, definicoes: definicoes)
        let estudo = Estudo(library: library, definicoes: definicoes)
        let fila = ProcessingQueue(runner: PipelineRunner(library: library, definicoes: definicoes, fichas: fichas, estudo: estudo))
        return (SessaoDireto(criarCaptacao: { _ in falsa }), library, fila, raiz)
    }

    @Test func mudarDeJanelaComecaOutroTrocoDeImagens() async throws {
        let f = try GravadorFrames()
        defer { f.apagar() }
        f.receber(imagem(0.2))
        for s in [0.0, 2, 4] { f.gravarSeDevido(segundos: s) }
        f.novoTroco()
        #expect(!f.temImagem)
        f.gravarSeDevido(segundos: 6) // ainda nada da janela nova: a imagem da antiga não entra no troço novo
        f.receber(imagem(0.8))
        for s in [8.0, 10] { f.gravarSeDevido(segundos: s) }
        f.concluir()

        let trocos = FontePasta.trocos(f.pasta)
        #expect(trocos.count == 2)
        #expect(try await FontePasta(pasta: trocos[0]).tempos(intervalo: 0) == [0, 2, 4])
        #expect(try await FontePasta(pasta: trocos[1]).tempos(intervalo: 0) == [8, 10])
        #expect(f.quantidade == 5)
    }

    @Test func semMudarHaUmSoTroco() throws {
        let f = try GravadorFrames()
        defer { f.apagar() }
        #expect(FontePasta.trocos(f.pasta) == [f.pasta])
    }

    /// Os slides de cada janela, extraídos à parte, ficam numa só lista por ordem e com nomes seguidos.
    @Test func osSlidesDosTrocosJuntamSe() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "trocos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        func parte(_ nome: String, _ slides: [(String, Double)]) throws -> URL {
            let pasta = raiz.appending(path: nome)
            let imagens = pasta.appending(path: Disco.pastaSlides)
            try FileManager.default.createDirectory(at: imagens, withIntermediateDirectories: true)
            for (ficheiro, _) in slides { try Data(ficheiro.utf8).write(to: imagens.appending(path: ficheiro)) }
            try Disco.escreverSlides(slides.map { Slide(ficheiro: $0.0, inicio: $0.1, fim: $0.1 + 10, reaparicoes: []) }, em: pasta)
            return pasta
        }
        let a = try parte("a", [("slide_01_00-04.jpg", 4), ("slide_02_01-00.jpg", 60)])
        let b = try parte("b", [("slide_01_10-00.jpg", 600)])
        let aula = raiz.appending(path: "aula")
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)

        let slides = try SlidesDireto.juntar([a, b], em: aula)

        #expect(slides.map(\.ficheiro) == ["slide_01_00-04.jpg", "slide_02_01-00.jpg", "slide_03_10-00.jpg"])
        #expect(slides.map(\.inicio) == [4, 60, 600])
        #expect(Disco.lerSlides(aula) == slides)
        #expect(try Data(contentsOf: Disco.urlSlide(slides[2], em: aula)) == Data("slide_01_10-00.jpg".utf8))
    }

    @Test func mudarDeJanelaContinuaAMesmaAula() async throws {
        let falsa = CaptacaoFalsa()
        let (s, library, fila, raiz) = try sessao(falsa)
        defer { try? FileManager.default.removeItem(at: raiz) }
        await s.comecar(fonte: fonte(1), cadeira: "Gestão", titulo: "Aula 1", data: .now, velocidade: 1,
                        gerarApontamentos: false, capturarSlides: true, library: library, fila: fila)
        #expect(s.estado == .aOuvir)

        await s.mudarJanela(fonte(2, "us.zoom.xos"))

        #expect(falsa.mudancas.map(\.janela) == [2])
        #expect(s.fonte?.janela == 2)
        #expect(s.estado == .aOuvir)
        #expect(s.aviso == nil)
        #expect(library.cadeira(nome: "Gestão")?.aulas.count == 1)
        await s.descartar()
    }

    @Test func seNaoConsegueMudarFicaNaJanelaAnterior() async throws {
        let falsa = CaptacaoFalsa()
        falsa.recusar = true
        let (s, library, fila, raiz) = try sessao(falsa)
        defer { try? FileManager.default.removeItem(at: raiz) }
        await s.comecar(fonte: fonte(1), cadeira: "Gestão", titulo: "Aula 1", data: .now, velocidade: 1,
                        gerarApontamentos: false, capturarSlides: true, library: library, fila: fila)

        await s.mudarJanela(fonte(2))

        #expect(s.fonte?.janela == 1)
        #expect(s.estado == .aOuvir)
        #expect(s.aviso?.contains("Não consegui mudar") == true)
        await s.descartar()
    }
}
