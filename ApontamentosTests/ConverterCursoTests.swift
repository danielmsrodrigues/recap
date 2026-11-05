import Foundation
import Testing
@testable import Apontamentos

/// O botão Converter: as cadeiras da raiz passam para a pasta do curso, sem se perder nada, mesmo que pare a meio.
@MainActor
struct ConverterCursoTests {
    private struct Falhou: Error {}

    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "converter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func definicoes() throws -> Definicoes {
        Definicoes(defaults: try #require(UserDefaults(suiteName: "converter-\(UUID().uuidString)")))
    }

    /// Uma raiz em formato antigo: duas cadeiras com aulas, ligações, perguntas, ficha e preferências.
    private func raizAntiga() throws -> (raiz: URL, aulaA: URL, aulaB: URL) {
        let raiz = try pasta()
        let lib = Library(raiz: raiz)
        let a = try lib.criarAula(cadeira: "Finanças", titulo: "Juros", data: Date(timeIntervalSince1970: 1_700_000_000), video: nil)
        let b = try lib.criarAula(cadeira: "Estratégia", titulo: "Vantagem", data: Date(timeIntervalSince1970: 1_800_000_000), video: nil)
        try Disco.escreverApontamentos("# Juros", em: a)
        try Disco.escreverPerguntas([PerguntaAula(pergunta: "?", resposta: "!")], em: a)
        try lib.alterarPreferencias { $0.contextoCurso = "Mestrado"; $0.idioma = .portugues }
        let l = LigacoesAula(ligacoes: [.init(aula: Estudo.caminhoRelativo(b, raiz: raiz), direcao: .seguinte, conceitos: ["x"], explicacao: "y")], temas: [])
        try Disco.escreverLigacoes(l, em: a)
        try Disco.escreverCurso(CursoMeta(nome: "Mestrado"), em: raiz)
        return (raiz, a, b)
    }

    private func preferencias(_ raiz: URL) -> DefinicoesPartilhadas {
        DefinicoesPartilhadas.ler(raiz: raiz) ?? .porDefeito
    }

    /// Os ficheiros de uma pasta, com o conteúdo, por caminho relativo.
    private func arvore(_ raiz: URL) throws -> [String: Data] {
        var r: [String: Data] = [:]
        let base = raiz.resolvingSymlinksInPath().path
        let itens = try #require(FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in itens where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            r[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return r
    }

    /// Só as cadeiras, sem o que está em `_recap`.
    private func cadeiras(_ arvore: [String: Data]) -> [String: Data] {
        arvore.filter { !$0.key.hasPrefix("/_recap/") }
    }

    private func destino(_ raiz: URL, _ id: String = "Mestrado") -> URL {
        Disco.urlCursos(raiz: raiz).appending(path: id, directoryHint: .isDirectory)
    }

    // MARK: Converter

    @Test func tudoPassaIgualParaAPastaDoCurso() throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let antes = cadeiras(try arvore(raiz))
        #expect(!antes.isEmpty)

        let ficaram = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        #expect(ficaram.isEmpty)
        let curso = destino(raiz)
        #expect(cadeiras(try arvore(curso)) == antes)
        #expect(cadeiras(try arvore(raiz)).isEmpty)
        #expect(Disco.lerCurso(curso).nome == "Mestrado")
        #expect(preferencias(curso).contextoCurso == "Mestrado")
        #expect(preferencias(curso).idioma == .portugues)
        // A pasta continua a ser reconhecida como a das aulas, e já não é um curso.
        #expect(Disco.problemaPastaAulas(raiz) == nil)
        #expect(Biblioteca.ler(raiz: raiz).map(\.id) == ["Mestrado"])
        #expect(ConversorCurso.registo(raiz: raiz) == nil)
        #expect(!FileManager.default.fileExists(atPath: Disco.urlCurso(raiz).path))
    }

    /// As ligações e o resto guardam caminhos relativos à raiz do curso: continuam a apontar para a aula certa.
    @Test func asLigacoesContinuamValidas() throws {
        let (raiz, aulaA, aulaB) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }

        _ = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        let lib = Library(raiz: destino(raiz))
        let nova = try #require(lib.cadeira(nome: "Finanças")?.aulas.first)
        #expect(nova.pasta.lastPathComponent == aulaA.lastPathComponent)
        #expect(Disco.lerApontamentos(nova.pasta) == "# Juros")
        #expect(Disco.lerPerguntas(nova.pasta).count == 1)
        let l = try #require(Disco.lerLigacoes(nova.pasta))
        let alvo = lib.raiz.appending(path: try #require(l.ligacoes.first).aula, directoryHint: .isDirectory)
        #expect(lib.aula(em: alvo)?.meta.titulo == "Vantagem")
        #expect(alvo.lastPathComponent == aulaB.lastPathComponent)
        // Os anos não mudam: os mesmos cálculos, sobre as mesmas datas.
        #expect(lib.cadeiras.count == 2)
    }

    /// Refazer as ligações gasta a subscrição: uma conversão não as pode deixar desatualizadas, mesmo com os acentos
    /// dos nomes das pastas noutra forma Unicode depois de mudarem de sítio.
    @Test func asLigacoesNaoFicamDesatualizadas() throws {
        let (raiz, aulaA, aulaB) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        try Disco.escreverApontamentos("# Vantagem", em: aulaB)
        let (relA, relB) = (Estudo.caminhoRelativo(aulaA, raiz: raiz), Estudo.caminhoRelativo(aulaB, raiz: raiz))
        var l = try #require(Disco.lerLigacoes(aulaA))
        l.assinaturas = [relA: NotasLigacoes.assinatura("# Juros"), relB: NotasLigacoes.assinatura("# Vantagem")]
        l.formato = LigacoesAula.formatoAtual
        try Disco.escreverLigacoes(l, em: aulaA)

        _ = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        let lib = Library(raiz: destino(raiz))
        let a = try #require(lib.cadeira(nome: "Finanças")?.aulas.first)
        let b = try #require(lib.cadeira(nome: "Estratégia")?.aulas.first)
        #expect(!Estudo.ligacoesDesatualizadas(a, outras: [b], raiz: lib.raiz))
    }

    /// O estado do curso vai com ele.
    @Test func oEstadoPassaParaOCurso() throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        var meta = Disco.lerCurso(raiz)
        meta.estadoCurso = .concluido
        try Disco.escreverCurso(meta, em: raiz)

        _ = try ConversorCurso.converter(raiz: raiz, nome: "Novo nome", preferencias: preferencias(raiz), captacoes: captacoes)

        let novo = destino(raiz, "Novo nome")
        #expect(Disco.lerCurso(novo).estadoCurso == .concluido)
        #expect(Disco.lerCurso(novo).nome == "Novo nome")
    }

    @Test func umDestinoQueJaExisteERecusadoSemMexerEmNada() throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        try FileManager.default.createDirectory(at: destino(raiz, "Fintech360"), withIntermediateDirectories: true)
        let antes = try arvore(raiz)

        #expect(throws: ErroCurso.jaExiste("Fintech360")) {
            try ConversorCurso.converter(raiz: raiz, nome: "Fintech360", preferencias: preferencias(raiz), captacoes: captacoes)
        }
        #expect(try arvore(raiz) == antes)
        #expect(ConversorCurso.registo(raiz: raiz) == nil)
    }

    /// Ficheiros soltos e escondidos não são cadeiras: ficam onde estão.
    @Test func oQueNaoECadeiraFicaNaRaiz() throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let solto = raiz.appending(path: "nota.txt")
        try Data("x".utf8).write(to: solto)

        _ = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        #expect(FileManager.default.fileExists(atPath: solto.path))
    }

    /// A pasta de uma cadeira pode ter o nome em qualquer forma Unicode (criada no Finder, ou depois de mudar de sítio):
    /// a cor é a mesma, e a conversão não muda as cores.
    @Test func aCorNaoDependeDaFormaDosAcentos() {
        let composta = "Finanças".precomposedStringWithCanonicalMapping
        let decomposta = "Finanças".decomposedStringWithCanonicalMapping
        #expect(Array(composta.unicodeScalars) != Array(decomposta.unicodeScalars))
        #expect(Revisao.matizes([composta])[composta] == Revisao.matizes([decomposta])[decomposta])
    }

    // MARK: Parar a meio

    /// Falha ao mover a n-ésima cadeira.
    private func moverQueFalha(em n: Int) -> (URL, URL) throws -> Void {
        var contador = 0
        return { origem, destino in
            contador += 1
            if contador == n { throw Falhou() }
            try FileManager.default.moveItem(at: origem, to: destino)
        }
    }

    @Test(arguments: [1, 2]) func pararAMeioNaoEscondeNadaEPodeContinuar(falhaEm: Int) throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let antes = cadeiras(try arvore(raiz))

        #expect(throws: Falhou.self) {
            try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes, mover: moverQueFalha(em: falhaEm))
        }

        // Nada desaparece: o que ainda não mudou está na raiz, o que mudou está no curso, sem nada em dois sítios.
        let naRaiz = cadeiras(try arvore(raiz)), noCurso = cadeiras(try arvore(destino(raiz)))
        #expect(naRaiz.count + noCurso.count == antes.count)
        #expect(naRaiz.merging(noCurso) { a, _ in a } == antes)
        // Os dois aparecem no catálogo, e a app sabe que ficou a meio.
        #expect(Set(Biblioteca.ler(raiz: raiz).map(\.id)) == [Curso.idDaRaiz, "Mestrado"])
        #expect(ConversorCurso.registo(raiz: raiz) == .init(destino: "Mestrado", nome: "Mestrado"))
        #expect(Disco.problemaPastaAulas(raiz) == nil)

        // Continuar acaba o trabalho, mesmo com outro nome na caixa: fica o do registo.
        let ficaram = try ConversorCurso.converter(raiz: raiz, nome: "Outro", preferencias: .porDefeito, captacoes: captacoes)
        #expect(ficaram.isEmpty)
        #expect(cadeiras(try arvore(destino(raiz))) == antes)
        #expect(cadeiras(try arvore(raiz)).isEmpty)
        #expect(ConversorCurso.registo(raiz: raiz) == nil)
        #expect(Biblioteca.ler(raiz: raiz).map(\.id) == ["Mestrado"])
        // As preferências são as do curso, não as passadas na continuação.
        #expect(preferencias(destino(raiz)).contextoCurso == "Mestrado")
    }

    /// Falhar logo no primeiro passo depois do registo: continuar não precisa de nada do que falhou.
    @Test func continuarDepoisDeFalharAntesDeMoverSejaOQueFor() throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        // Como se a app tivesse fechado logo depois de escrever o registo.
        try Disco.escrever(ConversorCurso.Registo(destino: "Mestrado", nome: "Mestrado"), em: ConversorCurso.urlRegisto(raiz: raiz))
        let antes = cadeiras(try arvore(raiz))

        let ficaram = try ConversorCurso.converter(raiz: raiz, nome: "", preferencias: preferencias(raiz), captacoes: captacoes)

        #expect(ficaram.isEmpty)
        #expect(cadeiras(try arvore(destino(raiz))) == antes)
    }

    /// Uma cadeira que já existe no destino junta-se; um ficheiro que já lá está não se substitui e a conversão fica por acabar.
    @Test func umFicheiroQueJaExisteNoDestinoNaoESubstituido() throws {
        let (raiz, aulaA, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        try Disco.escrever(ConversorCurso.Registo(destino: "Mestrado", nome: "Mestrado"), em: ConversorCurso.urlRegisto(raiz: raiz))
        let alvo = destino(raiz).appending(path: "Finanças").appending(path: aulaA.lastPathComponent)
        try FileManager.default.createDirectory(at: alvo, withIntermediateDirectories: true)
        try Data("o que já lá estava".utf8).write(to: alvo.appending(path: Disco.apontamentosMD))

        let ficaram = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        #expect(ficaram == ["Finanças/\(aulaA.lastPathComponent)/\(Disco.apontamentosMD)"])
        #expect(try Data(contentsOf: alvo.appending(path: Disco.apontamentosMD)) == Data("o que já lá estava".utf8))
        #expect(try Data(contentsOf: aulaA.appending(path: Disco.apontamentosMD)) == Data("# Juros".utf8))
        #expect(ConversorCurso.registo(raiz: raiz) != nil)
        #expect(Disco.lerCurso(raiz).nome == "Mestrado")
    }

    // MARK: Captações

    /// O áudio por transcrever é a única cópia da gravação: a ficha passa a apontar para o sítio novo.
    @Test func umaCaptacaoPendenteSobrevive() throws {
        let (raiz, aulaA, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let c = try CaptacaoGuardada.criar(em: captacoes)
        try Data("som".utf8).write(to: c.audio)
        try c.guardar(.init(pastaAula: aulaA, titulo: "Juros", velocidade: 1, gerarApontamentos: true))

        _ = try ConversorCurso.converter(raiz: raiz, nome: "Mestrado", preferencias: preferencias(raiz), captacoes: captacoes)

        let pendentes = CaptacaoGuardada.pendentes(em: captacoes) { FileManager.default.fileExists(atPath: $0.path) }
        #expect(pendentes.count == 1)
        let nova = try #require(pendentes.first).ficha.pastaAula
        #expect(nova.mesmoCaminho(destino(raiz).appending(path: "Finanças").appending(path: aulaA.lastPathComponent)))
    }

    /// A app fechou-se a meio de uma conversão, antes de corrigir a ficha: ao abrir, a captação encontra a aula.
    @Test func umaCaptacaoSobreviveAFecharAMeio() throws {
        let (raiz, aulaA, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let c = try CaptacaoGuardada.criar(em: captacoes)
        try Data("som".utf8).write(to: c.audio)
        try c.guardar(.init(pastaAula: aulaA, titulo: "Juros", velocidade: 1, gerarApontamentos: true))
        // A cadeira já mudou de sítio e a ficha ainda aponta para o antigo.
        try FileManager.default.createDirectory(at: destino(raiz), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: raiz.appending(path: "Finanças"), to: destino(raiz).appending(path: "Finanças"))
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())

        CaptacaoGuardada.realojar(em: captacoes) { b.procurarAula($0) }

        let pendentes = CaptacaoGuardada.pendentes(em: captacoes) { FileManager.default.fileExists(atPath: $0.path) }
        #expect(pendentes.count == 1)
    }

    // MARK: Na Biblioteca

    @Test func depoisDeConverterAbreOCursoComTudoIgual() async throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let d = try definicoes()
        let b = Biblioteca(raiz: raiz, definicoes: d)
        #expect(b.cursoAtivo.naRaiz)

        let ficaram = try await b.converterCursoDaRaiz(nome: "Mestrado", captacoes: captacoes)

        #expect(ficaram.isEmpty)
        #expect(!b.aConverter)
        #expect(b.cursoAtivo.id == "Mestrado")
        #expect(!b.cursoAtivo.naRaiz)
        #expect(b.cursos.map(\.id) == ["Mestrado"])
        #expect(b.ativo.library.contextoCurso == "Mestrado")
        #expect(Set(b.ativo.library.cadeiras.map(\.nome)) == ["Finanças", "Estratégia"])
        #expect(b.conversaoPorAcabar == nil)
        #expect(Biblioteca(raiz: raiz, definicoes: d).cursoAtivo.id == "Mestrado")
    }

    @Test func converterAoLadoDeOutroCursoNaoLheToca() async throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        let fintech = try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito)
        _ = try Library(raiz: fintech.pasta).criarAula(cadeira: "Finanças", titulo: "Pagamentos", data: .now, video: nil)
        let antes = try arvore(fintech.pasta)

        _ = try await b.converterCursoDaRaiz(nome: "Mestrado", captacoes: captacoes)

        #expect(try arvore(fintech.pasta) == antes)
        #expect(Set(b.cursos.map(\.id)) == ["Mestrado", "Fintech360"])
        #expect(b.cursoAtivo.id == "Mestrado")
    }

    @Test func umNomeOcupadoERecusadoSemMexerEmNada() async throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito)
        let antes = cadeiras(try arvore(raiz))

        await #expect(throws: ErroCurso.jaExiste("fintech360")) { try await b.converterCursoDaRaiz(nome: "fintech360", captacoes: captacoes) }
        await #expect(throws: ErroCurso.semNome) { try await b.converterCursoDaRaiz(nome: "  ", captacoes: captacoes) }
        #expect(cadeiras(try arvore(raiz)) == antes)
        #expect(!b.aConverter)
    }

    /// Com um pedido do iPhone por tratar, a aula pode mudar de sítio a meio da resposta: espera-se.
    @Test func comPedidosPorTratarERecusado() async throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        try CaixaPedidos.enviar(PedidoMac(tipo: .exercicios, aula: "Finanças/x"), raiz: raiz)

        await #expect(throws: ErroCurso.ocupado) { try await b.converterCursoDaRaiz(nome: "Mestrado", captacoes: captacoes) }
        #expect(ConversorCurso.registo(raiz: raiz) == nil)
    }

    /// Por ler as preferências, levavam-se as de recurso para o curso novo.
    @Test func comAsPreferenciasPorLerERecusado() async throws {
        let (raiz, _, _) = try raizAntiga()
        let captacoes = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz); try? FileManager.default.removeItem(at: captacoes) }
        let b = Biblioteca(raiz: raiz, definicoes: try definicoes())
        try Data("não é JSON".utf8).write(to: DefinicoesPartilhadas.url(raiz: raiz))

        await #expect(throws: ErroPreferencias.self) { try await b.converterCursoDaRaiz(nome: "Mestrado", captacoes: captacoes) }
        #expect(ConversorCurso.registo(raiz: raiz) == nil)
    }

    /// Os jobs parados cuja aula mudou de sítio saem da fila; os outros ficam.
    @Test func aFilaLargaOsJobsParadosSemPasta() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let d = try definicoes()
        let lib = Library(raiz: raiz)
        let fichas = Fichas(library: lib, definicoes: d)
        let fila = ProcessingQueue(runner: PipelineRunner(library: lib, definicoes: d, fichas: fichas, estudo: Estudo(library: lib, definicoes: d)))
        fila.emEspera = true
        let aula = try lib.criarAula(cadeira: "Finanças", titulo: "A", data: .now, video: nil)
        let semPasta = Job(pastaAula: raiz.appending(path: "Finanças/mudou"), titulo: "B", video: nil, gerarApontamentos: false)
        let comPasta = Job(pastaAula: aula, titulo: "A", video: nil, gerarApontamentos: false)
        let aEsperar = Job(pastaAula: raiz.appending(path: "Finanças/a-espera"), titulo: "C", video: nil, gerarApontamentos: false)
        for j in [semPasta, comPasta, aEsperar] { fila.adicionar(j) }
        semPasta.falhar("x")
        comPasta.falhar("y")

        fila.removerSemPasta()

        #expect(fila.jobs.map(\.id) == [comPasta.id, aEsperar.id])
    }
}
