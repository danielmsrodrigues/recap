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

    @Test func asAulasEAsDefinicoesContam() {
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas/Cálculo/2026-10-19_Aula 1/apontamentos.md", raiz: raiz))
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas/_recap/definicoes.json", raiz: raiz))
        #expect(!ObservadorPasta.ignorar("/Users/x/Aulas", raiz: raiz))
    }
}
