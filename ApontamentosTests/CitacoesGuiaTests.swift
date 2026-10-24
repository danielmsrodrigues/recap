import Foundation
import Testing
@testable import Apontamentos

struct CitacoesGuiaTests {
    /// Uma página citada da guía que não estava nas secções enviadas fica marcada; o resto não muda.
    @Test func marcaPaginasForaDasSeccoes() {
        let md = "> 📘 **Guía (1.3, p. 7):** a\n- x 📘 *Guía (p. 99): b*\n- *(Guía 2.4, p. 18)*\n- Pág. 99 de otra cosa"
        let r = CitacoesGuia.verificar(md, paginas: [7, 8, 18])
        #expect(r.invalidas == 1)
        #expect(r.markdown.contains("📘 *Guía (p. 99, página por confirmar): b*"))
        #expect(r.markdown.contains("> 📘 **Guía (1.3, p. 7):** a"))
        #expect(r.markdown.contains("- *(Guía 2.4, p. 18)*"))
        #expect(r.markdown.hasSuffix("- Pág. 99 de otra cosa"))
    }

    @Test func intervalosContamComoValidos() {
        #expect(CitacoesGuia.verificar("(Guía 1.3, p. 7–8)", paginas: [7, 8]).invalidas == 0)
        #expect(CitacoesGuia.verificar("(Guía 1.3, pp. 7–9)", paginas: [7, 8]).invalidas == 1)
        let r = CitacoesGuia.verificar("(Guía 1.3, p. 7–9)", paginas: [7, 8])
        #expect(r.invalidas == 1)
        #expect(r.markdown == "(Guía 1.3, p. 7–9, página por confirmar)")
    }

    /// Nas tabelas de divergência e nas outras línguas.
    @Test func tabelasELinguas() {
        let md = "| Según la profesora [01:12] | Según la guía (1.2, p. 5) |\n- Study guide (p. 40): x\n- (Slide 3 · Guía 1.1, p. 4)"
        let r = CitacoesGuia.verificar(md, paginas: [5])
        #expect(r.invalidas == 2)
        #expect(r.markdown.contains("Según la guía (1.2, p. 5) |"))
        #expect(r.markdown.contains("Study guide (p. 40, página por confirmar)"))
        #expect(r.markdown.contains("Guía 1.1, p. 4, página por confirmar)"))
    }
}
