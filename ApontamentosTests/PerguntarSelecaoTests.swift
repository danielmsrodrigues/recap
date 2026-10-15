import AppKit
import Foundation
import Testing
@testable import Apontamentos

/// Perguntar sobre um trecho selecionado nos apontamentos ou na transcrição.
@MainActor
struct PerguntarSelecaoTests {
    private let notas = CitacaoPergunta(texto: "> **Valor próprio.** $Av = \\lambda v$", origem: .apontamentos)
    private let fala = CitacaoPergunta(texto: "el determinante tiene que ser cero", origem: .transcricao, inicio: 754)

    @Test func semPerguntaExplicaOTrecho() {
        #expect(Estudo.pergunta("  ", citacao: nil) == nil)
        #expect(Estudo.pergunta("\n", citacao: notas) == Estudo.perguntaSobreTrecho)
        #expect(Estudo.pergunta(" Porquê o λ? ", citacao: notas) == "Porquê o λ?")
        #expect(Estudo.pergunta("O que é?", citacao: nil) == "O que é?")
    }

    @Test func pedidoLevaOTrechoAntesDaPergunta() {
        #expect(Estudo.pedido("O que é?", citacao: nil) == "O que é?")
        #expect(Estudo.pedido("Porquê o λ?", citacao: notas) == """
            Sobre este trecho dos apontamentos:

            <trecho>
            > **Valor próprio.** $Av = \\lambda v$
            </trecho>

            Porquê o λ?
            """)
        // Da transcrição vai também o momento, para o Claude encontrar o contexto.
        #expect(Estudo.pedido(Estudo.perguntaSobreTrecho, citacao: fala) == """
            Sobre este trecho da transcrição, dito aos [12:34]:

            <trecho>
            el determinante tiene que ser cero
            </trecho>

            Explica este trecho
            """)
    }

    @Test func trechoLongoECortadoNumaPalavra() {
        let longo = CitacaoPergunta(texto: String(repeating: "autovalor ", count: 400), origem: .transcricao, inicio: 1)
        let c = longo.cortado()
        #expect(c.texto.count <= CitacaoPergunta.limite + 1)
        #expect(c.texto.hasSuffix("autovalor…"))
        #expect(c.inicio == 1)
        #expect(fala.cortado() == fala)
        #expect(longo.cortado(300).texto.count <= 301)
    }

    @Test func legendaETextoParaMostrar() {
        #expect(notas.legenda == "Apontamentos")
        #expect(fala.legenda == "Transcrição · [12:34]")
        #expect(notas.textoLimpo == "Valor próprio. Av = λ v")
    }

    @Test func perguntaAntigaSemTrechoContinuaALer() throws {
        let json = #"[{"id":"5D1C5B7E-2D7B-4E0A-9C1E-3F1B2A4C5D6E","pergunta":"O que é?","resposta":"Isto.","data":"2026-10-14T10:00:00Z"}]"#
        let lidas = try Disco.decoder.decode([PerguntaAula].self, from: Data(json.utf8))
        #expect(lidas.first?.citacao == nil)
        let nova = PerguntaAula(pergunta: "E isto?", resposta: "Aquilo.", citacao: fala)
        let volta = try Disco.decoder.decode(PerguntaAula.self, from: Disco.encoder.encode(nova))
        #expect(volta.citacao == fala)
    }

    @Test func selecaoNaTranscricaoTiraTemposEEtiquetas() {
        let segmentos = [
            Segmento(inicio: 60, fim: 65, texto: " Vamos a calcular los autovalores."),
            Segmento(inicio: 65, fim: 70, texto: "¿Y si la matriz no es cuadrada?", orador: .aluno),
            Segmento(inicio: 70, fim: 80, texto: "Entonces no tiene autovalores."),
        ]
        let (texto, faixas) = TextoTranscricao.construir(segmentos, indices: [0, 1, 2])
        let s = texto.string as NSString
        #expect(texto.string.hasPrefix("01:00\tVamos a calcular"))
        #expect(s.substring(with: faixas[1].texto) == "¿Y si la matriz no es cuadrada?")
        #expect(faixas[1].etiqueta.map(s.substring) == " Aluno ")

        // Do meio do primeiro segmento ao meio do terceiro, a passar pelo tempo e pela etiqueta do aluno.
        let de = s.range(of: "los autovalores").location
        let ate = NSMaxRange(s.range(of: "Entonces no"))
        let c = TextoTranscricao.citacao(texto.string, faixas: faixas, segmentos: segmentos, selecao: NSRange(location: de, length: ate - de))
        #expect(c == CitacaoPergunta(texto: "los autovalores. ¿Y si la matriz no es cuadrada? Entonces no", origem: .transcricao, inicio: 60))

        // Só o tempo (sem nada dito) não dá para perguntar.
        let soTempo = s.range(of: "01:10")
        #expect(TextoTranscricao.citacao(texto.string, faixas: faixas, segmentos: segmentos, selecao: soTempo) == nil)
    }

    @Test func selecaoComPesquisaUsaOMomentoDoSegmentoCerto() {
        let segmentos = [
            Segmento(inicio: 5, fim: 9, texto: "Hola a todos."),
            Segmento(inicio: 600, fim: 610, texto: "La matriz inversa existe si el determinante no es cero."),
        ]
        // Com a pesquisa a mostrar só o segundo segmento.
        let (texto, faixas) = TextoTranscricao.construir(segmentos, indices: [1])
        let r = (texto.string as NSString).range(of: "determinante")
        #expect(TextoTranscricao.citacao(texto.string, faixas: faixas, segmentos: segmentos, selecao: r)
                == CitacaoPergunta(texto: "determinante", origem: .transcricao, inicio: 600))
    }
}
