import AppKit
import SwiftUI
import Testing
@testable import Apontamentos

@MainActor
struct FluxoTests {
    /// A largura que o `Fluxo` pede quando lhe dão `largura` pontos.
    private func largura(_ fluxo: some View, em largura: CGFloat) -> CGFloat {
        NSHostingController(rootView: fluxo).sizeThatFits(in: CGSize(width: largura, height: 1000)).width
    }

    @Test func umaEtiquetaMaiorDoQueALinhaNaoAlargaOPainel() {
        // No iPhone, uma etiqueta com o título comprido de uma aula alargava as Ligações para lá do ecrã.
        let fluxo = Fluxo {
            Text("Clase 1 · Programar, lenguajes, ejecución y entorno de trabajo").lineLimit(1)
            Text("Clase 2").lineLimit(1)
        }
        #expect(largura(fluxo, em: 120) <= 120)
    }

    @Test func etiquetasCurtasFicamNaMesmaLinha() {
        let fluxo = Fluxo(espaco: 6) {
            Text("a").frame(width: 30)
            Text("b").frame(width: 30)
        }
        #expect(largura(fluxo, em: 200) == 66)
    }
}
