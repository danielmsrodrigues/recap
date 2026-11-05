import Foundation
import Testing
@testable import Apontamentos

/// Criar, renomear e concluir cursos: nada do que já existe muda de sítio.
@MainActor
struct GerirCursosTests {
    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "gerir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func biblioteca(em raiz: URL) throws -> Biblioteca {
        Biblioteca(raiz: raiz, definicoes: Definicoes(defaults: try #require(UserDefaults(suiteName: "gerir-\(UUID().uuidString)"))))
    }

    private func preferencias(_ contexto: String) -> DefinicoesPartilhadas {
        var p = DefinicoesPartilhadas.porDefeito
        p.contextoCurso = contexto
        p.idioma = .ingles
        return p
    }

    /// A árvore toda, com o conteúdo de cada ficheiro, para ver que nada mudou.
    private func arvore(_ raiz: URL) throws -> [String: Data] {
        var r: [String: Data] = [:]
        // Com os caminhos resolvidos: a pasta temporária vem por /var e os ficheiros por /private/var.
        let base = raiz.resolvingSymlinksInPath().path
        let itens = try #require(FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in itens where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            r[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return r
    }

    @Test func criarNaoTocaNasCadeirasDaRaiz() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let aula = try lib.criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        try Disco.escreverApontamentos("# Juros", em: aula)
        try lib.alterarPreferencias { $0.contextoCurso = "Mestrado" }
        let antes = try arvore(raiz)
        let b = try biblioteca(em: raiz)

        let novo = try b.criarCurso(nome: "Fintech360", preferencias: preferencias("Fintech"))

        #expect(novo.id == "Fintech360")
        #expect(novo.pasta.mesmoCaminho(Disco.urlCursos(raiz: raiz).appending(path: "Fintech360")))
        let depois = try arvore(raiz)
        for (caminho, dados) in antes { #expect(depois[caminho] == dados, "Mudou: \(caminho)") }
        // O que há de novo está todo dentro de `_recap/cursos`.
        for caminho in Set(depois.keys).subtracting(antes.keys) { #expect(caminho.hasPrefix("/_recap/cursos/Fintech360/"), "Fora do curso: \(caminho)") }
        #expect(Set(b.cursos.map(\.id)) == [Curso.idDaRaiz, "Fintech360"])
        #expect(b.cursoAtivo.naRaiz)
    }

    @Test func oCursoNovoFicaComAsPreferenciasDele() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        try b.ativo.library.criarCadeira(nome: "Finanças")

        b.abrir(try b.criarCurso(nome: "Fintech360", preferencias: preferencias("Fintech")))

        #expect(b.cursoAtivo.nome == "Fintech360")
        #expect(b.ativo.library.contextoCurso == "Fintech")
        #expect(b.ativo.library.idiomaAulas == .ingles)
        #expect(b.ativo.library.cadeiras.isEmpty)
        #expect(!b.ativo.library.preferenciasPorLer)
    }

    /// O contexto é do curso: não se copia. A língua das aulas é a escolhida, e a dos apontamentos vem do curso aberto.
    @Test func asPreferenciasDeUmCursoNovoNaoCopiamOContexto() {
        var atual = DefinicoesPartilhadas.porDefeito
        atual.contextoCurso = "Mestrado em Gestão"
        atual.lingua = .en
        atual.idioma = .espanhol
        atual.organizacaoCurso = .nenhuma
        atual.duracao = 1

        let novas = DefinicoesPartilhadas.paraCursoNovo(idioma: .ingles, como: atual)

        #expect(novas.contextoCurso == "")
        #expect(novas.idioma == .ingles)
        #expect(novas.lingua == .en)
        #expect(novas.organizacaoCurso == DefinicoesPartilhadas.porDefeito.organizacaoCurso)
        #expect(novas.duracao == DefinicoesPartilhadas.porDefeito.duracao)
    }

    @Test func nomesRepetidosOuVaziosSaoRecusados() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        try b.ativo.library.criarCadeira(nome: "Finanças")
        try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito, nomeDoCursoDaRaiz: "Mestrado")

        #expect(throws: ErroCurso.jaExiste("fintech360")) { try b.criarCurso(nome: "fintech360", preferencias: .porDefeito) }
        #expect(throws: ErroCurso.jaExiste("Mestrado")) { try b.criarCurso(nome: "Mestrado", preferencias: .porDefeito) }
        #expect(throws: ErroCurso.semNome) { try b.criarCurso(nome: "   ", preferencias: .porDefeito) }
        #expect(b.cursos.count == 2)
    }

    /// Nomes diferentes podem dar a mesma pasta (a `/` passa a `-`).
    @Test func umaPastaJaExistenteERecusada() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        try b.criarCurso(nome: "A-B", preferencias: preferencias("Primeiro"))

        #expect(throws: ErroCurso.jaExiste("A/B")) { try b.criarCurso(nome: "A/B", preferencias: preferencias("Segundo")) }
        #expect(DefinicoesPartilhadas.ler(raiz: Disco.urlCursos(raiz: raiz).appending(path: "A-B"))?.contextoCurso == "Primeiro")
    }

    /// O curso da raiz recebe nome ao criar o segundo, e as cadeiras ficam onde estão.
    @Test func criarDaNomeAoCursoDaRaiz() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        let aula = try lib.criarAula(cadeira: "Finanças", titulo: "Juros", data: .now, video: nil)
        let b = try biblioteca(em: raiz)
        #expect(b.cursoDaRaizPorNomear != nil)

        try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito, nomeDoCursoDaRaiz: "Mestrado em Gestão")

        #expect(b.cursoDaRaizPorNomear == nil)
        #expect(b.cursoAtivo.nome == "Mestrado em Gestão")
        #expect(Disco.lerCurso(raiz).nome == "Mestrado em Gestão")
        #expect(FileManager.default.fileExists(atPath: aula.path))
    }

    @Test func oMesmoNomeParaOsDoisERecusadoSemMexerEmNada() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        try b.ativo.library.criarCadeira(nome: "Finanças")

        #expect(throws: ErroCurso.jaExiste("Curso")) { try b.criarCurso(nome: "Curso", preferencias: .porDefeito, nomeDoCursoDaRaiz: "curso") }
        #expect(!FileManager.default.fileExists(atPath: Disco.urlCurso(raiz).path))
        #expect(!FileManager.default.fileExists(atPath: Disco.urlCursos(raiz: raiz).path))
    }

    /// Numa pasta vazia, a raiz não tem o que nomear, e deixa de contar quando há um curso novo.
    @Test func numaPastaVaziaNaoHaCursoPorNomear() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        #expect(b.cursoDaRaizPorNomear == nil)

        let novo = try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito)
        #expect(b.cursos.map(\.id) == ["Fintech360"])
        // O curso aberto era o da raiz, que deixou de existir: abre-se o que há, sem aviso de curso em falta.
        #expect(b.cursoAtivo.id == novo.id)
        #expect(b.cursoEmFalta == nil)
    }

    /// Renomear muda só o nome: a pasta fica, e o que estava aberto continua aberto.
    @Test func renomearNaoMexeNaPasta() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        let novo = try b.criarCurso(nome: "Fintech360", preferencias: .porDefeito)
        b.abrir(novo)
        let servicos = b.ativo

        try b.renomear(novo, para: "Fintech 360 (2.ª edição)")

        #expect(b.cursoAtivo.nome == "Fintech 360 (2.ª edição)")
        #expect(b.cursoAtivo.id == "Fintech360")
        #expect(b.ativo === servicos)
        #expect(FileManager.default.fileExists(atPath: novo.pasta.path))
        #expect(Disco.lerCurso(novo.pasta).nome == "Fintech 360 (2.ª edição)")
    }

    @Test func renomearParaUmNomeOcupadoERecusado() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        let a = try b.criarCurso(nome: "A", preferencias: .porDefeito)
        try b.criarCurso(nome: "B", preferencias: .porDefeito)

        #expect(throws: ErroCurso.jaExiste("b")) { try b.renomear(a, para: "b") }
        #expect(throws: ErroCurso.semNome) { try b.renomear(a, para: "  ") }
        // Só mudar maiúsculas do próprio nome pode-se.
        try b.renomear(a, para: "a")
        #expect(Disco.lerCurso(a.pasta).nome == "a")
    }

    @Test func concluirEVoltarAPorADecorrer() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        let a = try b.criarCurso(nome: "A", preferencias: .porDefeito)
        try b.criarCurso(nome: "B", preferencias: .porDefeito)
        b.abrir(a)

        try b.definirConcluido(true, curso: a)

        #expect(b.cursos.map(\.nome) == ["B", "A"])
        #expect(b.cursos.last?.concluido == true)
        #expect(Disco.lerCurso(a.pasta).concluidoEm != nil)
        // Concluído continua a poder estar aberto, e tudo o que tem continua lá.
        #expect(b.cursoAtivo.id == "A")
        #expect(b.cursoAtivo.concluido)

        try b.definirConcluido(false, curso: a)
        #expect(!b.cursoAtivo.concluido)
        #expect(Disco.lerCurso(a.pasta).concluidoEm == nil)
    }

    /// Mudar o nome não apaga o que não muda.
    @Test func renomearMantemOEstado() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let b = try biblioteca(em: raiz)
        let a = try b.criarCurso(nome: "A", preferencias: .porDefeito)
        try b.definirConcluido(true, curso: a)

        try b.renomear(try #require(b.cursos.first { $0.id == a.id }), para: "A2")

        #expect(Disco.lerCurso(a.pasta).nome == "A2")
        #expect(Disco.lerCurso(a.pasta).estadoCurso == .concluido)
    }
}
