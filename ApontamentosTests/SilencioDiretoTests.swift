import AVFoundation
import Foundation
import Testing
@testable import Apontamentos

/// O tempo de silêncio ao fim do qual uma aula em direto termina sozinha, escolhido nas Definições.
@MainActor
struct SilencioDiretoTests {
    private final class CaptacaoFalsa: Captacao, @unchecked Sendable {
        var eventos: EventosCaptacao?
        func iniciar(_ fonte: FonteAudio) async throws {}
        func mudar(para fonte: FonteAudio) async throws -> Bool { true }
        func parar() async {}
    }

    /// O limite, em segundos, para os testes o poderem mudar a meio.
    private final class Limite {
        var segundos: Double
        init(_ segundos: Double) { self.segundos = segundos }
    }

    private let fonte = FonteAudio(bundleID: "com.google.Chrome", nome: "Chrome", janela: 1, tituloJanela: "Aula", pid: 1)

    private func definicoes() throws -> Definicoes {
        Definicoes(defaults: try #require(UserDefaults(suiteName: "silencio-\(UUID().uuidString)")))
    }

    private func buffer(segundos: Int, amplitude: Float) -> AVAudioPCMBuffer {
        let formato = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let n = AVAudioFrameCount(48_000 * segundos)
        let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n)!
        b.frameLength = n
        for i in 0..<Int(n) { b.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.06) }
        return b
    }

    /// Uma captação a ouvir, com 1 s de som seguido de 2 s de silêncio. Com menos de 5 s captados, terminar não põe
    /// nada na fila: acaba em `.falhou` ("não se ouviu nada"), sem carregar o Whisper.
    private func sessaoEmSilencio(_ limite: Limite) async throws -> (SessaoDireto, URL) {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "silencio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        let d = try definicoes()
        let library = Library(raiz: raiz)
        let fila = ProcessingQueue(runner: PipelineRunner(library: library, definicoes: d, fichas: Fichas(library: library, definicoes: d),
                                                          estudo: Estudo(library: library, definicoes: d)))
        let falsa = CaptacaoFalsa()
        let s = SessaoDireto(criarCaptacao: { eventos in falsa.eventos = eventos; return falsa }, limiteSilencio: { limite.segundos })
        await s.comecar(fonte: fonte, cadeira: "Gestão", titulo: "Aula 1", data: .now, velocidade: 1,
                        gerarApontamentos: false, capturarSlides: false, library: library, fila: fila)
        #expect(s.estado == .aOuvir)
        falsa.eventos?.aoReceber(buffer(segundos: 1, amplitude: 0.3))
        falsa.eventos?.aoReceber(buffer(segundos: 2, amplitude: 0))
        return (s, raiz)
    }

    private func esperarQueTermine(_ s: SessaoDireto) async throws {
        for _ in 0..<100 where s.ativa { try await Task.sleep(for: .milliseconds(100)) }
    }

    /// Até o relógio da sessão ter visto o silêncio: com os testes todos em paralelo, pode demorar mais do que o meio
    /// segundo de cada volta.
    private func esperarQueVejaOSilencio(_ s: SessaoDireto) async throws {
        for _ in 0..<100 where s.silencio < 1.9 { try await Task.sleep(for: .milliseconds(100)) }
    }

    // MARK: A sessão

    @Test func terminaAoFimDoTempoEscolhido() async throws {
        let (s, raiz) = try await sessaoEmSilencio(Limite(1))
        defer { try? FileManager.default.removeItem(at: raiz) }

        try await esperarQueTermine(s)

        #expect(!s.ativa)
    }

    @Test func comMaisTempoEscolhidoContinuaAOuvir() async throws {
        let (s, raiz) = try await sessaoEmSilencio(Limite(60))
        defer { try? FileManager.default.removeItem(at: raiz) }

        try await esperarQueVejaOSilencio(s)

        #expect(s.silencio >= 1.9)
        #expect(s.estado == .aOuvir)
        await s.descartar()
    }

    /// Numa aula com um intervalo mais longo do que se pensava, aumentar o tempo vale logo para a aula em curso.
    @Test func mudarONumaAulaEmCursoValeLogo() async throws {
        let limite = Limite(60)
        let (s, raiz) = try await sessaoEmSilencio(limite)
        defer { try? FileManager.default.removeItem(at: raiz) }
        try await esperarQueVejaOSilencio(s)
        #expect(s.estado == .aOuvir)

        limite.segundos = 1
        #expect(s.limiteSilencio == 1)
        try await esperarQueTermine(s)

        #expect(!s.ativa)
    }

    /// Sem nada dito, é o de sempre.
    @Test func porDefeitoSaoTresMinutos() {
        #expect(SessaoDireto().limiteSilencio == 180)
    }

    // MARK: A preferência

    @Test func aPreferenciaGuardaSeETemTresMinutosPorDefeito() throws {
        let defaults = try #require(UserDefaults(suiteName: "silencio-\(UUID().uuidString)"))
        let d = Definicoes(defaults: defaults)
        #expect(d.minutosSilencio == 3)
        #expect(d.limiteSilencio == 180)

        d.minutosSilencio = 30

        #expect(d.limiteSilencio == 1_800)
        #expect(Definicoes(defaults: defaults).minutosSilencio == 30)
    }

    /// Um valor que não está nas opções deixava o menu das Definições sem nada escolhido, e um zero ou negativo terminava logo.
    @Test(arguments: [0, -5, 7, 100_000]) func umValorForaDasOpcoesVoltaAoDefeito(valor: Int) throws {
        let defaults = try #require(UserDefaults(suiteName: "silencio-\(UUID().uuidString)"))
        defaults.set(valor, forKey: "minutosSilencio")
        #expect(Definicoes(defaults: defaults).minutosSilencio == 3)
    }

    @Test func oPorDefeitoEstaNasOpcoes() {
        #expect(Definicoes.opcoesMinutosSilencio.contains(Definicoes.minutosSilencioPorDefeito))
        #expect(Definicoes.opcoesMinutosSilencio.allSatisfy { $0 > 0 })
    }

    @Test func osNomesDosTempos() {
        #expect(Definicoes.nomeMinutos(1) == "1 minuto")
        #expect(Definicoes.nomeMinutos(3) == "3 minutos")
        #expect(Definicoes.nomeMinutos(60) == "1 hora")
    }
}
