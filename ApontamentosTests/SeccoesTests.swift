import Foundation
import Testing
@testable import Apontamentos

/// Âncoras das secções dos apontamentos e os links `[Título](#ancora)` das respostas do painel das perguntas.
@MainActor
struct SeccoesTests {
    private let notas = """
        # Aula 1 · Conceito de empresa

        ## Resumo
        Texto do resumo.

        ## O que é uma empresa [00:00]

        ### Definição tradicional [00:00]

        ### Valor **não** é o mesmo que benefício [03:01]

        ```python
        # isto é um comentário, não um título
        ```

        ### Exemplo: Amazon, que setor? [23:01]

        ## Valores próprios $\\lambda_1$ [41:20] ##

        #semespaco não é título

        > ## Dentro de uma citação também não

        ### Exemplo: Amazon, que setor? [52:00]
        """

    @Test func listaOsTitulosPelaOrdem() {
        let s = Seccoes.lista(notas)
        #expect(s.map(\.titulo) == [
            "Aula 1 · Conceito de empresa", "Resumo", "O que é uma empresa", "Definição tradicional",
            "Valor não é o mesmo que benefício", "Exemplo: Amazon, que setor?", "Valores próprios λ1",
            "Exemplo: Amazon, que setor?",
        ])
        #expect(s.map(\.nivel) == [1, 2, 2, 3, 3, 3, 2, 3])
        #expect(s.map(\.indice) == Array(0..<8))
    }

    @Test func ancorasSemAcentosEUnicas() {
        let s = Seccoes.lista(notas)
        #expect(s.map(\.ancora) == [
            "aula-1-conceito-de-empresa", "resumo", "o-que-e-uma-empresa", "definicao-tradicional",
            "valor-nao-e-o-mesmo-que-beneficio", "exemplo-amazon-que-setor", "valores-proprios-1",
            "exemplo-amazon-que-setor-2",
        ])
        #expect(Seccoes.ancora("Ação & Reação — Ñandú") == "acao-reacao-nandu")
        #expect(Seccoes.ancora("  --  ").isEmpty)
    }

    @Test func indiceParaOClaude() {
        let s = Seccoes.lista("## Resumo\n### Definição tradicional [00:00]\n## Avisos")
        #expect(Seccoes.indice(s) == """
            - [Resumo](#resumo)
              - [Definição tradicional](#definicao-tradicional)
            - [Avisos](#avisos)
            """)
    }

    @Test func resolveAAncoraExata() {
        let s = Seccoes.lista(notas)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#definicao-tradicional", texto: "Definição tradicional"), em: s)?.indice == 3)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "exemplo-amazon-que-setor-2", texto: "x"), em: s)?.indice == 7)
        // Com acentos e maiúsculas (como o GitHub as faria) ou percent-encoding (como vêm do marked).
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#O-que-é-uma-empresa", texto: ""), em: s)?.indice == 2)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#o-que-%C3%A9-uma-empresa", texto: ""), em: s)?.indice == 2)
    }

    @Test func resolvePeloTextoOuAproximado() {
        let s = Seccoes.lista(notas)
        // Âncora errada, mas o texto do link é o título.
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#seccao-3", texto: "Definição tradicional [00:00]"), em: s)?.indice == 3)
        // Título que mudou um pouco desde a resposta: contém a âncora como palavras inteiras.
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#valores-proprios", texto: "Valores próprios"), em: s)?.indice == 6)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#resumo-da-aula", texto: ""), em: s)?.indice == 1)
        // Só palavras inteiras: "empresa" não chega a "empresas…" nem a parte de uma palavra.
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#presa", texto: ""), em: s) == nil)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#redes-neuronais", texto: "Redes neuronais"), em: s) == nil)
        #expect(Seccoes.resolver(LigacaoSeccao(ancora: "#", texto: ""), em: s) == nil)
    }

    @Test func pedidoDasPerguntasLevaAsSeccoes() {
        #expect(Estudo.sistemaPerguntas.contains("(#cadeia-de-valor)"))
    }
}
