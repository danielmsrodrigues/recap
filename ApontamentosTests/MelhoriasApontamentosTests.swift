import AppKit
import Foundation
import PDFKit
import Testing
@testable import Apontamentos

struct SlidesNosApontamentosTests {
    @Test func trocaMarcasPelosFicheiros() {
        let md = "## Classes [18:25]\n\n![Slide 6 — Clases de empresa](slide:6)\n\nTexto.\n![Slide 99](slide:99)\nFim."
        let imagens = SlidesNosApontamentos.imagens(em: URL(fileURLWithPath: "/tmp"), paginasPDF: 36, capturas: [])
        let r = SlidesNosApontamentos.resolver(md, imagens: imagens)
        #expect(r.contains("![Slide 6 — Clases de empresa](slides-pdf/pagina-06.jpg)\n"))
        // Um slide que não existe sai, com a sua linha.
        #expect(!r.contains("99"))
        #expect(r.hasSuffix("Texto.\nFim."))
    }

    @Test func capturasPelaOrdem() {
        let capturas = [Slide(ficheiro: "slide_01_00-00.jpg", inicio: 0, fim: 1), Slide(ficheiro: "slide_02_24-26.jpg", inicio: 1, fim: 2)]
        let imagens = SlidesNosApontamentos.imagens(em: URL(fileURLWithPath: "/tmp"), paginasPDF: nil, capturas: capturas)
        #expect(SlidesNosApontamentos.resolver("![Slide 2](slide:2)", imagens: imagens) == "![Slide 2](slides/slide_02_24-26.jpg)")
    }

    @Test func criaUmaImagemPorPagina() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "slides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        let pdf = PDFDocument()
        for i in 0..<3 {
            let img = NSImage(size: NSSize(width: 400, height: 225))
            img.lockFocus(); NSColor(white: Double(i) / 3, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 400, height: 225).fill(); img.unlockFocus()
            pdf.insert(try #require(PDFPage(image: img)), at: i)
        }
        #expect(pdf.write(to: pasta.appending(path: Disco.slidesPDF)))
        #expect(try SlidesNosApontamentos.garantirPaginas(em: pasta) == 3)
        let pagina = pasta.appending(path: "slides-pdf/pagina-03.jpg")
        let imagem = try #require(NSImage(contentsOf: pagina))
        #expect(imagem.representations.first?.pixelsWide == 1600)
        SlidesNosApontamentos.apagarPaginas(em: pasta)
        #expect(!FileManager.default.fileExists(atPath: pagina.path))
    }
}

struct TituloAulaTests {
    @Test func temaDoCabecalho() {
        #expect(TituloAula.tema("# O que é uma empresa e como se classifica\n\n## Resumo") == "O que é uma empresa e como se classifica")
        #expect(TituloAula.tema("# Fundamentos de Empresas — Aula 1: o que é uma empresa\n") == "O que é uma empresa")
        #expect(TituloAula.tema("Sem título\n# Depois") == nil)
        #expect(TituloAula.tema("# Aula 3") == nil)
        #expect(TituloAula.tema("# clase 2 — Matrices") == "Matrices")
    }

    @Test func trocaSoOPrimeiroCabecalho() {
        let md = "# Tema\n\n## Resumo\n# Outro"
        #expect(TituloAula.trocarCabecalho(md, por: "Aula 2 · Tema") == "# Aula 2 · Tema\n\n## Resumo\n# Outro")
    }

    @Test @MainActor func numeroPelaOrdemDasDatas() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "titulo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let library = Library(raiz: raiz)
        let dia: TimeInterval = 86_400
        let segunda = try library.criarAula(cadeira: "Empresas", titulo: "b", data: Date(timeIntervalSince1970: 2 * dia), video: nil)
        _ = try library.criarAula(cadeira: "Empresas", titulo: "a", data: Date(timeIntervalSince1970: dia), video: nil)
        _ = try library.criarAula(cadeira: "Outra", titulo: "c", data: Date(timeIntervalSince1970: 0), video: nil)
        #expect(library.numeroDaAula(try #require(library.aula(em: segunda))) == 2)
    }

    @Test @MainActor func mudarOTituloAMaoMarcaComoManual() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "titulo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let library = Library(raiz: raiz)
        let pasta = try library.criarAula(cadeira: "Empresas", titulo: "Aula 1", data: .now, video: nil)
        let aula = try #require(library.aula(em: pasta))
        let mesma = try library.editarAula(aula, titulo: "Aula 1", data: aula.meta.data, cadeira: "Empresas")
        #expect(library.aula(em: mesma)?.meta.tituloManual == nil)
        let nova = try library.editarAula(try #require(library.aula(em: mesma)), titulo: "Introdução", data: aula.meta.data, cadeira: "Empresas")
        #expect(library.aula(em: nova)?.meta.tituloManual == true)
    }
}

struct OradoresTests {
    private func palavras(_ texto: String, desde inicio: Double) -> [Oradores.Palavra] {
        texto.split(separator: " ").enumerated().map { i, p in
            Oradores.Palavra(texto: " " + p, inicio: inicio + Double(i) * 0.5, fim: inicio + Double(i) * 0.5 + 0.4)
        }
    }

    @Test func professorEQuemFalaMais() {
        let turnos = [Oradores.Turno(inicio: 0, fim: 50, voz: 1), Oradores.Turno(inicio: 50, fim: 60, voz: 0)]
        #expect(Oradores.vozPrincipal(turnos) == 1)
    }

    @Test func vozDoProfessorPartidaEmDuasContaComoProfessor() {
        // Distâncias medidas com vozes sintéticas: 0 = professora, 3 = o fim de uma fala dela sem pausas, 1 e 2 = alunos.
        let d: [Set<Int>: Float] = [[0, 1]: 0.91, [0, 2]: 1.05, [0, 3]: 0.76, [1, 2]: 0.51, [1, 3]: 0.88, [2, 3]: 1.04]
        let turnos = [
            Oradores.Turno(inicio: 0, fim: 24.6, voz: 0), Oradores.Turno(inicio: 25.3, fim: 31.2, voz: 1),
            Oradores.Turno(inicio: 32.2, fim: 46.7, voz: 0), Oradores.Turno(inicio: 47.4, fim: 53.4, voz: 2),
            Oradores.Turno(inicio: 54.5, fim: 68.0, voz: 0), Oradores.Turno(inicio: 68.0, fim: 76.5, voz: 3),
        ]
        #expect(Oradores.vozesDoProfessor(principal: 0, turnos: turnos) { d[[$0, $1]] } == [0, 3])
    }

    @Test func soDuasVozesExigeFalaColada() {
        let perto: (Int, Int) -> Float? = { _, _ in 0.7 }
        // Um aluno parecido, mas que responde depois de uma pausa: continua aluno.
        let resposta = [Oradores.Turno(inicio: 0, fim: 20, voz: 0), Oradores.Turno(inicio: 20.8, fim: 25, voz: 1)]
        #expect(Oradores.vozesDoProfessor(principal: 0, turnos: resposta, distancia: perto) == [0])
        // A mesma voz partida a meio de uma fala contínua: é o professor.
        let partida = [Oradores.Turno(inicio: 0, fim: 20, voz: 0), Oradores.Turno(inicio: 20, fim: 25, voz: 1)]
        #expect(Oradores.vozesDoProfessor(principal: 0, turnos: partida, distancia: perto) == [0, 1])
    }

    @Test func semVozDominanteNaoSeDecide() {
        let turnos = [Oradores.Turno(inicio: 0, fim: 10, voz: 0), Oradores.Turno(inicio: 10, fim: 18, voz: 1), Oradores.Turno(inicio: 18, fim: 26, voz: 2)]
        #expect(Oradores.vozPrincipal(turnos) == nil)
    }

    @Test func parteOSegmentoOndeMudaAVoz() {
        // "creo que no estoy segura" (aluna, 0–2,5 s) + "muy buena la pregunta vamos a definir" (professora).
        let p = palavras("creo que no estoy segura es muy buena la pregunta vamos a definir", desde: 0)
        let turnos = [Oradores.Turno(inicio: 0, fim: 2.45, voz: 1), Oradores.Turno(inicio: 2.45, fim: 10, voz: 0)]
        let s = Segmento(inicio: 0, fim: 6.4, texto: "creo que no estoy segura es muy buena la pregunta vamos a definir")
        let r = Oradores.marcar([(s, p)], turnos: turnos, professor: [0])
        #expect(r.map(\.orador) == [.aluno, .professor])
        #expect(r[0].texto == "creo que no estoy segura")
        #expect(r[1].texto.hasPrefix("es muy buena"))
        #expect(r[1].inicio == 2.5)
    }

    @Test func trocasMuitoCurtasNaoPartem() {
        let p = palavras("uno dos tres cuatro cinco seis siete ocho", desde: 0)
        // Só a palavra "cuatro" (1,5–1,9 s) cai noutra voz.
        let turnos = [Oradores.Turno(inicio: 0, fim: 1.45, voz: 0), Oradores.Turno(inicio: 1.45, fim: 1.95, voz: 1), Oradores.Turno(inicio: 1.95, fim: 9, voz: 0)]
        let r = Oradores.marcar([(Segmento(inicio: 0, fim: 4, texto: "x"), p)], turnos: turnos, professor: [0])
        #expect(r.count == 1)
        #expect(r[0].orador == .professor)
        #expect(r[0].texto == "x")
    }

    @Test func semPalavrasUsaASobreposicao() {
        let turnos = [Oradores.Turno(inicio: 0, fim: 3, voz: 2), Oradores.Turno(inicio: 3, fim: 4, voz: 0)]
        let r = Oradores.marcar([(Segmento(inicio: 0, fim: 4, texto: "hola"), [])], turnos: turnos, professor: [0])
        #expect(r[0].orador == .aluno)
    }

    @Test func transcricaoMarcaAsLinhasDosAlunos() {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 10, criadaEm: .now, segmentos: [
            Segmento(inicio: 0, fim: 2, texto: "¿Qué es una empresa?", orador: .professor),
            Segmento(inicio: 2, fim: 4, texto: "Una organización.", orador: .aluno),
        ])
        #expect(t.textoComTimestamps == "[00:00] ¿Qué es una empresa?\n[00:02] (aluno) Una organización.")
        #expect(t.temOradores)
    }

    @Test func transcricoesAntigasContinuamAAbrir() throws {
        let json = #"{"idioma":"es","modelo":"m","duracao":1,"criadaEm":"2026-10-14T18:04:05Z","segmentos":[{"inicio":0,"fim":1,"texto":"hola"}]}"#
        let t = try Disco.decoder.decode(Transcricao.self, from: Data(json.utf8))
        #expect(t.segmentos[0].orador == nil)
        #expect(!t.temOradores)
    }
}

struct PromptStoreTests {
    @Test func promptPorDefeitoAtualNaoEstaNaListaDosAntigos() {
        #expect(!PromptStore.original.isEmpty)
        #expect(!PromptStore.versoesAntigas.contains(PromptStore.sha256(PromptStore.original)))
    }
}

/// Separação por vozes com o modelo real (descarrega ~30 MB). Só com `APONTAMENTOS_VOZES=<pasta com professor.aiff e aluno.aiff>`.
struct IntegracaoVozesTests {
    static let pasta = ProcessInfo.processInfo.environment["APONTAMENTOS_VOZES"]

    @Test(.enabled(if: pasta != nil), .timeLimit(.minutes(20)))
    func distingueProfessorDeAluno() async throws {
        let pasta = URL(fileURLWithPath: try #require(Self.pasta))
        let store = ModelStore()
        if !store.estaDescarregado(.largeV3Turbo) { _ = try await store.descarregar(.largeV3Turbo) { _ in } }
        let transcriber = Transcriber()
        try await transcriber.carregar(.largeV3Turbo, store: store)
        await transcriber.carregarVozes(base: store.base)
        #expect(await transcriber.semVozes == nil)

        let aula = pasta.appending(path: "aula.m4a")
        let duracao = try await AudioExtractor.duracao(aula)
        let segmentos = try await transcriber.transcrever(ficheiro: aula, duracao: duracao, glossario: "") { _ in }
        let t = Transcricao(idioma: "es", modelo: "turbo", duracao: duracao, criadaEm: .now, segmentos: segmentos)
        try t.textoComTimestamps.write(to: pasta.appending(path: "resultado.txt"), atomically: true, encoding: .utf8)
        #expect(segmentos.contains { $0.orador == .aluno })
        #expect(segmentos.contains { $0.orador == .professor })
    }
}
