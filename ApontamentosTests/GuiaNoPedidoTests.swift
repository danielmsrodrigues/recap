import Foundation
import Testing
@testable import Apontamentos

struct GuiaNoPedidoTests {
    private let transcricao = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now,
                                          segmentos: [Segmento(inicio: 0, fim: 2, texto: "Hola")])
    private let remetida = SeccaoGuia(id: "1.3", titulo: "Clase de empresas", paginaInicio: 7, paginaFim: 13)
    private let mencionada = SeccaoGuia(id: "2.5", titulo: "Clases frecuentes de estructuras organizativas", paginaInicio: 18, paginaFim: 18)

    private func texto(_ b: [BlocoConteudo]) -> String {
        b.compactMap { if case .texto(let t) = $0 { t } else { nil } }.joined(separator: "\n")
    }

    /// Três secções explicadas de 25 000 caracteres: as duas primeiras cabem nos 60 000, a terceira fica só mencionada.
    @Test func montarRespeitaOLimite() throws {
        let indice = IndiceGuia(hash: "h", desvio: 0, seccoes: [
            SeccaoGuia(id: "1", titulo: "A", paginaInicio: 1, paginaFim: 1),
            SeccaoGuia(id: "2", titulo: "B", paginaInicio: 2, paginaFim: 2),
            SeccaoGuia(id: "3", titulo: "C", paginaInicio: 3, paginaFim: 3),
            SeccaoGuia(id: "4", titulo: "D", paginaInicio: 4, paginaFim: 4),
        ])
        let paginas = ["a", "b", "c"].map { String(repeating: $0, count: 25_000) } + ["d"]
        let guia = try #require(GuiaDaAula.montar(indice, paginas: paginas,
                                                  selecao: SelecaoGuia(explicadas: [2, 0, 1], remetidas: [], mencionadas: [3])))
        #expect(guia.partes.map(\.seccao.id) == ["1", "2"])
        #expect(guia.partes.allSatisfy { $0.categoria == .explicada })
        #expect(guia.partes[0].texto.hasPrefix("[p. 1]\naaa"))
        #expect(guia.mencionadas.map(\.id) == ["3", "4"])
        #expect(guia.paginasPermitidas == [1, 2, 3, 4])
    }

    /// Com pouco espaço, a remetida (precisa do texto todo) entra antes das explicadas, e as partes saem pela ordem do índice.
    @Test func remetidasPrimeiroQuandoNaoCabeTudo() throws {
        let indice = IndiceGuia(hash: "h", desvio: 0, seccoes: [
            SeccaoGuia(id: "1", titulo: "A", paginaInicio: 1, paginaFim: 1),
            SeccaoGuia(id: "2", titulo: "B", paginaInicio: 2, paginaFim: 2),
            SeccaoGuia(id: "3", titulo: "C", paginaInicio: 3, paginaFim: 3),
        ])
        let paginas = ["a", "b", "c"].map { String(repeating: $0, count: 25_000) }
        let guia = try #require(GuiaDaAula.montar(indice, paginas: paginas,
                                                  selecao: SelecaoGuia(explicadas: [0, 1], remetidas: [2], mencionadas: [])))
        #expect(guia.partes.map(\.seccao.id) == ["1", "3"])
        #expect(guia.partes.map(\.categoria) == [.explicada, .remetida])
        #expect(guia.mencionadas.map(\.id) == ["2"])
        #expect(guia.semEspaco.map(\.id) == ["2"])
        #expect(guia.idsPermitidos == ["1", "2", "3"])
        #expect(guia.blocoParaPedido().contains("Outras secções tocadas pela aula, sem texto"))
        #expect(!guia.blocoParaPedido().contains("só mencionou"))
    }

    /// As remetidas entram com a sua categoria, pela ordem do índice; sem nada escolhido não há guía.
    @Test func montarComRemetidasESemNada() throws {
        let indice = IndiceGuia(hash: "h", desvio: 1, seccoes: [remetida, mencionada])
        let paginas = (0..<20).map { "pdf \($0 + 1)" }
        let guia = try #require(GuiaDaAula.montar(indice, paginas: paginas, selecao: SelecaoGuia(explicadas: [], remetidas: [0], mencionadas: [1])))
        #expect(guia.partes.map(\.categoria) == [.remetida])
        #expect(guia.partes[0].texto.hasPrefix("[p. 7]\npdf 8"))
        #expect(guia.paginasPermitidas == Set(7...13).union([18]))
        #expect(GuiaDaAula.montar(indice, paginas: paginas, selecao: SelecaoGuia(explicadas: [], remetidas: [], mencionadas: [])) == nil)
    }

    @Test func materiaisComGuia() throws {
        var ctx = ContextoAula(cadeira: "C", titulo: "T", data: .now, glossario: "", transcricao: transcricao,
                               slides: [SlideComImagem(slide: Slide(ficheiro: "s.jpg", inicio: 0, fim: 2), jpeg: Data([1]))])
        ctx.pdfsProfessor = [PDFComDados(pdf: PDFProfessor(numero: 1), dados: Data("%PDF-1.4".utf8))]
        ctx.guia = GuiaDaAula(partes: [.init(seccao: remetida, categoria: .remetida, texto: "[p. 7]\nLa empresa con fines de lucro…")],
                              mencionadas: [mencionada])
        let blocos = NotesGenerator.materiais(ctx)
        let texto = texto(blocos)
        #expect(texto.contains("Guía de estudio da cadeira"))
        #expect(texto.contains("<seccao id=\"1.3\" titulo=\"Clase de empresas\" paginas=\"7–13\" categoria=\"remetida\">\n[p. 7]\nLa empresa con fines de lucro…\n</seccao>"))
        #expect(texto.contains("2.5 Clases frecuentes de estructuras organizativas (p. 18)"))

        // Depois dos PDFs do professor e antes das capturas.
        let guia = try #require(blocos.firstIndex { if case .texto(let t) = $0 { t.hasPrefix("Guía de estudio da cadeira (material oficial)") } else { false } })
        let pdf = try #require(blocos.firstIndex { if case .documentoPDF = $0 { true } else { false } })
        let captura = try #require(blocos.firstIndex { if case .imagem = $0 { true } else { false } })
        #expect(pdf < guia && guia < captura)
    }

    @Test func materiaisSemGuiaComoAntes() {
        let ctx = ContextoAula(cadeira: "C", titulo: "T", data: .now, glossario: "", transcricao: transcricao)
        #expect(!texto(NotesGenerator.materiais(ctx)).contains("Guía de estudio"))
    }

    @Test func promptTemAsRegrasDeFontes() {
        let p = PromptStore.original
        #expect(p.contains("`> 📘 **Guia (<secção>, p. N):** ...`"))
        #expect(p.contains("| Segundo o professor [mm:ss] | Segundo a guia (<secção>, p. N) |"))
        #expect(p.contains("`💡 *Ext.: ...*`"))
        #expect(p.contains("Guia também trata"))
        #expect(p.contains("Lectura obligatoria"))
        #expect(!p.contains("Explicação extra"))
    }

    @Test func rotulos() {
        #expect(RotulosApontamentos.rotulo("Guia", .es) == "Guía")
        #expect(RotulosApontamentos.rotulo("Guia", .en) == "Study guide")
        #expect(RotulosApontamentos.rotulo("Para estudar", .es) == "Para estudiar")
        #expect(PromptStore.original.contains("`**Para estudar:** <a versão>`"))
        #expect(RotulosApontamentos.rotulo("Segundo a guia", .es) == "Según la guía")
        #expect(RotulosApontamentos.rotulo("Explicação extra", .es) == "Explicação extra")
    }
}
