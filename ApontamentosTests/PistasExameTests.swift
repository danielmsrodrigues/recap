import Foundation
import Testing
@testable import Apontamentos

/// "Sai no exame": o que o professor disse que entra no exame, com o minuto da aula.
struct PistasExameTests {
    @Test func leAsPistasDaResposta() throws {
        let resposta = """
        Aqui está:
        ```json
        [{"tempo": "12:34", "citacao": "Esto entra seguro en el examen", "descricao": "Passar um decimal periódico a fração"},
         {"tempo": "62:05", "citacao": "Lo pregunto siempre", "descricao": "Propriedade distributiva"}]
        ```
        """
        let pistas = try #require(PistasExame.daResposta(resposta))
        #expect(pistas.map(\.tempo) == [754, 3725])
        #expect(pistas[0].citacao == "Esto entra seguro en el examen")
        #expect(pistas[1].descricao == "Propriedade distributiva")
    }

    @Test func toleraChavesTraduzidasEDescartaOQueNaoTemTempo() {
        let resposta = #"[{"tiempo":"05:00","cita":"Ojo, esto cae","descripcion":"Intervalos"},{"cita":"sin tiempo","descripcion":"x"}]"#
        let pistas = PistasExame.daResposta(resposta)
        #expect(pistas == [PistasExame.Pista(tempo: 300, citacao: "Ojo, esto cae", descricao: "Intervalos")])
    }

    @Test func semPistasDaListaVazia() {
        #expect(PistasExame.daResposta("[]") == [])
    }

    /// Uma resposta que não se lê não é "nada sai no exame": senão a aula ficava marcada como vista para sempre.
    @Test func respostaQueNaoSeLeDaNil() {
        #expect(PistasExame.daResposta("Não encontrei nada.") == nil)
        #expect(PistasExame.daResposta(#"[{"tempo": "01:00", "citacao": "cortad"#) == nil)
    }

    @Test func umParentesesRetoAntesDaListaNaoAEstraga() {
        let resposta = #"Encontrei [2] momentos: [{"tempo":"01:00","citacao":"Esto cae","descricao":"x"}]"#
        #expect(PistasExame.daResposta(resposta)?.map(\.tempo) == [60])
    }

    @Test func oPedidoLevaATranscricaoComOsMinutosEALingua() {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 60, criadaEm: .now,
                            segmentos: [Segmento(inicio: 754, fim: 760, texto: "Esto entra en el examen.", orador: .professor)])
        let pedido = PistasExame.pedido(t, lingua: .es)
        #expect(pedido.contains("[12:34] Esto entra en el examen."))
        #expect(pedido.contains(LinguaApontamentos.es.nomeNoPrompt))
    }

    @Test func guardaELeAsPistasDaAulaMesmoSemNenhuma() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "pistas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        #expect(Disco.lerPistasExame(pasta) == nil)
        // Uma aula já vista sem pistas fica com a lista vazia: não volta a ser procurada.
        try Disco.escreverPistasExame([], em: pasta)
        #expect(Disco.lerPistasExame(pasta) == [])
        let p = PistasExame.Pista(tempo: 90, citacao: "c", descricao: "d")
        try Disco.escreverPistasExame([p], em: pasta)
        #expect(Disco.lerPistasExame(pasta) == [p])
    }

    @Test func juntaAsPistasPorCadeiraEPelaOrdemDasAulas() {
        func aula(_ titulo: String, _ cadeira: String, dia: Int) -> Aula {
            Aula(pasta: URL(filePath: "/aulas/\(cadeira)/\(titulo)"), cadeira: cadeira,
                 meta: AulaMeta(titulo: titulo, data: Date(timeIntervalSince1970: Double(dia) * 86_400), video: nil),
                 temTranscricao: true, temApontamentos: true, temSlides: false)
        }
        let a1 = aula("A1", "Cálculo", dia: 1), a2 = aula("A2", "Cálculo", dia: 8), b1 = aula("B1", "Gestão", dia: 2)
        let cadeiras = [Cadeira(nome: "Cálculo", pasta: URL(filePath: "/aulas/Cálculo"), meta: CadeiraMeta(), aulas: [a2, a1], semestre: Semestre(ano: 1, numero: 1)),
                        Cadeira(nome: "Gestão", pasta: URL(filePath: "/aulas/Gestão"), meta: CadeiraMeta(), aulas: [b1], semestre: Semestre(ano: 1, numero: 1))]
        let pistas: [String: [PistasExame.Pista]] = [
            "A1": [.init(tempo: 600, citacao: "x", descricao: "Tema 1b"), .init(tempo: 60, citacao: "y", descricao: "Tema 1a")],
            "A2": [.init(tempo: 30, citacao: "z", descricao: "Tema 2")],
        ]
        let grupos = PistasExame.porCadeira(cadeiras) { pistas[$0.lastPathComponent] }
        #expect(grupos.map(\.cadeira.nome) == ["Cálculo"])
        #expect(grupos[0].pistas.map(\.pista.descricao) == ["Tema 1a", "Tema 1b", "Tema 2"])
        #expect(grupos[0].pistas.map(\.aula.meta.titulo) == ["A1", "A1", "A2"])
    }
}
