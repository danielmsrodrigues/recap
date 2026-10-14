import Foundation

/// Leitura e escrita dos ficheiros de uma aula. `~/Aulas` é a fonte de verdade:
///
///     ~/Aulas/<cadeira>/cadeira.json
///     ~/Aulas/<cadeira>/<aaaa-mm-dd>_<título>/aula.json
///                                             transcricao.json
///                                             transcricao.txt
///                                             apontamentos.md
///                                             slides/
enum Disco {
    static let aulaJSON = "aula.json"
    static let cadeiraJSON = "cadeira.json"
    static let transcricaoJSON = "transcricao.json"
    static let transcricaoTXT = "transcricao.txt"
    static let apontamentosMD = "apontamentos.md"
    static let apontamentosPDF = "apontamentos.pdf"
    /// Versão anterior, guardada antes de cada regeneração.
    static let apontamentosAnteriorMD = "apontamentos.anterior.md"
    static let slidesJSON = "slides.json"
    /// Slides publicados pelo professor, juntados à aula pelo utilizador.
    static let slidesPDF = "slides-professor.pdf"
    /// Acima disto o pedido ao Claude fica demasiado grande (o limite é ~32 MB no total).
    static let tamanhoMaximoPDF = 24 * 1_048_576
    static let pastaSlides = "slides"

    static var raizPorDefeito: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Aulas", directoryHint: .isDirectory)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Nomes de pasta

    /// Torna um nome seguro para pasta sem o tornar ilegível: mantém acentos e espaços,
    /// troca `/` e `:` por `-` e corta pontos iniciais.
    static func nomeDePasta(_ nome: String) -> String {
        var s = nome.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while s.hasPrefix(".") { s.removeFirst() }
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Sem título" : s
    }

    static func nomePastaAula(titulo: String, data: Date) -> String {
        let dia = data.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        return "\(dia)_\(nomeDePasta(titulo))"
    }

    /// Acrescenta " (2)", " (3)"… se a pasta já existir.
    static func pastaLivre(_ nome: String, em pai: URL) -> URL {
        var candidato = pai.appending(path: nome, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: candidato.path) {
            candidato = pai.appending(path: "\(nome) (\(n))", directoryHint: .isDirectory)
            n += 1
        }
        return candidato
    }

    // MARK: JSON

    static func ler<T: Decodable>(_ tipo: T.Type, de url: URL) throws -> T {
        try decoder.decode(tipo, from: Data(contentsOf: url))
    }

    static func escrever<T: Encodable>(_ valor: T, em url: URL) throws {
        try encoder.encode(valor).write(to: url, options: .atomic)
    }

    // MARK: Aula

    static func lerMeta(_ pasta: URL) throws -> AulaMeta {
        try ler(AulaMeta.self, de: pasta.appending(path: aulaJSON))
    }

    static func escreverMeta(_ meta: AulaMeta, em pasta: URL) throws {
        try escrever(meta, em: pasta.appending(path: aulaJSON))
    }

    static func lerTranscricao(_ pasta: URL) -> Transcricao? {
        try? ler(Transcricao.self, de: pasta.appending(path: transcricaoJSON))
    }

    static func escreverTranscricao(_ t: Transcricao, em pasta: URL) throws {
        try escrever(t, em: pasta.appending(path: transcricaoJSON))
        try t.textoComTimestamps.write(to: pasta.appending(path: transcricaoTXT), atomically: true, encoding: .utf8)
    }

    static func lerApontamentos(_ pasta: URL) -> String? {
        try? String(contentsOf: pasta.appending(path: apontamentosMD), encoding: .utf8)
    }

    static func escreverApontamentos(_ texto: String, em pasta: URL) throws {
        try texto.write(to: pasta.appending(path: apontamentosMD), atomically: true, encoding: .utf8)
    }

    /// Copia os apontamentos atuais para `apontamentos.anterior.md` antes de os substituir.
    static func guardarCopiaApontamentos(em pasta: URL) throws {
        let atual = pasta.appending(path: apontamentosMD), copia = pasta.appending(path: apontamentosAnteriorMD)
        guard FileManager.default.fileExists(atPath: atual.path) else { return }
        try? FileManager.default.removeItem(at: copia)
        try FileManager.default.copyItem(at: atual, to: copia)
    }

    /// O PDF existe e é mais recente do que o Markdown.
    static func pdfAtualizado(em pasta: URL) -> Bool {
        let chave: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let pdf = try? pasta.appending(path: apontamentosPDF).resourceValues(forKeys: chave).contentModificationDate,
              let md = try? pasta.appending(path: apontamentosMD).resourceValues(forKeys: chave).contentModificationDate
        else { return false }
        return pdf >= md
    }

    /// nil = ainda não extraídos; [] = extraídos, mas nenhum slide encontrado.
    static func lerSlides(_ pasta: URL) -> [Slide]? {
        try? ler([Slide].self, de: pasta.appending(path: slidesJSON))
    }

    static func escreverSlides(_ slides: [Slide], em pasta: URL) throws {
        try escrever(slides, em: pasta.appending(path: slidesJSON))
    }

    static func urlPDFProfessor(_ pasta: URL) -> URL? {
        let url = pasta.appending(path: slidesPDF)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func juntarPDFProfessor(_ origem: URL, em pasta: URL) throws {
        let tamanho = (try? origem.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard tamanho <= tamanhoMaximoPDF else {
            throw NSError(domain: "Recap", code: 40, userInfo: [NSLocalizedDescriptionKey:
                "O PDF tem \(tamanho / 1_048_576) MB; o máximo é \(tamanhoMaximoPDF / 1_048_576) MB. Exporta-o com menos qualidade (Pré-visualização → Exportar → Filtro Quartz \"Reduce File Size\") e tenta de novo."])
        }
        let destino = pasta.appending(path: slidesPDF)
        if FileManager.default.fileExists(atPath: destino.path) { try FileManager.default.removeItem(at: destino) }
        try FileManager.default.copyItem(at: origem, to: destino)
        // As páginas do PDF antigo já não correspondem; as novas são criadas em fundo por quem juntou o PDF.
        SlidesNosApontamentos.apagarPaginas(em: pasta)
    }

    static func urlSlide(_ slide: Slide, em pasta: URL) -> URL {
        pasta.appending(path: pastaSlides).appending(path: slide.ficheiro)
    }

    static func existe(_ ficheiro: String, em pasta: URL) -> Bool {
        FileManager.default.fileExists(atPath: pasta.appending(path: ficheiro).path)
    }

    // MARK: Cadeira

    static func lerCadeira(_ pasta: URL) -> CadeiraMeta {
        (try? ler(CadeiraMeta.self, de: pasta.appending(path: cadeiraJSON))) ?? CadeiraMeta()
    }

    static func escreverCadeira(_ meta: CadeiraMeta, em pasta: URL) throws {
        try escrever(meta, em: pasta.appending(path: cadeiraJSON))
    }
}
