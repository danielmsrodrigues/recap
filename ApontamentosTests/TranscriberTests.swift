import Testing
@testable import Apontamentos

struct TranscriberTests {
    @Test func promptSoComTermosEmEspanhol() {
        let g = """
        autovalor = valor próprio
        - matriz → matriz
        descenso del gradiente -> descida do gradiente

        sobreajuste | overfitting
        """
        #expect(Transcriber.promptDoGlossario(g) == "Glosario: autovalor, matriz, descenso del gradiente, sobreajuste.")
        #expect(Transcriber.promptDoGlossario("  \n ") == "")
    }

    @Test func limpezaTiraAlucinacoesERepeticoes() {
        let s = Transcriber.limpar([
            Segmento(inicio: 10, fim: 12, texto: " La derivada. "),
            Segmento(inicio: 0, fim: 5, texto: "Buenos días."),
            Segmento(inicio: 12, fim: 14, texto: "La derivada."),
            Segmento(inicio: 20, fim: 25, texto: "Subtítulos realizados por la comunidad de Amara.org"),
            Segmento(inicio: 30, fim: 31, texto: "   "),
            Segmento(inicio: 16, fim: 17, texto: "Gracias."),
        ])
        #expect(s == [
            Segmento(inicio: 0, fim: 5, texto: "Buenos días."),
            Segmento(inicio: 10, fim: 14, texto: "La derivada."),
        ])
    }
}
