import Foundation
import Testing
@testable import Apontamentos

/// O livro da cadeira: a capa com o índice, a ficha, todas as aulas por ordem e o glossário no fim.
struct LivroCadeiraTests {
    private let aula1 = LivroCadeira.Capitulo(numero: 1, titulo: "Clase 1 · Números reales", data: Date(timeIntervalSince1970: 1_792_400_000), apontamentos: """
    # Clase 1 · Números reales
    ## Resumen
    Los números reales [02:10] y la recta.
    ## Glosario
    - **Racional:** cociente de enteros.
    - **Irracional:** no periódico.
    """)
    private let aula2 = LivroCadeira.Capitulo(numero: 2, titulo: "Clase 2 · Valor absoluto", data: Date(timeIntervalSince1970: 1_793_000_000), apontamentos: """
    # Clase 2 · Valor absoluto
    ## Resumen
    La distancia al cero [1:05:00].
    ## Glosario
    - **Valor absoluto:** distancia al cero.
    - **Racional:** cociente de enteros.
    """)

    @Test func aCapaTemOIndiceDasAulasPorOrdem() {
        let capa = LivroCadeira.capa(cadeira: "Cálculo", capitulos: [aula2, aula1], ficha: nil)
        #expect(capa.hasPrefix("# Cálculo"))
        let i1 = capa.range(of: "Aula 1 · Clase 1 · Números reales")!, i2 = capa.range(of: "Aula 2 · Clase 2 · Valor absoluto")!
        #expect(i1.lowerBound < i2.lowerBound)
    }

    @Test func aFichaEntraDepoisDoIndiceSemOTituloDela() {
        let capa = LivroCadeira.capa(cadeira: "Cálculo", capitulos: [aula1], ficha: "# Sobre la asignatura\n\n## Evaluación\nExamen 50 %.")
        #expect(capa.contains("## Evaluación"))
        #expect(!capa.contains("# Sobre la asignatura"))
    }

    @Test func numLivroImpressoOsMinutosSaem() {
        let texto = LivroCadeira.paraImprimir(aula2.apontamentos)
        #expect(!texto.contains("[1:05:00]"))
        #expect(texto.contains("La distancia al cero."))
    }

    @Test func oGlossarioJuntaOsTermosDeTodasAsAulasSemRepetir() {
        let glossario = LivroCadeira.glossario([aula1, aula2])
        #expect(glossario.hasPrefix("# Glosario"))
        #expect(glossario.components(separatedBy: "**Racional:**").count - 1 == 1)
        // Por ordem alfabética.
        let ordem = ["**Irracional:**", "**Racional:**", "**Valor absoluto:**"].map { glossario.range(of: $0)!.lowerBound }
        #expect(ordem == ordem.sorted())
    }

    @Test func semGlossarioNasAulasNaoHaPagina() {
        let semNada = LivroCadeira.Capitulo(numero: 1, titulo: "A", data: .now, apontamentos: "# A\n## Resumen\nNada.")
        #expect(LivroCadeira.glossario([semNada]).isEmpty)
    }
}
