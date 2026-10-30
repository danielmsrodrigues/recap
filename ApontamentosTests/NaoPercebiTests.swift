import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import Apontamentos

/// "Não estou a perceber": durante a captação, o momento fica na aula; os apontamentos explicam-no melhor.
@MainActor
struct NaoPercebiTests {
    private final class CaptacaoFalsa: Captacao, @unchecked Sendable {
        var eventos: EventosCaptacao?
        func iniciar(_ fonte: FonteAudio) async throws {}
        func mudar(para fonte: FonteAudio) async throws -> Bool { true }
        func parar() async {}
    }

    private func sessao(_ falsa: CaptacaoFalsa) throws -> (SessaoDireto, Library, ProcessingQueue, URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "naopercebi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "naopercebi-\(UUID().uuidString)")!)
        let library = Library(raiz: raiz)
        let fichas = Fichas(library: library, definicoes: definicoes)
        let estudo = Estudo(library: library, definicoes: definicoes)
        let fila = ProcessingQueue(runner: PipelineRunner(library: library, definicoes: definicoes, fichas: fichas, estudo: estudo))
        return (SessaoDireto(criarCaptacao: { eventos in falsa.eventos = eventos; return falsa }), library, fila, raiz)
    }

    /// `segundos` de som (um tom baixo).
    private func som(_ segundos: Int) -> AVAudioPCMBuffer {
        let formato = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let n = AVAudioFrameCount(48_000 * segundos)
        let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n)!
        b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = 0.3 * sin(Float(i) * 0.06) }
        return b
    }

    private let fonte = FonteAudio(bundleID: "com.google.Chrome", nome: "Chrome", janela: 1, tituloJanela: "Aula", pid: 1)

    @Test func oBocadoVaiDeNaoEstouAPerceberAteJaPercebiATempoDeAula() async throws {
        let falsa = CaptacaoFalsa()
        let (s, library, fila, raiz) = try sessao(falsa)
        defer { try? FileManager.default.removeItem(at: raiz) }
        // A gravação toca a 1,5×: 2 s captados são 3 s de aula.
        await s.comecar(fonte: fonte, cadeira: "Gestão", titulo: "Aula 1", data: .now, velocidade: 1.5,
                        gerarApontamentos: false, capturarSlides: false, library: library, fila: fila)
        falsa.eventos?.aoReceber(som(2))
        s.alternarNaoPercebi()
        #expect(s.aNaoPerceber)
        falsa.eventos?.aoReceber(som(2))
        s.alternarNaoPercebi()
        #expect(!s.aNaoPerceber)

        #expect(s.naoPercebi == [IntervaloNaoPercebi(inicio: 3, fim: 6)])
        let pasta = try #require(library.cadeira(nome: "Gestão")?.aulas.first?.pasta)
        // Logo no disco, antes de a captação acabar.
        #expect(try Disco.lerMeta(pasta).naoPercebi == [IntervaloNaoPercebi(inicio: 3, fim: 6)])
        await s.descartar()
    }

    @Test func umBocadoAbertoFechaNoFimDaCaptacao() async throws {
        let falsa = CaptacaoFalsa()
        let (s, library, fila, raiz) = try sessao(falsa)
        defer { try? FileManager.default.removeItem(at: raiz) }
        await s.comecar(fonte: fonte, cadeira: "Gestão", titulo: "Aula 1", data: .now, velocidade: 1,
                        gerarApontamentos: false, capturarSlides: false, library: library, fila: fila)
        falsa.eventos?.aoReceber(som(1))
        s.alternarNaoPercebi()
        falsa.eventos?.aoReceber(som(3))
        s.fecharNaoPercebi()
        #expect(s.naoPercebi == [IntervaloNaoPercebi(inicio: 1, fim: 4)])
        await s.descartar()
    }

    @Test func semCaptacaoNaoMarcaNada() {
        let s = SessaoDireto(criarCaptacao: { _ in CaptacaoFalsa() })
        s.alternarNaoPercebi()
        #expect(s.naoPercebi.isEmpty)
    }

    @Test func aulaAntigaSemMarcasAbre() throws {
        let json = #"{"titulo":"X","data":"2026-10-08T10:00:00Z"}"#
        #expect(try Disco.decoder.decode(AulaMeta.self, from: Data(json.utf8)).naoPercebi == nil)
    }

    private func contexto(naoPercebi: [IntervaloNaoPercebi]) -> ContextoAula {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 4000, criadaEm: .now,
                            segmentos: [Segmento(inicio: 10, fim: 20, texto: "Hola.", orador: .professor),
                                        Segmento(inicio: 125, fim: 130, texto: "Los límites…", orador: .professor)])
        var c = ContextoAula(cadeira: "Cálculo", titulo: "Aula 1", data: .now, glossario: "", transcricao: t)
        c.naoPercebi = naoPercebi
        return c
    }

    private func texto(_ blocos: [BlocoConteudo]) -> String {
        blocos.compactMap { if case .texto(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }

    @Test func osApontamentosPedemUmaExplicacaoDosBocadosMarcados() {
        let pedido = texto(NotesGenerator.conteudo(contexto(naoPercebi: [IntervaloNaoPercebi(inicio: 125, fim: 725),
                                                                          IntervaloNaoPercebi(inicio: 3725, fim: 3800)])))
        #expect(pedido.contains("de [02:05] a [12:05]"))
        // Depois da primeira hora, os minutos continuam a contar, como na transcrição.
        #expect(pedido.contains("[62:05]"))
        #expect(pedido.contains("🤔"))
    }

    @Test func semMarcasOPedidoNaoFalaDisso() {
        #expect(!texto(NotesGenerator.conteudo(contexto(naoPercebi: []))).contains("🤔"))
    }
}
