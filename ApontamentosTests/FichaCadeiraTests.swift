import Foundation
import Testing
@testable import Apontamentos

struct FichaCadeiraTests {
    @Test func separaASeccaoAteAoTituloSeguinte() {
        let md = """
        # Aula 1 · Tema

        ## Resumo
        Texto.

        ## Sobre a cadeira
        **Avaliação**
        - Exame: 60 %
        ### Datas
        - Exame a 01/02

        ## Conceito [00:00]
        Matéria.
        """
        let (apontamentos, sobre) = FichaCadeira.separar(md)
        #expect(sobre == "**Avaliação**\n- Exame: 60 %\n### Datas\n- Exame a 01/02")
        #expect(apontamentos == "# Aula 1 · Tema\n\n## Resumo\nTexto.\n\n## Conceito [00:00]\nMatéria.")
    }

    @Test func seccaoNoFimESemSeccao() {
        let (a, s) = FichaCadeira.separar("## Resumo\nX\n\n## Sobre a cadeira\n- Aviso\n")
        #expect(s == "- Aviso")
        #expect(a == "## Resumo\nX\n")
        let semNada = "## Resumo\nX\n### Sobre a cadeira\nnão é a secção"
        #expect(FichaCadeira.separar(semNada).sobre == nil)
        #expect(FichaCadeira.separar(semNada).apontamentos == semNada)
        // Um título dentro de um bloco de código não é a secção.
        #expect(FichaCadeira.separar("```\n## Sobre a cadeira\n```").sobre == nil)
    }

    @Test func limpaARespostaDoClaude() {
        #expect(FichaCadeira.limpar("```markdown\n# Sobre a cadeira\n\n## Avaliação\n- X\n```") == "# Sobre a cadeira\n\n## Avaliação\n- X\n")
        #expect(FichaCadeira.limpar("## Avaliação\n- X") == "# Sobre a cadeira\n\n## Avaliação\n- X\n")
    }

    @Test func migraEMarcaAsAulasPendentes() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "fichas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let cadeira = raiz.appending(path: "Cadeira")
        func aula(_ nome: String, dia: Int, notas: String) throws -> URL {
            let pasta = cadeira.appending(path: nome)
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            try Disco.escreverMeta(AulaMeta(titulo: nome, data: Date(timeIntervalSince1970: Double(dia) * 86_400), video: nil), em: pasta)
            try Disco.escreverApontamentos(notas, em: pasta)
            return pasta
        }
        let a1 = try aula("A1", dia: 1, notas: "## Resumo\nR\n\n## Sobre a cadeira\n- Exame: 60 %\n\n## Tema\nT")
        let a2 = try aula("A2", dia: 2, notas: "## Resumo\nR2\n\n## Tema\nT2")

        #expect(try FichaCadeira.migrar(a1))
        #expect(try !FichaCadeira.migrar(a2))
        #expect(try !FichaCadeira.migrar(a1)) // já migrada
        #expect(Disco.lerApontamentos(a1) == "## Resumo\nR\n\n## Tema\nT")
        #expect(FichaCadeira.lerExcerto(a1) == "- Exame: 60 %")

        var c = try #require(try Library.ler(raiz: raiz).first)
        #expect(FichaCadeira.pendentes(c).map(\.meta.titulo) == ["A1"])
        try FichaCadeira.escreverRegisto(.init(aulas: ["A1": FichaCadeira.hash("- Exame: 60 %")]), em: cadeira)
        #expect(FichaCadeira.pendentes(c).isEmpty)

        // Regenerada com outro excerto: volta a ficar pendente.
        try FichaCadeira.escreverExcerto("- Exame: 70 %", em: a1)
        try FichaCadeira.escreverExcerto("- Entrega a 29/01", em: a2)
        c = try #require(try Library.ler(raiz: raiz).first)
        #expect(FichaCadeira.pendentes(c).map(\.meta.titulo) == ["A1", "A2"])
        // Os ficheiros da cadeira não passam por aulas.
        try FichaCadeira.escreverFicha("# Sobre a cadeira\n", em: cadeira)
        #expect(try Library.ler(raiz: raiz).first?.aulas.count == 2)
    }

    @Test func programaPendenteTrocadoERemovido() throws {
        let cadeira = FileManager.default.temporaryDirectory.appending(path: "programa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cadeira, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cadeira) }
        let origem = cadeira.appending(path: "origem.pdf")
        try Data("%PDF-1 programa".utf8).write(to: origem)

        #expect(!FichaCadeira.programaPendente(cadeira))
        try FichaCadeira.juntarPrograma(origem, em: cadeira)
        #expect(FichaCadeira.temPrograma(cadeira) && FichaCadeira.programaPendente(cadeira))
        try FichaCadeira.escreverRegisto(.init(aulas: [FichaCadeira.chavePrograma: FichaCadeira.hash(Data("%PDF-1 programa".utf8))]), em: cadeira)
        #expect(!FichaCadeira.programaPendente(cadeira))

        try Data("%PDF-1 programa novo".utf8).write(to: origem)
        try FichaCadeira.juntarPrograma(origem, em: cadeira)
        #expect(FichaCadeira.programaPendente(cadeira))

        try FichaCadeira.removerPrograma(em: cadeira)
        #expect(!FichaCadeira.temPrograma(cadeira) && !FichaCadeira.programaPendente(cadeira))
        #expect(FichaCadeira.lerRegisto(cadeira).aulas[FichaCadeira.chavePrograma] == nil)
    }

    @Test func aFichaEntraNoPedidoDosApontamentos() {
        func texto(_ b: [BlocoConteudo]) -> String { b.compactMap { if case .texto(let t) = $0 { t } else { nil } }.joined(separator: "\n") }
        var c = ContextoAula(cadeira: "C", titulo: "A", data: .now, glossario: "", transcricao: Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: []))
        #expect(!texto(NotesGenerator.conteudo(c)).contains("<ficha>"))
        c.fichaCadeira = "# Sobre a cadeira\n## Programa\n- Tema 1"
        let t = texto(NotesGenerator.conteudo(c))
        #expect(t.contains("<ficha>") && t.contains("- Tema 1") && t.contains("nada copiado da ficha"))
    }

    @Test func pedidoDizSeAAulaJaTinhaEntrado() {
        func texto(_ b: [BlocoConteudo]) -> String { b.compactMap { if case .texto(let t) = $0 { t } else { nil } }.joined() }
        let novo = texto(FichaCadeira.conteudo(ficha: nil, excerto: "- X", aula: "Aula 2 (22/10/2026)", jaJuntada: false))
        #expect(novo.contains("(vazia)") && novo.contains("Aula 2 (22/10/2026)") && !novo.contains("já tinha entrado"))
        let outra = texto(FichaCadeira.conteudo(ficha: "# Sobre a cadeira\n- Y", excerto: "- X", aula: "Aula 1", jaJuntada: true))
        #expect(outra.contains("- Y") && outra.contains("já tinha entrado"))
    }
}
