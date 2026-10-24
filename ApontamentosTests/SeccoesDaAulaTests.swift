import Foundation
import Testing
@testable import Apontamentos

struct SeccoesDaAulaTests {
    /// Sete secções como as da guía de Fundamentos (a "6.2" aparece duas vezes, como na guía).
    private var indiceFixture: IndiceGuia {
        IndiceGuia(hash: "h", desvio: 0, seccoes: [
            SeccaoGuia(id: "1", titulo: "La empresa y la actividad empresarial", paginaInicio: 4, paginaFim: 4),
            SeccaoGuia(id: "1.1", titulo: "Fundamentos de las empresas", paginaInicio: 5, paginaFim: 6),
            SeccaoGuia(id: "1.2", titulo: "Principios de la actividad empresarial", paginaInicio: 7, paginaFim: 9),
            SeccaoGuia(id: "1.3", titulo: "Clase de empresas", paginaInicio: 10, paginaFim: 13),
            SeccaoGuia(id: "2", titulo: "Gestión Empresarial", paginaInicio: 14, paginaFim: 51),
            SeccaoGuia(id: "6.2", titulo: "El proceso", paginaInicio: 52, paginaFim: 59),
            SeccaoGuia(id: "6.2", titulo: "Técnicas", paginaInicio: 60, paginaFim: 66),
        ])
    }

    private var transcricaoFixture: Transcricao {
        Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now, segmentos: [
            Segmento(inicio: 0, fim: 2, texto: "Hoy vemos qué es una empresa."),
        ])
    }

    @Test func pedidoNumeraAsSeccoes() {
        let p = SeccoesDaAula.pedido(indiceFixture, transcricao: transcricaoFixture)
        #expect(p.contains("S1: 1 La empresa y la actividad empresarial (p. 4–4)"))
        #expect(p.contains("S6: 6.2 El proceso (p. 52–59)"))
        #expect(p.contains("<transcricao>"))
        #expect(p.contains("Hoy vemos qué es una empresa."))
    }

    @Test func leAResposta() {
        let r = SeccoesDaAula.daResposta(#"```json {"explicadas":["S2","S3"],"remetidas":["S3", 4],"mencionadas":["S9","S5","S5"]} ```"#, total: 7)
        #expect(r == SelecaoGuia(explicadas: [1], remetidas: [2, 3], mencionadas: [4]))
    }

    @Test func leAsChavesTraduzidas() {
        let r = SeccoesDaAula.daResposta(#"{"explicadas":["S1"],"remitidas":["S2"],"mencionadas":["S3"]}"#, total: 7)
        #expect(r == SelecaoGuia(explicadas: [0], remetidas: [1], mencionadas: [2]))
    }

    /// Sem JSON não há seleção (nil): a app avisa em vez de gerar sem guía em silêncio. Um JSON vazio é uma resposta.
    @Test func respostaInvalidaDaNil() {
        #expect(SeccoesDaAula.daResposta("não sei", total: 7) == nil)
        #expect(SeccoesDaAula.daResposta(#"{"explicadas":[],"remetidas":[],"mencionadas":[]}"#, total: 7) == SelecaoGuia(explicadas: [], remetidas: [], mencionadas: []))
        #expect(SeccoesDaAula.sistema.contains("nunca o número da secção"))
    }

    @Test func promptDefineAsTresCategorias() {
        #expect(SeccoesDaAula.sistema.contains("remetidas"))
        #expect(SeccoesDaAula.sistema.contains("no lo vamos a leer"))
    }
}
