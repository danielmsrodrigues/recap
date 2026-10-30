import Foundation

/// Outros materiais do professor juntados à aula além dos PDFs dos slides (folhas de Excel, documentos de Word,
/// apresentações de PowerPoint, imagens, texto), em `materiais/`. Guardam-se e vão para o Claude como os ficheiros
/// do chat (`Anexos`): entram no pedido dos apontamentos e no das perguntas, mas não aparecem como slides.
enum Materiais {
    static let pasta = "materiais"

    static func url(_ nome: String, em pastaAula: URL) -> URL {
        Anexos.url(nome, em: pastaAula, subpasta: pasta)
    }

    /// Pela ordem em que foram juntados.
    static func nomes(em pastaAula: URL) -> [String] {
        let chaves: [URLResourceKey] = [.creationDateKey]
        let ficheiros = (try? FileManager.default.contentsOfDirectory(
            at: pastaAula.appending(path: pasta, directoryHint: .isDirectory),
            includingPropertiesForKeys: chaves, options: .skipsHiddenFiles)) ?? []
        let comData: [(nome: String, criado: Date)] = ficheiros.map { f in
            (f.lastPathComponent, (try? f.resourceValues(forKeys: Set(chaves)).creationDate) ?? .distantPast)
        }
        return comData.sorted { $0.criado != $1.criado ? $0.criado < $1.criado : $0.nome < $1.nome }.map(\.nome)
    }

    /// Os bytes de todos: contam para o limite do pedido, com os PDFs do professor.
    static func tamanho(em pastaAula: URL) -> Int {
        nomes(em: pastaAula).reduce(0) { $0 + Anexos.tamanho($1, em: pastaAula, subpasta: pasta) }
    }

    /// Copia os ficheiros para a aula e devolve os nomes com que ficaram. Um igual a um já juntado é saltado.
    /// Recusa o que não sabe ler, e o que passaria o limite do pedido somado aos PDFs (`Disco.tamanhoMaximoPDF`).
    @discardableResult
    static func juntar(_ origens: [URL], em pastaAula: URL) throws -> [String] {
        var juntados: [String] = []
        for origem in origens {
            let existentes = nomes(em: pastaAula).map { url($0, em: pastaAula) }
            if existentes.contains(where: { FileManager.default.contentsEqual(atPath: $0.path, andPath: origem.path) }) { continue }
            let nome = try Anexos.juntar(origem, em: pastaAula, subpasta: pasta)
            let copia = url(nome, em: pastaAula)
            // A ordem é a da data de criação: a cópia pode trazer a do ficheiro original.
            try? FileManager.default.setAttributes([.creationDate: Date.now], ofItemAtPath: copia.path)
            let total = Disco.tamanhoPDFsProfessor(em: pastaAula) + tamanho(em: pastaAula)
            guard total <= Disco.tamanhoMaximoPDF else {
                try? FileManager.default.removeItem(at: copia)
                throw NSError(domain: "Recap", code: 41, userInfo: [NSLocalizedDescriptionKey:
                    "Com \"\(origem.lastPathComponent)\", os PDFs e os materiais desta aula ficavam com \(total / 1_048_576) MB; o máximo é \(Disco.tamanhoMaximoPDF / 1_048_576) MB."])
            }
            juntados.append(nome)
        }
        return juntados
    }

    /// Vai para o Lixo (recuperável).
    static func remover(_ nome: String, em pastaAula: URL) throws {
        guard let nome = Anexos.nomeSeguro(nome) else { throw ErroAnexo.naoLido(nome) }
        try FileManager.default.trashItem(at: url(nome, em: pastaAula), resultingItemURL: nil)
    }

    /// Para o pedido ao Claude (Excel, Word e PowerPoint já em texto). Lê do disco: fora do fio principal.
    static func blocos(em pastaAula: URL) -> [BlocoConteudo] {
        Anexos.blocos(nomes(em: pastaAula), em: pastaAula, subpasta: pasta)
    }
}
