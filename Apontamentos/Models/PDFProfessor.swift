import Foundation

/// Um PDF de slides publicado pelo professor e juntado à aula. Uma aula pode ter vários (um por tema, por exemplo);
/// cada um pode ter sido dado só em parte, ou nada, nesta aula.
///
///     slides-professor.pdf     → páginas em slides-pdf/pagina-NN.jpg    (PDF 1, o único das aulas antigas)
///     slides-professor-2.pdf   → páginas em slides-pdf-2/pagina-NN.jpg  (PDF 2)
struct PDFProfessor: Hashable, Sendable, Identifiable {
    /// Número do PDF na aula. Não muda quando se remove outro: os apontamentos já feitos apontam para as páginas dele.
    var numero: Int
    /// Nome do ficheiro original (aulas antigas não o guardaram).
    var nome: String?

    var id: Int { numero }
    var ficheiro: String { numero == 1 ? "slides-professor.pdf" : "slides-professor-\(numero).pdf" }
    /// Pasta das imagens das páginas, relativa à pasta da aula.
    var pastaPaginas: String { numero == 1 ? "slides-pdf" : "slides-pdf-\(numero)" }
    /// Como aparece na app: o nome original, sem a extensão.
    var titulo: String {
        guard let nome, !nome.isEmpty else { return "PDF \(numero)" }
        return (nome as NSString).deletingPathExtension
    }

    func url(em pasta: URL) -> URL { pasta.appending(path: ficheiro) }

    /// O número do PDF a partir do nome do ficheiro na pasta da aula, ou nil se não é um PDF do professor.
    static func numero(doFicheiro nome: String) -> Int? {
        if nome == "slides-professor.pdf" { return 1 }
        guard nome.hasPrefix("slides-professor-"), nome.hasSuffix(".pdf") else { return nil }
        let meio = String(nome.dropFirst("slides-professor-".count).dropLast(".pdf".count))
        guard let n = Int(meio), n >= 2, String(n) == meio else { return nil }
        return n
    }
}
