import Foundation
import Testing
@testable import Apontamentos

struct ExplicacoesExtraTests {
    private let md = """
    # Clase 1 · Gestión

    ## Niveles de gestión [68:07]
    - **Estratégico:** donde se formulan las estrategias.
    - **Operativo:** la operatividad diaria.

    | Nivel | Qué es |
    |---|---|
    | **Táctico** | Desarrollo de proyectos |

    > 👀 **Solo mencionado:** la matriz DOFA [70:10].

    ## Preguntas de repaso
    1. **¿Qué es el nivel estratégico?**
    """

    /// O Claude vê as linhas numeradas, para responder com o número em vez de copiar o texto.
    @Test func linhasNumeradas() {
        let n = ExplicacoesExtra.numeradas(md)
        #expect(n.contains("L4: - **Estratégico:** donde se formulan las estrategias."))
        #expect(n.contains("L1: # Clase 1 · Gestión"))
    }

    @Test func acrescentaNaMesmaLinhaENumaTabela() {
        let r = ExplicacoesExtra.aplicar([
            .init(linha: 4, explicacao: "Es la dirección: decide hacia dónde va la empresa."),
            .init(linha: 9, explicacao: "Llevar las estrategias a proyectos concretos."),
        ], em: md, lingua: .es)
        let linhas = r.components(separatedBy: "\n")
        #expect(linhas[3] == "- **Estratégico:** donde se formulan las estrategias. 💡 *Ext.: Es la dirección: decide hacia dónde va la empresa.*")
        #expect(linhas[8] == "| **Táctico** | Desarrollo de proyectos 💡 *Ext.: Llevar las estrategias a proyectos concretos.* |")
        // O resto fica igual.
        #expect(linhas.count == md.components(separatedBy: "\n").count)
        #expect(linhas[4] == "- **Operativo:** la operatividad diaria.")
    }

    /// Títulos, caixas 👀, linhas que já têm 💡, o cabeçalho das tabelas e o que vem depois das perguntas de revisão
    /// ficam como estão, tal como números de linha que não existem.
    @Test func naoMexeNoQueNaoDeve() {
        let r = ExplicacoesExtra.aplicar([
            .init(linha: 3, explicacao: "x"),
            .init(linha: 7, explicacao: "x"),
            .init(linha: 8, explicacao: "x"),
            .init(linha: 11, explicacao: "x"),
            .init(linha: 14, explicacao: "x"),
            .init(linha: 99, explicacao: "x"),
        ], em: md, lingua: .es)
        #expect(r == md)
        let ja = ExplicacoesExtra.aplicar([.init(linha: 1, explicacao: "y")], em: "- **A:** b. 💡 *c*", lingua: .es)
        #expect(ja == "- **A:** b. 💡 *c*")
        let daGuia = ExplicacoesExtra.aplicar([.init(linha: 1, explicacao: "y")], em: "- **A:** b. 📘 *Guía (p. 3): c*", lingua: .es)
        #expect(daGuia == "- **A:** b. 📘 *Guía (p. 3): c*")
    }

    /// O que a guía explica leva 📘 com a página, no rótulo da língua dos apontamentos; o resto leva Ext.
    @Test func explicacaoDaGuia() {
        let r = ExplicacoesExtra.aplicar([
            .init(linha: 1, explicacao: "Son las reglas escritas.", fonte: .guia(pagina: 48)),
            .init(linha: 2, explicacao: "Lo de cada día.", fonte: .guia(pagina: nil)),
        ], em: "- **Procedimientos:** los definidos.\n- **Operativo:** la operatividad.", lingua: .es)
        #expect(r == "- **Procedimientos:** los definidos. 📘 *Guía (p. 48): Son las reglas escritas.*\n- **Operativo:** la operatividad. 📘 *Guía: Lo de cada día.*")
        let en = ExplicacoesExtra.aplicar([.init(linha: 1, explicacao: "Rules.", fonte: .guia(pagina: 48))], em: "- **P:** x.", lingua: .en)
        #expect(en == "- **P:** x. 📘 *Study guide (p. 48): Rules.*")
    }

    /// Tolera ``` à volta, chaves traduzidas e explicações com 💡 ou asteriscos a mais.
    @Test func leAResposta() {
        let texto = """
        ```json
        [{"linea": 4, "explicación": "💡 *Es la dirección.*"}, {"line": "9", "explanation": "Proyectos\\nconcretos."}, {"linha": "L12", "explicacao": "Doce."}]
        ```
        """
        #expect(ExplicacoesExtra.daResposta(texto) == [
            .init(linha: 4, explicacao: "Es la dirección."),
            .init(linha: 9, explicacao: "Proyectos concretos."),
            .init(linha: 12, explicacao: "Doce."),
        ])
        #expect(ExplicacoesExtra.daResposta("Nada a acrescentar.").isEmpty)
        let fontes = #"[{"linha":4,"fonte":"guia","pagina":48,"explicacao":"Reglas."},{"linha":"L9","fonte":"ext","explicacao":"Fuera."},{"linha":10,"fonte":"otra","explicacao":"X."}]"#
        #expect(ExplicacoesExtra.daResposta(fontes) == [
            .init(linha: 4, explicacao: "Reglas.", fonte: .guia(pagina: 48)),
            .init(linha: 9, explicacao: "Fuera."),
            .init(linha: 10, explicacao: "X."),
        ])
    }

    /// As explicações saem na língua dos apontamentos, não na das instruções.
    @Test func pedidoDizALingua() {
        let p = ExplicacoesExtra.pedido("- **A:** b.", lingua: .es, guia: nil)
        #expect(p.contains("espanhol de Espanha"))
        #expect(p.contains("L1: - **A:** b."))
        #expect(!p.contains("<seccao"))
    }

    /// Com guía, o pedido leva as secções da aula e diz para as usar antes do conhecimento externo.
    @Test func pedidoComGuia() {
        let s = SeccaoGuia(id: "5.1", titulo: "Tipos de sistemas empresariales", paginaInicio: 47, paginaFim: 48)
        let guia = GuiaDaAula(partes: [.init(seccao: s, categoria: .explicada, texto: "[p. 47]\nProcedimientos…")], mencionadas: [])
        let p = ExplicacoesExtra.pedido("- **A:** b.", lingua: .es, guia: guia)
        #expect(p.contains("<seccao id=\"5.1\""))
        #expect(p.contains("Só usa Ext. quando a guía não explica"))
    }

    @Test func promptPedeSoAsLinhasVagas() {
        #expect(ExplicacoesExtra.sistema.contains("repete a palavra do termo"))
        #expect(ExplicacoesExtra.sistema.contains("👀"))
    }
}

/// O passo de revisão com o Claude a sério, sobre uns apontamentos já feitos. Só com `APONTAMENTOS_AULA=<pasta da aula>`.
struct IntegracaoExplicacoesTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["APONTAMENTOS_AULA"] != nil), .timeLimit(.minutes(10)))
    func acrescentaExplicacoes() async throws {
        let pasta = URL(fileURLWithPath: ProcessInfo.processInfo.environment["APONTAMENTOS_AULA"]!)
        let md = try String(contentsOf: pasta.appending(path: "apontamentos.md"), encoding: .utf8)
        let gerador = NotesGenerator(motor: .claudeCode(ClaudeCodeClient(executavel: try #require(ClaudeCodeClient.localizar()))),
                                     modelo: "claude-sonnet-5-5", esforco: .medium, precos: TabelaPrecos())
        if let bruto = ProcessInfo.processInfo.environment["APONTAMENTOS_RESPOSTA"] {
            let r = try await gerador.gerar(sistema: ExplicacoesExtra.sistema, conteudo: [.texto(ExplicacoesExtra.pedido(md, lingua: .es, guia: nil))],
                                            aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: { _, _, _ in })
            try r.markdown.write(toFile: bruto, atomically: true, encoding: .utf8)
        }
        let r = try await ExplicacoesExtra.rever(md, lingua: .es, guia: nil, gerador: gerador)
        if let saida = ProcessInfo.processInfo.environment["APONTAMENTOS_SAIDA"] {
            try r.markdown.write(toFile: saida, atomically: true, encoding: .utf8)
        }
        #expect(r.markdown.components(separatedBy: "💡").count > md.components(separatedBy: "💡").count)
    }
}
