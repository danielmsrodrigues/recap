import Foundation
import Testing
@testable import Apontamentos

@MainActor
struct LinguaApontamentosTests {
    private func aplicar(_ texto: String, _ lingua: LinguaApontamentos, idioma: IdiomaAula = .espanhol) -> String {
        ContextoCurso.aplicar(texto, idioma: idioma, contexto: "mestrado em Gestão", apontamentos: lingua)
    }

    @Test func ptPTComoAntes() {
        let p = aplicar(PromptStore.original, .ptPT)
        #expect(!p.contains("{{"))
        #expect(p.contains("## Língua\n- Escreve tudo em português europeu (PT-PT), nunca em português do Brasil: \"ficheiro\""))
        #expect(p.contains("\n- Mantém em inglês os termos que se usam assim em português (\"overfitting\""))
        #expect(!p.contains("escrevem-se assim"))
        #expect(p.contains("""
            ## Glossário (espanhol → português)
            | Original | Português | Nota |
            |---|---|---|
            Os termos técnicos da matéria que apareceram na aula (não os da logística, como "época de exames").
            """))
        // Sem a língua dos apontamentos, como até aqui.
        #expect(ContextoCurso.aplicar("{{regras_lingua}}", idioma: .espanhol, contexto: "") == LinguaApontamentos.ptPT.regras)
    }

    @Test func apontamentosEmIngles() {
        let p = aplicar(PromptStore.original, .en)
        #expect(!p.contains("{{"))
        #expect(p.contains("- Escreve tudo em inglês, embora estas instruções estejam em português."))
        #expect(p.contains(#""Sobre a cadeira" → "About the course""#))
        #expect(p.contains(#""Resolução" → "Solution""#))
        #expect(!p.contains("ficheiro"))
        #expect(p.contains("## Glossary (Spanish → English)\n| Original | English | Note |"))
    }

    @Test func glossarioSemTraducaoNaMesmaLingua() {
        #expect(LinguaApontamentos.ptPT.seccaoGlossario(aulas: .portugues).hasPrefix("## Glossário\n| Termo | Significado |"))
        #expect(LinguaApontamentos.en.seccaoGlossario(aulas: .ingles).hasPrefix("## Glossary\n| Term | Meaning |"))
        #expect(LinguaApontamentos.es.seccaoGlossario(aulas: .espanhol).hasPrefix("## Glosario\n| Término | Significado |"))
        #expect(LinguaApontamentos.ptPT.seccaoGlossario(aulas: .ingles).hasPrefix("## Glossário (inglês → português)"))
    }

    @Test func ptBRSoTraduzOQueMuda() {
        let p = aplicar(PromptStore.original, .ptBR)
        #expect(p.contains("português do Brasil (PT-BR)"))
        #expect(p.contains(#""Sobre a cadeira" → "Sobre a disciplina""#))
        #expect(!p.contains(#""Resumo" →"#))
    }

    @Test func promptsDoEstudoEDaFicha() {
        for sistema in [Estudo.sistemaPerguntas, Estudo.sistemaExercicios, Estudo.sistemaLigacoes, FichaCadeira.sistema] {
            #expect(!sistema.contains("PT-PT"))
            #expect(!sistema.contains("Português de Portugal"))
            let p = aplicar(sistema, .es)
            #expect(!p.contains("{{"))
            #expect(p.contains("espanhol de Espanha"))
        }
    }

    @Test func sobreACadeiraEmQualquerLingua() {
        for titulo in ["About the course", "Sobre la asignatura", "Sobre a disciplina", "Sobre a cadeira"] {
            let (apontamentos, sobre) = FichaCadeira.separar("# Tema\n\n## \(titulo)\n- Exam: 40 %\n\n## Matrices [00:10]\nX")
            #expect(sobre == "- Exam: 40 %")
            #expect(apontamentos == "# Tema\n\n## Matrices [00:10]\nX")
        }
        #expect(FichaCadeira.limpar("## Exam\n- 40 %", titulo: "About the course") == "# About the course\n\n## Exam\n- 40 %\n")
    }

    @Test func resumoParaAsLigacoesEmQualquerLingua() {
        #expect(Estudo.esqueleto("# Tema\n\n## Summary\nMatrices and eigenvalues.\n\n## Eigenvalues [01:00]\nX") ==
                "## Summary\nMatrices and eigenvalues.\n## Eigenvalues [01:00]")
        #expect(Estudo.esqueleto("# Tema\n## Resumen\nMatrices.\n## Autovalores\nX") == "## Resumen\nMatrices.\n## Autovalores")
    }

    @Test func rotulosETitulos() {
        #expect(RotulosApontamentos.rotulo("Aula", .en) == "Lecture")
        #expect(RotulosApontamentos.rotulo("Não existe", .en) == "Não existe")
        #expect(RotulosApontamentos.todas("Resumo") == ["Resumo", "Resumen", "Summary"])
        #expect(RotulosApontamentos.instrucao(.ptPT) == nil)
        #expect(TituloAula.titulo(numero: 3, tema: "Matrices", aula: "Lecture") == "Lecture 3 · Matrices")
        #expect(TituloAula.tema("# Lecture 3 · Matrices") == "Matrices")
        #expect(TituloAula.tema("# Classes of firms") == "Classes of firms")
    }
}
