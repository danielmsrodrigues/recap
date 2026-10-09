import Foundation
import Testing
@testable import Apontamentos

struct EstudoTests {
    @Test func pesquisaIgnoraMaiusculasEAcentos() {
        #expect(Pesquisa.contem("La diagonalización de matrices", ["DIAGONALIZACION", "matrices"]))
        #expect(!Pesquisa.contem("La diagonalización de matrices", ["diagonalizacion", "vectores"]))
        let texto = "Hoy vamos a ver la diagonalización de una matriz cuadrada"
        let r = Pesquisa.realces(texto, ["diagonalizacion"])
        #expect(r.map { String(texto[$0]) } == ["diagonalización"])
    }

    @Test func trechoCortaAVoltaDaPalavra() {
        let longo = String(repeating: "relleno ", count: 30) + "autovalor" + String(repeating: " más", count: 30)
        let t = Pesquisa.trecho(longo, ["autovalor"])
        #expect(t.contains("autovalor"))
        #expect(t.hasPrefix("…") && t.hasSuffix("…"))
        #expect(t.count <= 142)
        #expect(Pesquisa.limparMarkdown("> **Definição — valor próprio.** $Av = \\lambda_{1} v$") == "Definição — valor próprio. Av = λ1 v")
        #expect(Pesquisa.termosParaRealcar("o polinómio característico de A é det(A - λI)", ["polinomio"])
                == ["polinómio característico de A é det", "polinómio"])
    }

    @Test func pesquisaEncontraNosFicheiros() async throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "pesquisa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        try Disco.escreverApontamentos("# Aula\n\n## Resumo\nValores próprios e diagonalização.\n", em: pasta)
        let t = Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                            segmentos: [Segmento(inicio: 42, fim: 50, texto: "Calculamos los autovalores de la matriz.")])
        try Disco.encoder.encode(t).write(to: pasta.appending(path: Disco.transcricaoJSON))
        let aula = Pesquisa.AulaRef(pasta: pasta, titulo: "Tema 3", cadeira: "Álgebra", data: .now)

        let notas = await Pesquisa.procurar("diagonalizacao", em: [aula])
        #expect(notas.map(\.onde) == [.apontamentos])
        let fala = await Pesquisa.procurar("autovalores matriz", em: [aula])
        #expect(fala.map(\.onde) == [.transcricao(42)])
        #expect(await Pesquisa.procurar("tema 3", em: [aula]).map(\.onde) == [.titulo])
    }

    @Test func esqueletoTemResumoETitulos() {
        let md = """
        # Tema 3

        ## Resumo
        Diagonalização de matrizes.

        ## Valores próprios [02:10]
        Texto longo que não interessa.

        ### Exemplo: matriz 2×2 [10:00]
        Mais texto.
        """
        #expect(Estudo.esqueleto(md) == "## Resumo\nDiagonalização de matrizes.\n## Valores próprios [02:10]\n### Exemplo: matriz 2×2 [10:00]")
    }

    @Test func ligacoesDaRespostaDoClaude() throws {
        let resposta = """
        ```json
        {"ligacoes": [
          {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio"], "explicacao": "Vem da aula 1.", "momento": "[00:17]"},
          {"aula": "A9", "direcao": "anterior", "conceitos": [], "explicacao": "Id que não existe.", "momento": null},
          {"aula": "A2", "direcao": "seguinte", "conceitos": ["PDP⁻¹"], "explicacao": "Continua.", "momento": "não sei"},
          {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio", "gradiente"], "explicacao": "E mais.", "momento": "01:26"}
        ],
         "temas_comuns": [{"tema": "Gradiente", "aulas": ["A1", "A7"], "explicacao": "Nas duas."}]}
        ```
        """
        let l = try LigacoesAula.daResposta(resposta, aulas: ["A1": "Álgebra/aula1", "A2": "Álgebra/aula2"])
        #expect(l.ligacoes.map(\.aula) == ["Álgebra/aula1", "Álgebra/aula2"])
        #expect(l.ligacoes.map(\.momento) == ["00:17", nil])
        #expect(l.ligacoes.last?.direcao == .seguinte)
        #expect(l.ligacoes.first?.conceitos == ["valor próprio", "gradiente"])
        #expect(l.ligacoes.first?.explicacao == "Vem da aula 1. E mais.")
        #expect(l.temas.first?.aulas == ["Álgebra/aula1"])
        #expect(throws: ErroLigacoes.self) { try LigacoesAula.daResposta("Não há ligações.", aulas: [:]) }
    }

    @Test func perguntasGuardadas() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "perguntas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        #expect(Disco.lerPerguntas(pasta).isEmpty)
        try Disco.escreverPerguntas([PerguntaAula(pergunta: "O que é $\\lambda$?", resposta: "Um valor próprio.")], em: pasta)
        #expect(Disco.lerPerguntas(pasta).map(\.pergunta) == ["O que é $\\lambda$?"])
        try Disco.escreverPerguntas([], em: pasta)
        #expect(!FileManager.default.fileExists(atPath: pasta.appending(path: Disco.perguntasJSON).path))
    }
}
