import Foundation
import Testing
@testable import Apontamentos

/// O que o iPhone e o iPad mostram em Hoje, Por rever e Cadeiras (`Revisao`), e as secções de uma aula
/// (`SeccoesApontamentos`).
struct RevisaoTests {
    private func aula(_ titulo: String, _ cadeira: String, dia: Int, revista: Bool = false, apontamentos: Bool = true) -> Aula {
        var meta = AulaMeta(titulo: titulo, data: Date(timeIntervalSince1970: 1_790_000_000 + Double(dia) * 86_400), video: nil)
        meta.revista = revista
        return Aula(pasta: URL(filePath: "/aulas/\(cadeira)/\(titulo)"), cadeira: cadeira, meta: meta,
                    temTranscricao: true, temApontamentos: apontamentos, temSlides: false)
    }

    private func cadeira(_ nome: String, _ aulas: [Aula]) -> Cadeira {
        Cadeira(nome: nome, pasta: URL(filePath: "/aulas/\(nome)"), meta: CadeiraMeta(), aulas: aulas, semestre: Semestre(ano: 1, numero: 1))
    }

    private var cadeiras: [Cadeira] {
        [cadeira("Cálculo", [aula("C1", "Cálculo", dia: 19, revista: true), aula("C2", "Cálculo", dia: 26)]),
         cadeira("Empresas", [aula("E3", "Empresas", dia: 28), aula("E4", "Empresas", dia: 29), aula("E5", "Empresas", dia: 30, apontamentos: false)])]
    }

    @Test func porReverSaoAsComApontamentosAindaNaoRevistasMaisRecentesPrimeiro() {
        #expect(Revisao.porRever(cadeiras).map(\.meta.titulo) == ["E4", "E3", "C2"])
    }

    @Test func aProximaEAMaisRecenteDasOutrasPorRever() {
        let c = cadeiras
        let e4 = c[1].aulas[1]
        #expect(Revisao.proxima(depoisDe: e4, em: c)?.meta.titulo == "E3")
        let tudoRevisto = [cadeira("Cálculo", [aula("C1", "Cálculo", dia: 19, revista: true), aula("C2", "Cálculo", dia: 26)])]
        #expect(Revisao.proxima(depoisDe: tudoRevisto[0].aulas[1], em: tudoRevisto) == nil)
    }

    @Test func recentesPelaData() {
        #expect(Revisao.recentes(cadeiras, limite: 3).map(\.meta.titulo) == ["E5", "E4", "E3"])
    }

    @Test func siglaComAsIniciaisDasPalavrasQueContam() {
        #expect(Revisao.sigla("Álgebra Lineal") == "ÁL")
        #expect(Revisao.sigla("Fundamentos de Empresas e Economia") == "FE")
        #expect(Revisao.sigla("Probabilidade e Estatística") == "PE")
        #expect(Revisao.sigla("Cálculo") == "CÁ")
        #expect(Revisao.sigla("") == "?")
    }

    /// Cada cadeira tem uma cor sua (até 8), sempre a mesma para o mesmo conjunto de cadeiras.
    @Test func coresDiferentesParaCadaCadeiraEEstaveis() {
        let nomes = ["Álgebra Lineal", "Cálculo", "Fundamentos de Empresas e Economia", "Fundamentos de Programação",
                     "Probabilidade e Estatística"]
        let cores = Revisao.matizes(nomes)
        #expect(Set(cores.values).count == nomes.count)
        #expect(cores == Revisao.matizes(nomes.reversed()))
        #expect(cores.values.allSatisfy { (0..<1).contains($0) })
        let muitas = (1...12).map { "Cadeira \($0)" }
        #expect(Set(Revisao.matizes(Array(muitas.prefix(8))).values).count == 8)
        #expect(Revisao.matizes(muitas).count == 12)
    }

    @Test func apontamentosPartidosEmSeccoes() {
        let md = """
        # Números reales

        ## Resumen
        Se repasan los tipos de números.

        ## Tipos de números [04:12]
        Los números reales se construyen por pasos.

        ```
        ## isto não é um título
        ```

        ## Intervalos
        Abiertos y cerrados: $[a, b]$.
        """
        let a = SeccoesApontamentos.partir(md)
        #expect(a.titulo == "Números reales")
        #expect(a.resumo == "Se repasan los tipos de números.")
        #expect(a.seccoes.map(\.titulo) == ["Tipos de números", "Intervalos"])
        #expect(a.seccoes[0].corpo.contains("## isto não é um título"))
        #expect(a.seccoes[0].corpo.hasPrefix("Los números"))
        #expect(a.seccoes[1].corpo == "Abiertos y cerrados: $[a, b]$.")
    }

    @Test func cadaSeccaoSabeOMinutoEmQueComeca() {
        // Os apontamentos escrevem [mm:ss] mesmo depois da primeira hora: [122:20].
        let a = SeccoesApontamentos.partir("# T\n\n## Avisos [00:33]\nx\n\n## Intervalos [1:38:05]\ny\n\n## Rich [122:20]\nw\n\n## Dúvidas\nz")
        #expect(a.seccoes.map(\.inicio) == [33, 5885, 7340, nil])
        #expect(a.seccoes.map(\.titulo) == ["Avisos", "Intervalos", "Rich", "Dúvidas"])
    }

    /// A barra de capítulos do Mac: as secções com minuto, cada uma até à seguinte, com os slides que mostrou.
    @Test func capitulosAteAoSeguinteComOsSlides() {
        let s = [SeccoesApontamentos.Seccao(titulo: "Avisos", corpo: "", inicio: 0),
                 SeccoesApontamentos.Seccao(titulo: "Números", corpo: "", inicio: 600),
                 SeccoesApontamentos.Seccao(titulo: "Dúvidas", corpo: "", inicio: nil),
                 SeccoesApontamentos.Seccao(titulo: "Intervalos", corpo: "", inicio: 3000)]
        let c = Capitulos.calcular(s, duracao: 3600, slides: [10, 620, 700, 3100, 3700])
        #expect(c.map(\.titulo) == ["Avisos", "Números", "Intervalos"])
        #expect(c.map(\.inicio) == [0, 600, 3000])
        #expect(c.map(\.fim) == [600, 3000, 3600])
        #expect(c.map(\.slides) == [1, 2, 1])
        // Menos de dois capítulos não dá barra.
        #expect(Capitulos.calcular(Array(s.prefix(1)), duracao: 3600, slides: []).isEmpty)
    }

    @Test func quebrasDeLinhaDoWindows() {
        let a = SeccoesApontamentos.partir("# Tema\r\n\r\n## Resumo\r\nCurto.\r\n\r\n## Parte 1\r\nTexto.")
        #expect(a.titulo == "Tema")
        #expect(a.resumo == "Curto.")
        #expect(a.seccoes.map(\.titulo) == ["Parte 1"])
    }

    @Test func semTitulosFicaTudoNumaSeccao() {
        let a = SeccoesApontamentos.partir("Só texto, sem títulos.")
        #expect(a.titulo == nil && a.resumo == nil)
        #expect(a.seccoes == [SeccoesApontamentos.Seccao(titulo: "", corpo: "Só texto, sem títulos.")])
    }
}
