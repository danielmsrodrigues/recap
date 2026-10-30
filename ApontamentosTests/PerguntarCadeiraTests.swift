import Foundation
import Testing
@testable import Apontamentos

/// Perguntar à cadeira inteira: o que vai no pedido e para onde levam os links das respostas.
struct PerguntarCadeiraTests {
    private func aula(_ pasta: String) -> Aula {
        Aula(pasta: URL(filePath: "/aulas/Cálculo/\(pasta)"), cadeira: "Cálculo",
             meta: AulaMeta(titulo: pasta, data: .now, video: nil), temTranscricao: true, temApontamentos: true, temSlides: false)
    }

    private let notas = """
    # Clase 3
    ## Resumen
    Se ven los límites.
    ## Límites [12:34]
    Un límite es…
    ![Slide 4](slides/slide_04.jpg)
    """

    @Test func cadaAulaLevaONumeroOPrefixoEOsMinutos() {
        let texto = Estudo.aulaParaCadeira(Estudo.AulaNaCadeira(numero: 3, titulo: "Clase 3", data: .now, prefixo: "2026-10-29-aula-3",
                                                                 apontamentos: notas), completa: true)
        #expect(texto.contains("numero=\"3\""))
        #expect(texto.contains("prefixo=\"2026-10-29-aula-3\""))
        // Os minutos ficam: são o que o Claude usa para os links para o momento da aula.
        #expect(texto.contains("[12:34]"))
        #expect(texto.contains("(#2026-10-29-aula-3/"))
        #expect(!texto.contains("![Slide"))
    }

    @Test func quandoNaoCabemAsMaisAntigasVaoSoComOResumo() {
        let aulas = (1...3).map { n in
            Estudo.AulaNaCadeira(numero: n, titulo: "Aula \(n)", data: Date(timeIntervalSince1970: Double(n) * 86_400),
                                 prefixo: "aula-\(n)", apontamentos: notas + String(repeating: "x", count: 1_000))
        }
        // Cabem duas: as mais recentes vão completas, a primeira só com o resumo.
        let texto = Estudo.aulasParaCadeira(aulas, limite: 2_500)
        #expect(texto.components(separatedBy: "<apontamentos>").count - 1 == 2)
        #expect(texto.components(separatedBy: "<resumo>").count - 1 == 1)
        #expect(texto.range(of: "aula-1")!.lowerBound < texto.range(of: "aula-3")!.lowerBound)
    }

    @Test func oLinkComArrobaLevaAoMinutoDaAula() {
        let aulas = [aula("2026-10-22_Aula 2"), aula("2026-10-29_Aula 3")]
        let prefixo = Estudo.prefixoLink(aulas[1].pasta)
        let d = Estudo.destino(LigacaoSeccao(ancora: "#\(prefixo)@12:34", texto: "Aula 3 · 12:34"), aulas: aulas)
        #expect(d?.pasta == aulas[1].pasta)
        #expect(d?.separador == .transcricao)
        #expect(d?.tempo == 754)
    }

    @Test func oLinkComBarraLevaASeccaoDaAula() {
        let aulas = [aula("2026-10-22_Aula 2")]
        let prefixo = Estudo.prefixoLink(aulas[0].pasta)
        let d = Estudo.destino(LigacaoSeccao(ancora: "#\(prefixo)/limites", texto: "Límites"), aulas: aulas)
        #expect(d?.pasta == aulas[0].pasta)
        #expect(d?.separador == .apontamentos)
        #expect(d?.seccao?.ancora == "limites")
    }

    @Test func umLinkDeOutraCadeiraNaoLevaANadaSitio() {
        #expect(Estudo.destino(LigacaoSeccao(ancora: "#nao-existe@01:00", texto: "x"), aulas: [aula("2026-10-22_Aula 2")]) == nil)
    }

    @Test func asPerguntasDaCadeiraFicamNaPastaDaCadeira() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "cadeira-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        #expect(Disco.lerPerguntasCadeira(pasta).isEmpty)
        let p = PerguntaAula(pergunta: "Onde se deram os limites?", resposta: "Na Aula 3.")
        try Disco.escreverPerguntasCadeira([p], em: pasta)
        #expect(Disco.lerPerguntasCadeira(pasta).map(\.pergunta) == ["Onde se deram os limites?"])
        // Não é uma aula: a pasta da cadeira não ganha um `aula.json`.
        #expect(!FileManager.default.fileExists(atPath: pasta.appending(path: "aula.json").path))
    }
}
