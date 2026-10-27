import AppKit
import Foundation
import PDFKit
import Testing
@testable import Apontamentos

struct SlidesNosApontamentosTests {
    @Test func trocaMarcasPelosFicheiros() {
        let md = "## Classes [18:25]\n\n![Slide 6 — Clases de empresa](slide:1/6)\n\nTexto.\n![Slide 99](slide:1/99)\nFim."
        let imagens = SlidesNosApontamentos.imagens(paginasPDF: [1: 36], capturas: [])
        let r = SlidesNosApontamentos.resolver(md, imagens: imagens)
        #expect(r.contains("![Slide 6 — Clases de empresa](slides-pdf/pagina-06.jpg)\n"))
        // Um slide que não existe sai, com a sua linha.
        #expect(!r.contains("99"))
        #expect(r.hasSuffix("Texto.\nFim."))
    }

    @Test func capturasPelaOrdem() {
        let capturas = [Slide(ficheiro: "slide_01_00-00.jpg", inicio: 0, fim: 1), Slide(ficheiro: "slide_02_24-26.jpg", inicio: 1, fim: 2)]
        let imagens = SlidesNosApontamentos.imagens(paginasPDF: [:], capturas: capturas)
        #expect(SlidesNosApontamentos.resolver("![Slide 2](slide:2)", imagens: imagens) == "![Slide 2](slides/slide_02_24-26.jpg)")
    }

    @Test func variosPDFsECapturasSemAmbiguidade() {
        let capturas = [Slide(ficheiro: "slide_01_00-00.jpg", inicio: 0, fim: 1)]
        let imagens = SlidesNosApontamentos.imagens(paginasPDF: [1: 10, 3: 5], capturas: capturas)
        let md = "![a](slide:1/7)\n![b](slide: 3 / 5)\n![c](slide:1)\n![d](slide:2/1)\n![e](slide:3/6)\nFim."
        let r = SlidesNosApontamentos.resolver(md, imagens: imagens)
        #expect(r == "![a](slides-pdf/pagina-07.jpg)\n![b](slides-pdf-3/pagina-05.jpg)\n![c](slides/slide_01_00-00.jpg)\nFim.")
    }

    private static func pdf(paginas: Int, tom: Double = 0.5) throws -> PDFDocument {
        let pdf = PDFDocument()
        for i in 0..<paginas {
            let img = NSImage(size: NSSize(width: 400, height: 225))
            img.lockFocus(); NSColor(white: (tom + Double(i)) / Double(paginas + 1), alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 400, height: 225).fill(); img.unlockFocus()
            pdf.insert(try #require(PDFPage(image: img)), at: i)
        }
        return pdf
    }

    @Test func criaUmaImagemPorPagina() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "slides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        // Uma aula antiga: só `slides-professor.pdf`, sem nome em aula.json.
        #expect(try Self.pdf(paginas: 3).write(to: pasta.appending(path: "slides-professor.pdf")))
        let pdfs = Disco.pdfsProfessor(pasta)
        #expect(pdfs == [PDFProfessor(numero: 1)])
        #expect(pdfs[0].titulo == "PDF 1")
        #expect(try SlidesNosApontamentos.garantirPaginas(de: pdfs[0], em: pasta) == 3)
        let pagina = pasta.appending(path: "slides-pdf/pagina-03.jpg")
        let imagem = try #require(NSImage(contentsOf: pagina))
        #expect(imagem.representations.first?.pixelsWide == 1600)
        SlidesNosApontamentos.apagarPaginas(de: pdfs[0], em: pasta)
        #expect(!FileManager.default.fileExists(atPath: pagina.path))
    }

    @Test func juntarERemoverVariosPDFs() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "pdfs-\(UUID().uuidString)")
        let pasta = base.appending(path: "aula"), origem = base.appending(path: "origem")
        for p in [pasta, origem] { try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: base) }
        let tema1 = origem.appending(path: "Tema 1.pdf"), tema2 = origem.appending(path: "Tema 2.pdf"), tema3 = origem.appending(path: "Tema 3.pdf")
        #expect(try Self.pdf(paginas: 2, tom: 0.1).write(to: tema1))
        #expect(try Self.pdf(paginas: 3, tom: 0.6).write(to: tema2))
        #expect(try Self.pdf(paginas: 1, tom: 0.9).write(to: tema3))

        let juntados = try Disco.juntarPDFsProfessor([tema1, tema2], em: pasta)
        #expect(juntados.map(\.numero) == [1, 2])
        #expect(juntados.map(\.nome) == ["Tema 1.pdf", "Tema 2.pdf"])
        #expect(Disco.existe("slides-professor.pdf", em: pasta) && Disco.existe("slides-professor-2.pdf", em: pasta))
        // O mesmo PDF outra vez não entra.
        #expect(try Disco.juntarPDFsProfessor([tema2], em: pasta).isEmpty)

        let nomes = Dictionary(uniqueKeysWithValues: juntados.map { ($0.ficheiro, $0.nome!) })
        #expect(Disco.pdfsProfessor(pasta, nomes: nomes).map(\.titulo) == ["Tema 1", "Tema 2"])
        #expect(await SlidesNosApontamentos.garantirPaginasEmFundo(em: pasta) == [1: 2, 2: 3])
        #expect(Disco.existe("slides-pdf-2/pagina-03.jpg", em: pasta))

        // Remover o primeiro não renumera o segundo (os apontamentos já feitos apontam para as páginas dele).
        try Disco.removerPDFProfessor(juntados[0], em: pasta)
        #expect(Disco.pdfsProfessor(pasta, nomes: [:]).map(\.numero) == [2])
        #expect(!Disco.existe("slides-pdf", em: pasta) && Disco.existe("slides-pdf-2/pagina-01.jpg", em: pasta))
        #expect(try Disco.juntarPDFsProfessor([tema3], em: pasta).map(\.numero) == [3])
    }

    @Test func limiteSomaOsPDFs() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "pdfs-\(UUID().uuidString)")
        let pasta = base.appending(path: "aula")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let grande = base.appending(path: "grande.pdf"), outro = base.appending(path: "outro.pdf")
        try Data(count: Disco.tamanhoMaximoPDF / 2 + 1).write(to: grande)
        try Data(repeating: 1, count: Disco.tamanhoMaximoPDF / 2 + 1).write(to: outro)
        _ = try Disco.juntarPDFsProfessor([grande], em: pasta)
        #expect(throws: (any Error).self) { try Disco.juntarPDFsProfessor([outro], em: pasta) }
        #expect(Disco.pdfsProfessor(pasta, nomes: [:]).count == 1)
    }

    @Test func numeroPeloNomeDoFicheiro() {
        #expect(PDFProfessor.numero(doFicheiro: "slides-professor.pdf") == 1)
        #expect(PDFProfessor.numero(doFicheiro: "slides-professor-12.pdf") == 12)
        #expect(PDFProfessor.numero(doFicheiro: "slides-professor-02.pdf") == nil)
        #expect(PDFProfessor.numero(doFicheiro: "slides-professor-1.pdf") == nil)
        #expect(PDFProfessor.numero(doFicheiro: "apontamentos.pdf") == nil)
        #expect(PDFProfessor(numero: 12).ficheiro == "slides-professor-12.pdf")
        #expect(PDFProfessor(numero: 12).pastaPaginas == "slides-pdf-12")
    }

    @Test func capturasEspalhadasAteAoLimite() {
        let capturas = (0..<100).map { SlideComImagem(slide: Slide(ficheiro: "\($0).jpg", inicio: Double($0), fim: Double($0) + 1), jpeg: Data(count: 10)) }
        let quarenta = ContextoAula.capturasQueCabem(capturas, bytes: 10_000)
        #expect(quarenta.count == 40)
        #expect(quarenta.first?.slide.ficheiro == "0.jpg" && quarenta.last?.slide.ficheiro == "99.jpg")
        #expect(Set(quarenta.map(\.slide.ficheiro)).count == 40)
        #expect(ContextoAula.capturasQueCabem(capturas, bytes: 50).count == 5)
        #expect(ContextoAula.capturasQueCabem(capturas, bytes: 5).isEmpty)
        #expect(ContextoAula.capturasQueCabem(Array(capturas.prefix(7)), bytes: 10_000).count == 7)
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

    @Test func numeroDoTituloEmQualquerLingua() {
        #expect(TituloAula.separar("Aula 1 · Conceito de empresa")! == (1, "Conceito de empresa"))
        #expect(TituloAula.separar("Clase 2 · Formas jurídicas · fiscalidad")! == (2, "Formas jurídicas · fiscalidad"))
        #expect(TituloAula.separar("Lecture 10 · Strategy")! == (10, "Strategy"))
        #expect(TituloAula.separar("Revisões para o exame") == nil)
        #expect(TituloAula.separar("Aula prática · Matrizes") == nil)
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

    /// Só o professor ensina: o prompt não deixa entrar o que os alunos dizem, nem validado.
    @Test func soAMateriaDoProfessor() {
        #expect(PromptStore.original.contains("nunca entra, mesmo que o professor concorde"))
        #expect(!PromptStore.original.contains("validado em aula"))
    }

    /// O espaço de cada tema segue o que o professor explicou: o que só mencionou fica numa caixa 👀, sem título nem slide.
    @Test @MainActor func oQueSoFoiMencionadoFicaNumaCaixa() {
        #expect(PromptStore.original.contains("`> 👀 **Só mencionado:** ...`"))
        #expect(!PromptStore.original.contains("`*Só mencionado:*"))
        #expect(Estudo.sistemaExercicios.contains("👀"))
        #expect(!PromptStore.original.contains("mesmo que o professor o tenha só lido ou passado depressa"))
        #expect(RotulosApontamentos.rotulo("Só mencionado", .es) == "Solo mencionado")
    }

    /// Quando o professor explica um termo só com o próprio termo, o Claude diz o que quer dizer, marcado com 💡 Ext. na mesma linha.
    @Test func explicaOQueOProfessorDeixouVago() {
        #expect(PromptStore.original.contains("- **<termo>:** <o que o professor disse>. 💡 *Ext.: <o que quer dizer na prática>*"))
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
