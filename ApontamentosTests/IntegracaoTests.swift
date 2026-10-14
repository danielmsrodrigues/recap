import AppKit
import AVFoundation
import Foundation
import PDFKit
import Vision
import Synchronization
import Testing
@testable import Apontamentos

/// Testes com o modelo real do Whisper. Só correm com `APONTAMENTOS_AUDIO=<ficheiro>`
/// (no xcodebuild: `TEST_RUNNER_APONTAMENTOS_AUDIO=...`). Descarregam o modelo se faltar.
struct IntegracaoTests {
    static let audio = ProcessInfo.processInfo.environment["APONTAMENTOS_AUDIO"]

    @Test(.enabled(if: audio != nil), .timeLimit(.minutes(30)))
    func extraiETranscreveAudioReal() async throws {
        let url = URL(fileURLWithPath: try #require(Self.audio))
        let inicio = Date.now
        let memoria = MedidorMemoria()
        let medicao = Task { while !Task.isCancelled { memoria.amostrar(); try? await Task.sleep(for: .milliseconds(200)) } }
        defer { medicao.cancel() }
        let duracao = try await AudioExtractor.duracao(url)
        #expect(duracao > 0)

        let store = ModelStore()
        if !store.estaDescarregado(.largeV3Turbo) {
            _ = try await store.descarregar(.largeV3Turbo) { _ in }
        }
        if let n = ProcessInfo.processInfo.environment["APONTAMENTOS_DESCODIFICADORES"].flatMap(Int.init) { Transcriber.descodificadores = n }
        let transcriber = Transcriber()
        try await transcriber.carregar(.largeV3Turbo, store: store)
        memoria.amostrar()
        let soModelo = memoria.picoMB
        let segmentos = try await transcriber.transcrever(
            ficheiro: url, duracao: duracao, glossario: "autovalor = valor próprio\ndescenso del gradiente"
        ) { _ in }

        let t = Transcricao(idioma: "es", modelo: "turbo", duracao: duracao, criadaEm: .now, segmentos: segmentos)
        memoria.amostrar()
        let relatorio = "TRANSCRICAO (\(Int(Date.now.timeIntervalSince(inicio))) s, modelo carregado \(soModelo) MB, pico de memória \(memoria.picoMB) MB, \(segmentos.count) segmentos)\n\(t.textoComTimestamps.prefix(600))"
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try relatorio.write(toFile: saida, atomically: true, encoding: .utf8)
        }
        #expect(!segmentos.isEmpty)
        #expect(segmentos.last!.fim <= duracao + 1)
        #expect(zip(segmentos, segmentos.dropFirst()).allSatisfy { $0.inicio <= $1.inicio })
    }
}

/// Gera texto a sério com o `claude -p` (gasta um pouco da subscrição). Só com `APONTAMENTOS_CLAUDE=1`.
struct IntegracaoClaudeCodeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_CLAUDE"] == "1"), .timeLimit(.minutes(5)))
    func geraComClaudeCode() async throws {
        let url = try #require(ClaudeCodeClient.localizar())
        var recebido = ""
        let r = try await ClaudeCodeClient(executavel: url).gerar(
            sistema: "Responde em português europeu, numa frase, sem formatação.",
            conteudo: [.texto("Transcrição: [00:00] La matriz identidad tiene unos en la diagonal."), .texto("Resume a transcrição.")],
            modelo: "claude-sonnet-5-5", esforco: .low,
            aoRecomecar: { recebido = "" }, aoReceber: { recebido += $0 })
        #expect(!r.resposta.texto.isEmpty)
        #expect(recebido == r.resposta.texto)
        #expect(r.resposta.uso.contagem.output > 0)
        #expect(r.resposta.texto.localizedCaseInsensitiveContains("diagonal"))
    }
}

/// Extração de slides num vídeo real. Só com `APONTAMENTOS_VIDEO=<ficheiro>`; o relatório vai para `APONTAMENTOS_SAIDA`.
struct IntegracaoSlidesTests {
    static let video = ProcessInfo.processInfo.environment["APONTAMENTOS_VIDEO"]

    @Test(.enabled(if: video != nil), .timeLimit(.minutes(20)))
    func extraiSlides() async throws {
        let url = URL(fileURLWithPath: try #require(Self.video))
        let pasta = FileManager.default.temporaryDirectory.appending(path: "slides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)

        // Distâncias entre frames consecutivos, com a zona da câmara tapada, para calibrar o limiar.
        let asset = AVURLAsset(url: url)
        let duracao = try await asset.load(.duration).seconds
        let gerador = AVAssetImageGenerator(asset: asset)
        gerador.maximumSize = CGSize(width: 640, height: 640)
        let tempos = stride(from: 0.0, to: duracao, by: 2).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var imagens: [(Double, CGImage)] = []
        for await r in gerador.images(for: tempos) {
            if case .success(let t, let img, _) = r { imagens.append((t.seconds, img)) }
        }
        let mascara = SlideExtractor.zonaEmMovimento(imagens.map { SlideExtractor.grelha($0.1) })
        var relatorio = "mascara: \(mascara.count) células\n"
        var anterior: FeaturePrintObservation?
        for (t, img) in imagens {
            let fp = try await GenerateImageFeaturePrintRequest().perform(on: SlideExtractor.tapar(img, mascara))
            if let anterior { relatorio += String(format: "%6.1f  %.3f\n", t, try fp.distance(to: anterior)) }
            anterior = fp
        }

        let slides = try await SlideExtractor().extrair(de: url, para: pasta) { _ in }
        relatorio += "\nslides: \(slides.count)\n" + slides.map {
            "\(Timestamp.format($0.inicio))–\(Timestamp.format($0.fim)) \($0.ficheiro) reaparições: \($0.reaparicoes)"
        }.joined(separator: "\n") + "\npasta: \(pasta.path)\n"
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try relatorio.write(toFile: saida, atomically: true, encoding: .utf8)
        }
        #expect(!slides.isEmpty)

        // O mesmo vídeo como capturas de uma aula em direto vista a 1,5×: mesmos slides, tempos × 1,5.
        let capturas = FileManager.default.temporaryDirectory.appending(path: "capturas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: capturas, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: capturas) }
        try await FonteVideo(url: url).percorrer(intervalo: 2, maxLado: 1280) { t, imagem in
            try SlideExtractor.gravarJPEG(imagem, em: capturas.appending(path: FontePasta.nome(t)))
        }
        let pasta2 = FileManager.default.temporaryDirectory.appending(path: "slides2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta2, withIntermediateDirectories: true)
        var config = ConfigSlides()
        config.escalaTempo = 1.5
        let doDireto = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: capturas), para: pasta2) { _ in }
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try (relatorio + "\ndireto: " + doDireto.map { "\(Timestamp.format($0.inicio)) \($0.reaparicoes)" }.joined(separator: ", "))
                .write(toFile: saida, atomically: true, encoding: .utf8)
        }
        #expect(doDireto.count == slides.count)
        #expect(zip(doDireto, slides).allSatisfy { abs($0.inicio - $1.inicio * 1.5) < 0.01 })
    }
}

@MainActor
struct ExportadorPDFTests {
    @Test func pdfLevaAsImagensDosSlides() async throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "aula-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta.appending(path: "slides-pdf"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        // Ruído: uma imagem que não comprime, para se notar no tamanho do PDF.
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 450, bitsPerSample: 8,
                                                samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try #require(rep.bitmapData)
        for i in 0..<(rep.bytesPerRow * 450) { bytes[i] = .random(in: 0...255) }
        try #require(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])).write(to: pasta.appending(path: "slides-pdf/pagina-01.jpg"))
        let md = "# Título\n\nAntes.\n\n![Slide 1 — Teste](slides-pdf/pagina-01.jpg)\n\nDepois."
        let com = pasta.appending(path: "com.pdf"), sem = pasta.appending(path: "sem.pdf")
        try await ExportadorPDF.exportar(markdown: md, pastaAula: pasta, para: com)
        try await ExportadorPDF.exportar(markdown: md, pastaAula: nil, para: sem)
        let tamanho = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        #expect(tamanho(com) > tamanho(sem) + 50_000)
        #expect(PDFDocument(url: com)?.string?.contains("Slide 1 — Teste") == true)
    }

    @Test func geraPDFPaginadoComFormulas() async throws {
        let md = "# Título\n\n## Secção [01:05]\n\n" + String(repeating: "Texto com $A v = \\lambda v$ e mais palavras para encher a página. ", count: 200)
            + "\n\n$$\n\\det(A - \\lambda I) = 0\n$$\n"
        let destino = FileManager.default.temporaryDirectory.appending(path: "teste-\(UUID().uuidString).pdf")
        try await ExportadorPDF.exportar(markdown: md, para: destino)
        let pdf = try #require(PDFDocument(url: destino))
        #expect(pdf.pageCount >= 2)
        #expect(abs((pdf.page(at: 0)?.bounds(for: .mediaBox).width ?? 0) - 595.28) < 1) // A4
        #expect(pdf.string?.contains("Título") == true)
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_PDF"] {
            try? FileManager.default.removeItem(atPath: saida)
            try FileManager.default.copyItem(at: destino, to: URL(fileURLWithPath: saida))
        }
    }
}


/// Pico de memória do processo (phys_footprint, o valor do Monitor de Atividade).
final class MedidorMemoria: @unchecked Sendable {
    private let trinco = NSLock()
    private var pico: UInt64 = 0

    var picoMB: Int { trinco.withLock { Int(pico / 1_048_576) } }

    func amostrar() {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
        }
        guard r == KERN_SUCCESS else { return }
        trinco.withLock { pico = max(pico, info.phys_footprint) }
    }
}

/// Gera apontamentos de uma aula já transcrita com o prompt atual. Só com `APONTAMENTOS_AULA=<pasta da aula>`.
struct IntegracaoApontamentosTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_AULA"] != nil), .timeLimit(.minutes(10)))
    func geraApontamentos() async throws {
        let pasta = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APONTAMENTOS_AULA"]!)
        let transcricao = try #require(Disco.lerTranscricao(pasta))
        let prompt = try String(contentsOf: Bundle(for: Marcador.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/prompt_sistema_default.md"), encoding: .utf8)
        let gerador = NotesGenerator(motor: .claudeCode(ClaudeCodeClient(executavel: try #require(ClaudeCodeClient.localizar()))),
                                     modelo: "claude-sonnet-5-5", esforco: .high, precos: TabelaPrecos())
        let r = try await gerador.gerar(ContextoAula(cadeira: "Álgebra Lineal", titulo: "Diagonalización", data: .now, glossario: "", transcricao: transcricao),
                                        prompt: prompt, aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: { _, _, _ in })
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try r.markdown.write(toFile: saida, atomically: true, encoding: .utf8)
        }
        #expect(r.markdown.contains("Em palavras simples"))
    }
}

private final class Marcador {
}

struct IntegracaoJanelaTests {
    /// `APONTAMENTOS_JANELA`: início do título da janela a captar durante 7 s (precisa da autorização de gravação de ecrã).
    static let janela = ProcessInfo.processInfo.environment["APONTAMENTOS_JANELA"]

    @Test(.enabled(if: janela != nil), .timeLimit(.minutes(3)))
    func captaImagensDeUmaJanela() async throws {
        let fontes = try await CapturaAudio.fontes()
        let fonte = try #require(fontes.first { $0.tituloJanela.hasPrefix(Self.janela ?? "") })
        #expect(fontes.isEmpty == false, "janelas: \(fontes.map { "\($0.nome) — \($0.tituloJanela)" })")
        let miniaturas = await CapturaAudio.miniaturas([fonte.janela])
        #expect(miniaturas[fonte.janela] != nil)
        let f = try GravadorFrames()
        defer { f.apagar() }
        let erro = Mutex<String?>(nil)
        let c = CapturaAudio(aoReceber: { _ in }, aoFrame: { f.receber($0) },
                             aoPararJanela: { e in erro.withLock { $0 = "\(e)" } }, aoParar: { _ in })
        try await c.iniciar(fonte)
        let duracao = ProcessInfo.processInfo.environment["APONTAMENTOS_SEGUNDOS"].flatMap(Double.init) ?? 7
        for s in stride(from: 0.0, through: duracao, by: 0.5) {
            f.gravarSeDevido(segundos: s)
            try await Task.sleep(for: .milliseconds(500))
        }
        await c.parar()
        f.concluir()
        let tempos = try await FontePasta(pasta: f.pasta).tempos(intervalo: 0)
        print("capturas: \(tempos)")
        #expect(erro.withLock { $0 } == nil)
        #expect(tempos.count >= 3)
        // Não pode vir preta (conteúdo protegido ou sem autorização).
        let url = f.pasta.appending(path: FontePasta.nome(try #require(tempos.last)))
        let imagem = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        let brilho = (0..<256).map { Int(ctx.data!.load(fromByteOffset: $0, as: UInt8.self)) }.reduce(0, +) / 256
        print("tamanho: \(imagem.width)x\(imagem.height), brilho médio: \(brilho)")
        #expect(brilho > 5)

        // Os slides que sairiam destas capturas.
        let aula = FileManager.default.temporaryDirectory.appending(path: "aula-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aula) }
        var config = ConfigSlides()
        config.recortarZonaAtiva = true
        let slides = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: f.pasta), para: aula) { _ in }
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try? FileManager.default.removeItem(atPath: saida)
            try FileManager.default.createDirectory(atPath: saida, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: aula.appending(path: "slides"), to: URL(fileURLWithPath: saida).appending(path: "slides"))
            try FileManager.default.copyItem(at: f.pasta, to: URL(fileURLWithPath: saida).appending(path: "capturas"))
        }
        #expect(slides.count >= 1, "\(imagem.width)x\(imagem.height), \(tempos.count) capturas")
    }

    /// `APONTAMENTOS_CAPTURAS=<pasta>`: slides de capturas já feitas (para afinar sem voltar a captar).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_CAPTURAS"] != nil), .timeLimit(.minutes(5)))
    func slidesDeCapturas() async throws {
        let pasta = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["APONTAMENTOS_CAPTURAS"]))
        let aula = FileManager.default.temporaryDirectory.appending(path: "aula-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: aula, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aula) }
        var config = ConfigSlides()
        config.recortarZonaAtiva = true
        let slides = try await SlideExtractor(config: config).extrair(de: FontePasta(pasta: pasta), para: aula) { _ in }
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try? FileManager.default.removeItem(atPath: saida)
            try FileManager.default.copyItem(at: aula.appending(path: "slides"), to: URL(fileURLWithPath: saida))
        }
        #expect(slides.count >= 1)
    }
}

/// Perguntas, exercícios e ligações com o Claude a sério. Só com `APONTAMENTOS_ESTUDO=<raiz com aulas>`;
/// o que o Claude escreve fica nos ficheiros das aulas dessa raiz.
@MainActor
struct IntegracaoEstudoTests {
    nonisolated static let raiz = ProcessInfo.processInfo.environment["APONTAMENTOS_ESTUDO"]

    @Test(.enabled(if: raiz != nil), .timeLimit(.minutes(15)))
    func perguntasExerciciosLigacoes() async throws {
        let library = Library(raiz: URL(fileURLWithPath: try #require(Self.raiz)))
        let estudo = Estudo(library: library, definicoes: Definicoes())
        let aulas = library.cadeiras.flatMap(\.aulas).sorted { $0.meta.data < $1.meta.data }
        let primeira = try #require(aulas.first), ultima = try #require(aulas.last)
        #expect(aulas.count >= 2)

        func esperar(_ aula: Aula, _ tipo: Estudo.Tipo) async {
            while estudo.emCurso(aula, tipo) != nil { try? await Task.sleep(for: .milliseconds(300)) }
        }

        estudo.perguntar("Não percebi a parte do gradiente. Podes explicar com o exemplo da aula?", sobre: primeira)
        estudo.gerarExercicios(primeira)
        estudo.gerarLigacoes(ultima)
        await esperar(primeira, .pergunta)
        await esperar(primeira, .exercicios)
        await esperar(ultima, .ligacoes)

        #expect(estudo.erro(primeira, .pergunta) == nil)
        #expect(estudo.erro(primeira, .exercicios) == nil)
        #expect(estudo.erro(ultima, .ligacoes) == nil)
        #expect(Disco.lerPerguntas(primeira.pasta).count >= 1)
        let exercicios = try #require(Disco.lerTexto(Disco.exerciciosMD, em: primeira.pasta))
        #expect(exercicios.contains("> **Resolução**"))
        let ligacoes = try #require(Disco.lerLigacoes(ultima.pasta))
        #expect(ligacoes.ligacoes.contains { $0.direcao == .anterior && $0.aula.hasSuffix(primeira.pasta.lastPathComponent) })
    }
}
