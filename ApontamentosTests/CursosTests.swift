import Foundation
import Testing
@testable import Apontamentos

/// Vários cursos na mesma pasta das aulas: o catálogo lê-se das pastas, e os conteúdos nunca se misturam.
@MainActor
struct CursosTests {
    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "cursos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func definicoes() throws -> Definicoes {
        Definicoes(defaults: try #require(UserDefaults(suiteName: "cursos-\(UUID().uuidString)")))
    }

    /// Cria um curso novo no disco, como um Mac faria. Devolve a pasta.
    @discardableResult
    private func criarCurso(_ nome: String, em raiz: URL, meta: CursoMeta? = nil) throws -> URL {
        let curso = Disco.urlCursos(raiz: raiz).appending(path: nome, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: curso, withIntermediateDirectories: true)
        if let meta { try Disco.escreverCurso(meta, em: curso) }
        return curso
    }

    private func curso(_ id: String, em b: Biblioteca) throws -> Curso {
        try #require(b.cursos.first { $0.id == id })
    }

    // MARK: O catálogo

    /// Uma pasta como as de hoje: um só curso, e abrir não muda nada no disco.
    @Test func umaPastaDeHojeEUmCursoSo() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        _ = try lib.criarAula(cadeira: "Cálculo", titulo: "Límites", data: .now, video: nil)

        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())

        #expect(b.cursos.map(\.id) == [Curso.idDaRaiz])
        #expect(b.cursoAtivo.naRaiz)
        #expect(b.ativo.library.cadeira(nome: "Cálculo") != nil)
        #expect(!FileManager.default.fileExists(atPath: raiz.appending(path: Disco.pastaSistema).path))
        #expect(!FileManager.default.fileExists(atPath: Disco.urlCursos(raiz: raiz).path))
    }

    @Test func umaPastaVaziaTambemEUmCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        #expect(Biblioteca.ler(raiz: raiz).map(\.id) == [Curso.idDaRaiz])
    }

    @Test func cadaPastaEmCursosEUmCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        try criarCurso("Fintech360", em: raiz, meta: CursoMeta(nome: "Fintech 360"))
        // O `curso.json` pode ainda não ter chegado: continua a ser um curso, com o nome da pasta.
        try criarCurso("Sem ficha", em: raiz)
        // O que não é pasta, ou está escondido, não é um curso.
        try Data().write(to: Disco.urlCursos(raiz: raiz).appending(path: "nota.txt"))
        try FileManager.default.createDirectory(at: Disco.urlCursos(raiz: raiz).appending(path: ".escondida"), withIntermediateDirectories: true)

        let cursos = Biblioteca.ler(raiz: raiz)

        #expect(Set(cursos.map(\.id)) == [Curso.idDaRaiz, "Fintech360", "Sem ficha"])
        #expect(cursos.first { $0.id == "Fintech360" }?.nome == "Fintech 360")
        #expect(cursos.first { $0.id == "Sem ficha" }?.nome == "Sem ficha")
        #expect(cursos.first(where: \.naRaiz)?.nome == "O meu curso")
    }

    @Test func aRaizSemCadeirasNemNomeNaoEUmCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try criarCurso("Fintech360", em: raiz)
        #expect(Biblioteca.ler(raiz: raiz).map(\.id) == ["Fintech360"])

        // Com nome, continua a ser um curso, mesmo sem cadeiras.
        try Disco.escreverCurso(CursoMeta(nome: "Mestrado"), em: raiz)
        #expect(Set(Biblioteca.ler(raiz: raiz).map(\.id)) == [Curso.idDaRaiz, "Fintech360"])
    }

    @Test func osConcluidosFicamNoFim() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var feito = CursoMeta(nome: "Antigo")
        feito.estadoCurso = .concluido
        try criarCurso("A", em: raiz, meta: feito)
        try criarCurso("B", em: raiz, meta: CursoMeta(nome: "Zebra"))
        #expect(Biblioteca.ler(raiz: raiz).map(\.nome) == ["Zebra", "Antigo"])
    }

    /// Um estado que esta versão não conheça lê-se como "a decorrer", mas não se perde.
    @Test func umEstadoDesconhecidoNaoEstragaOCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let curso = try criarCurso("Fintech360", em: raiz)
        try FileManager.default.createDirectory(at: curso.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)
        try Data(#"{"nome":"Fintech","estado":"em-pausa","campoDoFuturo":1}"#.utf8).write(to: Disco.urlCurso(curso))

        var meta = Disco.lerCurso(curso)
        #expect(meta.nome == "Fintech")
        #expect(meta.estadoCurso == .aDecorrer)
        #expect(meta.estado == "em-pausa")

        meta.nome = "Fintech 360"
        try Disco.escreverCurso(meta, em: curso)
        #expect(Disco.lerCurso(curso).estado == "em-pausa")
    }

    @Test func oResumoContaOQueHaEmCadaCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let a = try lib.criarAula(cadeira: "Cálculo", titulo: "A", data: Date(timeIntervalSince1970: 1_800_000_000), video: nil)
        _ = try lib.criarAula(cadeira: "Cálculo", titulo: "B", data: Date(timeIntervalSince1970: 1_700_000_000), video: nil)
        try Disco.escreverApontamentos("# x", em: a)
        let vazio = try criarCurso("Fintech360", em: raiz)

        let r = Biblioteca.resumos(de: Biblioteca.ler(raiz: raiz))

        #expect(r[Curso.idDaRaiz] == ResumoCurso(cadeiras: 1, aulas: 2, porRever: 1, ultimaAula: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(r["Fintech360"] == ResumoCurso(cadeiras: 0, aulas: 0, porRever: 0, ultimaAula: nil))
        #expect(FileManager.default.fileExists(atPath: vazio.path))
    }

    // MARK: Abrir um curso

    @Test func abrirMudaTodaAVistaELembraSeDoCurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        _ = try Library(raiz: raiz).criarAula(cadeira: "Cálculo", titulo: "A", data: .now, video: nil)
        let fintech = try criarCurso("Fintech360", em: raiz)
        _ = try Library(raiz: fintech).criarAula(cadeira: "Pagamentos", titulo: "B", data: .now, video: nil)
        let d = try definicoes()
        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.cursoAtivo.naRaiz)
        #expect(b.ativo.library.cadeiras.map(\.nome) == ["Cálculo"])
        let daRaiz = b.ativo

        b.abrir(try curso("Fintech360", em: b))

        #expect(b.cursoAtivo.id == "Fintech360")
        #expect(b.ativo.library.cadeiras.map(\.nome) == ["Pagamentos"])
        #expect(b.ativo !== daRaiz)

        // Noutra abertura da app, volta ao mesmo curso.
        #expect(Biblioteca(raiz: raiz, definicoes: d).cursoAtivo.id == "Fintech360")

        // Voltar ao curso de antes é voltar aos mesmos serviços: o que lá estiver em curso continua a ser seguido.
        b.abrir(try curso(Curso.idDaRaiz, em: b))
        #expect(b.ativo === daRaiz)
        #expect(Biblioteca(raiz: raiz, definicoes: d).cursoAtivo.naRaiz)
    }

    /// Os conteúdos nunca se misturam: a raiz contém os cursos novos, mas não os lê como cadeiras.
    @Test func oCursoDaRaizNaoVeOsOutros() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        _ = try Library(raiz: raiz).criarAula(cadeira: "Cálculo", titulo: "A", data: .now, video: nil)
        let fintech = try criarCurso("Fintech360", em: raiz)
        _ = try Library(raiz: fintech).criarAula(cadeira: "Pagamentos", titulo: "B", data: .now, video: nil)

        let daRaiz = Library(raiz: raiz)
        #expect(daRaiz.cadeiras.map(\.nome) == ["Cálculo"])
        #expect(daRaiz.aulasNaNuvem == 0)
    }

    /// Dois cursos com uma cadeira de nome igual: cada um com o seu glossário, as suas preferências e os seus anos.
    @Test func cadeirasComOMesmoNomeNaoSeMisturam() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let aulaRaiz = try lib.criarAula(cadeira: "Finanças", titulo: "A", data: Date(timeIntervalSince1970: 1_700_000_000), video: nil)
        try lib.guardarCadeira(CadeiraMeta(glossario: "do mestrado"), cadeira: try #require(lib.cadeira(nome: "Finanças")))
        try lib.alterarPreferencias { $0.contextoCurso = "Mestrado" }

        let fintech = try criarCurso("Fintech360", em: raiz)
        let libF = Library(raiz: fintech)
        let aulaF = try libF.criarAula(cadeira: "Finanças", titulo: "A", data: .now, video: nil)
        try libF.guardarCadeira(CadeiraMeta(glossario: "do fintech"), cadeira: try #require(libF.cadeira(nome: "Finanças")))
        try libF.alterarPreferencias { $0.contextoCurso = "Fintech360"; $0.idioma = .ingles }

        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let doMestrado = try #require(b.servicos(de: aulaRaiz)).library
        let doFintech = try #require(b.servicos(de: aulaF)).library

        #expect(doMestrado !== doFintech)
        #expect(doMestrado.cadeira(nome: "Finanças")?.meta.glossario == "do mestrado")
        #expect(doFintech.cadeira(nome: "Finanças")?.meta.glossario == "do fintech")
        #expect(doMestrado.contextoCurso == "Mestrado")
        #expect(doFintech.contextoCurso == "Fintech360")
        #expect(doMestrado.idiomaAulas == .espanhol)
        #expect(doFintech.idiomaAulas == .ingles)
        // A cadeira de 2023 do mestrado não faz da de hoje do Fintech360 uma do 3.º ou 4.º ano.
        #expect(doFintech.cadeira(nome: "Finanças")?.semestre.ano == 1)
    }

    /// As preferências antigas do aparelho eram do curso que havia: não passam para os cursos novos.
    @Test func asPreferenciasAntigasSoServemAoCursoDaRaiz() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        try criarCurso("Fintech360", em: raiz)
        let d = try definicoes()
        d.defaults.set("Licenciatura em Física", forKey: "contextoCurso")
        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.ativo.library.contextoCurso == "Licenciatura em Física")

        b.abrir(try curso("Fintech360", em: b))
        #expect(b.ativo.library.contextoCurso == "")
    }

    // MARK: O curso em falta

    @Test func cursoEmFaltaAbreOutroSemEsquecerAEscolha() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let d = try definicoes()
        d.defaults.set("Fintech360", forKey: Biblioteca.chaveCursoAtivo)

        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.cursoAtivo.naRaiz)
        #expect(b.cursoEmFalta == "Fintech360")
        #expect(d.defaults.string(forKey: Biblioteca.chaveCursoAtivo) == "Fintech360")

        // Quando chega pelo iCloud, abre.
        try criarCurso("Fintech360", em: raiz)
        b.recarregarCursos()
        #expect(b.cursoAtivo.id == "Fintech360")
        #expect(b.cursoEmFalta == nil)
    }

    /// Escolher outro à mão: o que estava em falta deixa de contar.
    @Test func escolherOutroEsqueceOEmFalta() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let d = try definicoes()
        d.defaults.set("Fintech360", forKey: Biblioteca.chaveCursoAtivo)
        let b = Biblioteca(raiz: raiz, definicoes: d)

        b.abrir(try curso(Curso.idDaRaiz, em: b))
        #expect(b.cursoEmFalta == nil)

        try criarCurso("Fintech360", em: raiz)
        b.recarregarCursos()
        #expect(b.cursoAtivo.naRaiz)
    }

    /// O curso aberto foi apagado noutro aparelho: abre-se outro, e o apagado não volta.
    @Test func oCursoApagadoNaoVoltaComoFantasma() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let fintech = try criarCurso("Fintech360", em: raiz)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        b.abrir(try curso("Fintech360", em: b))
        let antigo = b.ativo

        try FileManager.default.removeItem(at: fintech)
        antigo.library.recarregar()
        #expect(!FileManager.default.fileExists(atPath: fintech.path))
        #expect(antigo.library.erro != nil)

        b.recarregarCursos()
        #expect(b.cursoAtivo.naRaiz)
        #expect(b.cursoEmFalta == "Fintech360")
        #expect(!FileManager.default.fileExists(atPath: fintech.path))
    }

    @Test func umPedidoNumCursoApagadoNaoTrazOCursoDeVolta() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let fintech = try criarCurso("Fintech360", em: raiz)
        try FileManager.default.removeItem(at: fintech)

        #expect(throws: (any Error).self) { try CaixaPedidos.enviar(PedidoMac(tipo: .exercicios, aula: "A/B"), raiz: fintech) }
        #expect(!FileManager.default.fileExists(atPath: fintech.path))
    }

    // MARK: A que curso pertence

    @Test func oCursoDeUmCaminhoEODoPrefixoMaisLongo() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let fintech = try criarCurso("Fintech360", em: raiz)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())

        #expect(b.curso(de: raiz.appending(path: "Cálculo/aula"))?.naRaiz == true)
        #expect(b.curso(de: fintech.appending(path: "Pagamentos/aula"))?.id == "Fintech360")
        #expect(b.curso(de: fintech)?.id == "Fintech360")
        // Dentro de `_recap`, fora de um curso conhecido, não é de nenhum: nunca da raiz.
        #expect(b.curso(de: Disco.urlCursos(raiz: raiz).appending(path: "Outro/Cadeira/aula")) == nil)
        #expect(b.curso(de: raiz.appending(path: "_recap/pedidos")) == nil)
    }

    /// Um curso que acabou de chegar pelo iCloud: ao procurar uma aula dele, relê-se o catálogo.
    @Test func procurarOCursoDeUmCaminhoReleOCatalogo() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let novo = try criarCurso("Fintech360", em: raiz)

        let s = try #require(b.servicos(de: novo.appending(path: "Pagamentos/aula")))
        #expect(s.library.raiz.mesmoCaminho(novo))
    }

    /// Um job de outro curso que não o aberto usa os serviços do curso dele.
    @Test func umJobDeOutroCursoCorreNoCursoDele() async throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let fintech = try criarCurso("Fintech360", em: raiz)
        let aula = try Library(raiz: fintech).criarAula(cadeira: "Pagamentos", titulo: "A", data: .now, video: nil)
        let d = try definicoes()
        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.cursoAtivo.naRaiz)

        let job = Job(pastaAula: aula, titulo: "A", video: nil, gerarApontamentos: false)
        await PipelineRunner(biblioteca: b, definicoes: d).executar(job)

        // Encontrou a aula e chegou a precisar do vídeo: não falhou por estar noutro curso.
        guard case .falhou(let motivo) = job.estado else {
            Issue.record("O job devia ter falhado por não ter vídeo.")
            return
        }
        #expect(motivo.contains("vídeo"))
        #expect(b.cursoAtivo.naRaiz)
    }

    /// O iPhone pode estar num curso que não é o aberto no Mac.
    @Test func aPonteRespondeNumCursoNaoAberto() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try FileManager.default.createDirectory(at: raiz.appending(path: "Cálculo"), withIntermediateDirectories: true)
        let fintech = try criarCurso("Fintech360", em: raiz)
        let d = try definicoes()
        d.motor = .claudeCode
        d.caminhoClaude = raiz.appending(path: "nao-existe").path
        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.cursoAtivo.naRaiz)
        // A aula aparece depois de a biblioteca abrir, como se viesse pelo iCloud.
        let aula = try Library(raiz: fintech).criarAula(cadeira: "Pagamentos", titulo: "A", data: .now, video: nil)
        let existe = PedidoMac(tipo: .exercicios, aula: Estudo.caminhoRelativo(aula, raiz: fintech))
        let naoExiste = PedidoMac(tipo: .exercicios, aula: "Pagamentos/nao-existe")
        try CaixaPedidos.enviar(existe, raiz: fintech)
        try CaixaPedidos.enviar(naoExiste, raiz: fintech)

        PonteMac(biblioteca: b, definicoes: d).verificar()

        #expect(CaixaPedidos.estado(naoExiste.id, raiz: fintech)?.erro?.contains("não está no Mac") == true)
        let e = try #require(CaixaPedidos.estado(existe.id, raiz: fintech))
        #expect(e.erro?.contains("não está no Mac") != true)
    }

    // MARK: Mudar a pasta das aulas

    @Test func mudarAPastaComOutroCursoAbertoFicaNoMesmoCurso() throws {
        let raiz = try pasta()
        let nova = FileManager.default.temporaryDirectory.appending(path: "cursos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: nova) }
        _ = try Library(raiz: raiz).criarAula(cadeira: "Cálculo", titulo: "A", data: .now, video: nil)
        let fintech = try criarCurso("Fintech360", em: raiz)
        _ = try Library(raiz: fintech).criarAula(cadeira: "Pagamentos", titulo: "B", data: .now, video: nil)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        b.abrir(try curso("Fintech360", em: b))

        try b.mudarRaiz(para: nova, mover: true)

        #expect(b.raiz.mesmoCaminho(nova))
        #expect(b.cursoAtivo.id == "Fintech360")
        #expect(b.ativo.library.raiz.estaDentro(de: nova))
        #expect(b.ativo.library.cadeiras.map(\.nome) == ["Pagamentos"])
        #expect(Set(b.cursos.map(\.id)) == [Curso.idDaRaiz, "Fintech360"])
        #expect(!FileManager.default.fileExists(atPath: fintech.path))
    }

    // MARK: Captações

    @Test func procurarUmaAulaQueMudouDeSitio() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let aula = try lib.criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        let fintech = try criarCurso("Fintech360", em: raiz)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let nome = aula.lastPathComponent

        // A mesma cadeira, noutra pasta das aulas de há uns tempos.
        let antiga = URL(fileURLWithPath: "/Volumes/Velho/Aulas/Finanças/\(nome)")
        #expect(b.procurarAula(antiga)?.mesmoCaminho(aula) == true)

        // A cadeira mudou de nome: encontra-se a pasta da aula noutra cadeira.
        let outroNome = URL(fileURLWithPath: "/Volumes/Velho/Aulas/Finanças antigas/\(nome)")
        #expect(b.procurarAula(outroNome)?.mesmoCaminho(aula) == true)

        // Com duas respostas possíveis, não se adivinha.
        _ = try Library(raiz: fintech).criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        #expect(b.procurarAula(antiga) == nil)
        #expect(b.procurarAula(outroNome) == nil)

        #expect(b.procurarAula(URL(fileURLWithPath: "/Volumes/Velho/Aulas/Finanças/2020-01-01_Outra")) == nil)
    }

    @Test func umaCaptacaoCujaAulaMudouDeSitioVoltaAFila() throws {
        let raiz = try pasta(), captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let aula = try Library(raiz: raiz).criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let c = try CaptacaoGuardada.criar(em: captacoes)
        try Data("som".utf8).write(to: c.audio)
        let antiga = URL(fileURLWithPath: "/Volumes/Velho/Aulas/Finanças antigas/\(aula.lastPathComponent)")
        try c.guardar(.init(pastaAula: antiga, titulo: "Juros", velocidade: 1, gerarApontamentos: true))
        let existe = { (u: URL) in FileManager.default.fileExists(atPath: u.path) }
        #expect(CaptacaoGuardada.pendentes(em: captacoes, aulaExiste: existe).isEmpty)

        CaptacaoGuardada.realojar(em: captacoes) { b.procurarAula($0) }

        let pendentes = CaptacaoGuardada.pendentes(em: captacoes, aulaExiste: existe)
        #expect(pendentes.count == 1)
        #expect(pendentes.first?.ficha.pastaAula.mesmoCaminho(aula) == true)
    }

    /// Com a aula no sítio, a ficha não se toca.
    @Test func realojarNaoMexeNoQueEstaCerto() throws {
        let raiz = try pasta(), captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let aula = try Library(raiz: raiz).criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        let c = try CaptacaoGuardada.criar(em: captacoes)
        try Data("som".utf8).write(to: c.audio)
        try c.guardar(.init(pastaAula: aula, titulo: "Juros", velocidade: 1, gerarApontamentos: true))

        CaptacaoGuardada.realojar(em: captacoes) { _ in
            Issue.record("Não devia procurar uma aula que está no sítio.")
            return nil
        }
        #expect(CaptacaoGuardada.pendentes(em: captacoes) { _ in true }.first?.ficha.pastaAula.mesmoCaminho(aula) == true)
    }
}
