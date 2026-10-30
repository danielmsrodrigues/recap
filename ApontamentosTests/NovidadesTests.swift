import Foundation
import Testing
@testable import Apontamentos

/// "O que há de novo": as notas de cada versão, e as que ainda não se viram depois de uma atualização.
struct NovidadesTests {
    private let lista = [
        Novidades.Versao(numero: "1.13", data: "30 out 2026", itens: ["c"]),
        Novidades.Versao(numero: "1.12", data: "30 out 2026", itens: ["b"]),
        Novidades.Versao(numero: "1.9", data: "27 out 2026", itens: ["a"]),
    ]

    @Test func asVersoesComparamSePeloNumeroENaoPeloTexto() {
        #expect(Novidades.menor("1.9", "1.12"))
        #expect(Novidades.menor("1.12", "1.13"))
        #expect(!Novidades.menor("1.13", "1.13"))
        #expect(Novidades.menor("1.13", "1.13.1"))
    }

    @Test func depoisDeAtualizarMostraSoAsQueAindaNaoSeViram() {
        let porVer = Novidades.porVer(lista, ultimaVista: "1.9", atual: "1.13")
        #expect(porVer.map(\.numero) == ["1.13", "1.12"])
    }

    @Test func naPrimeiraVezNaoMostraNada() {
        // Quem instala agora não precisa da lista de tudo o que mudou antes.
        #expect(Novidades.porVer(lista, ultimaVista: nil, atual: "1.13").isEmpty)
    }

    @Test func naMesmaVersaoNaoMostraNada() {
        #expect(Novidades.porVer(lista, ultimaVista: "1.13", atual: "1.13").isEmpty)
    }

    @Test func aListaDaAppEstaPorOrdemComAMaisRecentePrimeiro() {
        let numeros = Novidades.todas.map(\.numero)
        #expect(numeros == numeros.sorted { Novidades.menor($1, $0) })
        #expect(Novidades.todas.allSatisfy { !$0.itens.isEmpty })
    }
}
