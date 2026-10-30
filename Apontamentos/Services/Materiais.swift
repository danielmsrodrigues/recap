import Foundation

/// Outros materiais do professor juntados à aula além dos PDFs dos slides (folhas de Excel, documentos de Word,
/// apresentações de PowerPoint, imagens, texto), em `materiais/`. Guardam-se e vão para o Claude como os ficheiros
/// do chat (`Anexos`): entram no pedido dos apontamentos e no das perguntas, mas não aparecem como slides.
enum Materiais {
    static let pasta = "materiais"
    /// O texto de todos os materiais junto (Excel, Word, PowerPoint, texto) vai até aqui: muitas folhas de cálculo
    /// enchiam o pedido (e a conta), em cada pergunta.
    static let maximoCaracteres = 150_000

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

    /// O que todos ocupam no pedido: contam para o limite, com os PDFs do professor. Uma imagem vai inteira;
    /// um Excel, Word, PowerPoint ou texto vai em texto, até à sua parte de `maximoCaracteres` (o ficheiro pode
    /// ser muito maior, ou, comprimido como um Excel, muito mais pequeno do que o texto que dá).
    static func tamanho(em pastaAula: URL) -> Int {
        let nomes = nomes(em: pastaAula)
        let porTexto = caracteresPorFicheiro(nomes)
        return nomes.reduce(0) { total, nome in
            let bytes = Anexos.tamanho(nome, em: pastaAula, subpasta: pasta)
            let noPedido = switch Anexos.tipo(nome) {
            case .imagem, .pdf: bytes
            case .texto: min(bytes, porTexto)
            default: porTexto
            }
            return total + noPedido
        }
    }

    /// A parte de `maximoCaracteres` de cada material que vai em texto.
    private static func caracteresPorFicheiro(_ nomes: [String]) -> Int {
        let emTexto = nomes.filter { ![.imagem, .pdf].contains(Anexos.tipo($0)) }.count
        return maximoCaracteres / max(1, emTexto)
    }

    /// Copia os ficheiros para a aula e devolve os nomes com que ficaram. Um igual a um já juntado é saltado.
    /// Recusa o que não sabe ler, e o que passaria o limite do pedido somado aos PDFs (`Disco.tamanhoMaximoPDF`).
    @discardableResult
    static func juntar(_ origens: [URL], em pastaAula: URL) throws -> [String] {
        var juntados: [String] = []
        for origem in origens {
            guard let nome = try Anexos.juntarSeNovo(origem, em: pastaAula, subpasta: pasta) else { continue }
            let copia = url(nome, em: pastaAula)
            // A ordem é a da data de criação: a cópia pode trazer a do ficheiro original.
            try? FileManager.default.setAttributes([.creationDate: Date.now], ofItemAtPath: copia.path)
            let total = Disco.tamanhoPDFsProfessor(em: pastaAula) + tamanho(em: pastaAula)
            guard total <= Disco.tamanhoMaximoPDF else {
                try? FileManager.default.removeItem(at: copia)
                let antes = juntados.isEmpty ? "" : " Os anteriores (\(juntados.joined(separator: ", "))) ficaram juntados."
                throw NSError(domain: "Recap", code: 41, userInfo: [NSLocalizedDescriptionKey:
                    "Com \"\(origem.lastPathComponent)\", os PDFs e os materiais desta aula ficavam com \(total / 1_048_576) MB; o máximo é \(Disco.tamanhoMaximoPDF / 1_048_576) MB.\(antes)"])
            }
            juntados.append(nome)
        }
        return juntados
    }

    /// Ao juntar duas gravações (`JuntarAulas`): copia os materiais de `outra` tal como estão (sem converter de novo
    /// as imagens nem voltar a medir), saltando os que já cá estão iguais.
    static func copiar(de outra: URL, para pastaAula: URL) throws {
        let destino = pastaAula.appending(path: pasta, directoryHint: .isDirectory)
        let existentes = nomes(em: pastaAula).map { url($0, em: pastaAula) }
        for nome in nomes(em: outra) {
            let origem = url(nome, em: outra)
            if existentes.contains(where: { FileManager.default.contentsEqual(atPath: $0.path, andPath: origem.path) }) { continue }
            try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
            let copia = destino.appending(path: Anexos.nomeLivre(Anexos.nomeGuardado(nome), em: destino))
            try FileManager.default.copyItem(at: origem, to: copia)
            try? FileManager.default.setAttributes([.creationDate: Date.now], ofItemAtPath: copia.path)
        }
    }

    /// Vai para o Lixo (recuperável).
    static func remover(_ nome: String, em pastaAula: URL) throws {
        guard let nome = Anexos.nomeSeguro(nome) else { throw ErroAnexo.naoLido(nome) }
        try FileManager.default.trashItem(at: url(nome, em: pastaAula), resultingItemURL: nil)
    }

    /// Para o pedido ao Claude (Excel, Word e PowerPoint já em texto). Lê do disco: fora do fio principal.
    static func blocos(em pastaAula: URL) -> [BlocoConteudo] {
        let nomes = nomes(em: pastaAula)
        return Anexos.blocos(nomes, em: pastaAula, subpasta: pasta, maximoCaracteres: caracteresPorFicheiro(nomes))
    }
}
