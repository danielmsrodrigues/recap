import Foundation
import Testing
@testable import Apontamentos

/// "Ouvir": os apontamentos lidos em voz alta, sem a voz dizer "asterisco", "aspas" ou "cardinal".
struct TextoFaladoTests {
    private let md = """
    # Clase 3 · Cadenas, input y conversiones

    ## Resumen
    Se ven las **cadenas de texto** (`str`) y la función `input()`. [12:34]

    ## Concatenación [05:10]
    - Se usa el operador `+`: "hola" + "mundo".
    - Con *f-strings* es más cómodo: «f"Hola {nombre}"».
    1. Primer paso.
    2. Segundo paso

    > 💡 *Ext.:* una cadena es una secuencia de caracteres.
    > 🤔 **Não percebeste aqui [07:20]:** o `+` junta duas cadenas.

    ![Slide 4 — Concatenación](slide:4)

    | Tipo | Ejemplo |
    |------|---------|
    | str  | "hola"  |

    Ver [la sección anterior](#resumen) y $x^2 + 1$.

    ```python
    print("hola")
    ```

    $$
    \\frac{a}{b}
    $$
    """

    private var trechos: [TextoFalado.Trecho] { TextoFalado.trechos(md) }
    private var tudo: String { trechos.map { ($0.titulo ?? "") + " " + $0.texto }.joined(separator: " ") }

    @Test func naoFicaNenhumSimboloDoMarkdown() {
        for simbolo in ["*", "#", "`", "\"", "«", "»", "|", "[", "]", "(", ")", ">", "_", "$", "\\", "{", "}", "💡", "🤔", "—"] {
            #expect(!tudo.contains(simbolo), "ficou \(simbolo) no texto falado")
        }
    }

    @Test func umTrechoPorSeccaoComOTitulo() {
        #expect(trechos.map(\.titulo) == [nil, "Resumen", "Concatenación"])
        #expect(trechos[1].texto.hasPrefix("Se ven las cadenas de texto"))
    }

    @Test func asLigacoesFicamSoComOTextoEOsMinutosSaem() {
        #expect(tudo.contains("Ver la sección anterior"))
        #expect(!tudo.contains("12:34"))
        #expect(!tudo.contains("resumen)"))
    }

    @Test func imagensCodigoEFormulasEmBlocoNaoSeLeem() {
        #expect(!tudo.contains("Slide 4"))
        #expect(!tudo.contains("print"))
        #expect(!tudo.contains("frac"))
    }

    @Test func listasETabelasViramFrases() {
        let t = trechos[2].texto
        #expect(t.contains("Primer paso."))
        #expect(t.contains("Segundo paso."))
        #expect(t.contains("str, hola."))
    }

    @Test func asCaixasLeemSeSemOEmoji() {
        let t = trechos[2].texto
        #expect(t.contains("Ext.: una cadena es una secuencia de caracteres."))
        #expect(t.contains("Não percebeste aqui: o + junta duas cadenas."))
    }

    @Test func aVozDaLinguaDosApontamentos() {
        #expect(TextoFalado.idiomaVoz(.es) == "es-ES")
        #expect(TextoFalado.idiomaVoz(.ptPT) == "pt-PT")
    }
}
