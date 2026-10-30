import SwiftUI

/// Cadeira, título e data de uma aula: o mesmo formulário para importar um vídeo, transcrever em direto e editar.
struct DadosAula {
    /// O nome de uma cadeira existente, ou `novaCadeiraTag` para a escrever à mão.
    var cadeira = ""
    var novaCadeira = ""
    var titulo = ""
    var data = Date.now
    /// O último título proposto ("Aula 4"): muda com a cadeira enquanto não for escrito outro.
    var tituloSugerido = ""

    static let novaCadeiraTag = "\u{0}nova"

    var nomeCadeira: String {
        (cadeira == Self.novaCadeiraTag ? novaCadeira : cadeira).trimmingCharacters(in: .whitespaces)
    }

    var tituloLimpo: String { titulo.trimmingCharacters(in: .whitespaces) }

    var valido: Bool { !nomeCadeira.isEmpty && !tituloLimpo.isEmpty }

    /// O que ainda falta preencher, ou nil.
    var falta: String? {
        if nomeCadeira.isEmpty { return "Falta o nome da cadeira" }
        if tituloLimpo.isEmpty { return "Falta o título da aula" }
        return nil
    }

    /// Com o título vazio (ou ainda o proposto), propõe "Aula N" a seguir à última aula da cadeira.
    @MainActor
    mutating func sugerirTitulo(library: Library) {
        guard tituloLimpo.isEmpty || titulo == tituloSugerido else { return }
        let sugestao = TituloAula.proximo(library.cadeira(nome: nomeCadeira)?.aulas ?? [])
        titulo = sugestao
        tituloSugerido = sugestao
    }

    /// Começa na última cadeira usada, senão na primeira da lista, senão a escrever uma nova.
    @MainActor
    mutating func escolherCadeira(library: Library, ultima: String) {
        if library.cadeira(nome: ultima) != nil { cadeira = ultima }
        else if let primeira = library.cadeirasPorSemestre.first?.cadeiras.first { cadeira = primeira.nome }
        else { cadeira = Self.novaCadeiraTag }
    }
}

/// As linhas do formulário; vai dentro de um `Form` (para o chamador poder juntar as suas).
struct FormularioAula: View {
    @Environment(Library.self) private var library
    @Binding var dados: DadosAula
    var rotuloData = "Data"

    var body: some View {
        Picker("Cadeira", selection: $dados.cadeira) {
            OpcoesCadeira()
            if !library.cadeiras.isEmpty { Divider() }
            Text("Nova cadeira…").tag(DadosAula.novaCadeiraTag)
        }
        if dados.cadeira == DadosAula.novaCadeiraTag {
            TextField("Nome da cadeira", text: $dados.novaCadeira, prompt: Text("ex.: Álgebra Linear"))
        }
        TextField("Título da aula", text: $dados.titulo, prompt: Text("ex.: Tema 3 – Diagonalização"))
            // "Aula 4", a seguir à última da cadeira (só num título vazio: ao editar uma aula, o dela fica).
            .onChange(of: dados.nomeCadeira, initial: true) { dados.sugerirTitulo(library: library) }
        DatePicker(rotuloData, selection: $dados.data, displayedComponents: .date)
    }
}
