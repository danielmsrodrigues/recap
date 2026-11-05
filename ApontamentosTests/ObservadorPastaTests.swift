import Foundation
import Testing
@testable import Apontamentos

/// Os pedidos entre o iPhone e o Mac (`_recap/pedidos`) mudam a cada poucos segundos enquanto o Mac responde, e cada
/// lado já os vigia sozinho: não obrigam a reler a biblioteca toda.
struct ObservadorPastaTests {
    private let raiz = URL(fileURLWithPath: "/Users/x/Aulas", isDirectory: true)

    @Test func osPedidosAoMacNaoContam() {
        #expect(ObservadorPasta.ignorar("/Users/x/Aulas/_recap/pedidos/1234.estado.json", raiz: raiz))
        #expect(ObservadorPasta.ignorar("/Users/x/Aulas/_recap/pedidos", raiz: raiz))
    }

    /// Os outros cursos estão dentro de `_recap` da pasta das aulas, mas não são deste curso.
    @Test func osOutrosCursosNaoContam() {
        #expect(ObservadorPasta.ignorar("/Users/x/Aulas/_recap/cursos/Fintech360/Módulo 1/aula.json", raiz: raiz))
        #expect(ObservadorPasta.ignorar("/Users/x/Aulas/_recap/cursos", raiz: raiz))
    }

    /// Um curso novo vigia a sua pasta, com os seus pedidos, e as suas aulas contam.
    @Test func dentroDeUmCursoNovoContaOQueEDele() {
        let curso = raiz.appending(path: "_recap/cursos/Fintech360")
        #expect(!ObservadorPasta.ignorar(curso.path + "/Módulo 1/2026-10-19_Aula 1/apontamentos.md", raiz: curso))
        #expect(ObservadorPasta.ignorar(curso.path + "/_recap/pedidos/1234.json", raiz: curso))
    }

    /// O catálogo vigia a pasta toda: conta um curso novo a chegar, mas não os pedidos de nenhum curso.
    @Test func noCatalogoContaTudoMenosOsPedidos() {
        #expect(!ObservadorPasta.ignorarNoCatalogo("/Users/x/Aulas/_recap/cursos/Fintech360", raiz: raiz))
        #expect(!ObservadorPasta.ignorarNoCatalogo("/Users/x/Aulas/_recap/cursos/Fintech360/_recap/curso.json", raiz: raiz))
        #expect(!ObservadorPasta.ignorarNoCatalogo("/Users/x/Aulas/Cálculo", raiz: raiz))
        #expect(ObservadorPasta.ignorarNoCatalogo("/Users/x/Aulas/_recap/pedidos/1.json", raiz: raiz))
        #expect(ObservadorPasta.ignorarNoCatalogo("/Users/x/Aulas/_recap/cursos/Fintech360/_recap/pedidos", raiz: raiz))
    }

    @Test func asAulasEAsDefinicoesContam() {
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas/Cálculo/2026-10-19_Aula 1/apontamentos.md", raiz: raiz))
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas/_recap/definicoes.json", raiz: raiz))
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas", raiz: raiz))
    }
}
