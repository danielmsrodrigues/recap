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
    /// Acima disto (somando os PDFs do professor) o pedido ao Claude fica demasiado grande (o limite é ~32 MB no total).
    static let tamanhoMaximoPDF = 24 * 1_048_576
    static let pastaSlides = "slides"

    /// No iOS só serve até se escolher a pasta do iCloud Drive (ver `PastaAulas`).
    static var raizPorDefeito: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Aulas", directoryHint: .isDirectory)
        #else
        URL.documentsDirectory.appending(path: "Aulas", directoryHint: .isDirectory)
        #endif
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

    /// Os PDFs dos slides do professor juntados à aula, pelo número (ver `PDFProfessor`).
    /// `nomes` evita ler `aula.json` quando quem chama já o tem.
    static func pdfsProfessor(_ pasta: URL, nomes: [String: String]? = nil) -> [PDFProfessor] {
        let ficheiros = (try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? []
        let numeros = ficheiros.compactMap(PDFProfessor.numero(doFicheiro:)).sorted()
        guard !numeros.isEmpty else { return [] }
        let nomes = nomes ?? (try? lerMeta(pasta))?.nomesPDFs ?? [:]
        return numeros.map { n in
            var pdf = PDFProfessor(numero: n)
            pdf.nome = nomes[pdf.ficheiro]
            return pdf
        }
    }

    /// Copia PDFs do professor para a aula, a seguir aos que já lá estão (um PDF igual a um já juntado é saltado).
    /// Devolve os juntados, com o nome original (quem chama guarda-o em `aula.json`).
    static func juntarPDFsProfessor(_ origens: [URL], em pasta: URL) throws -> [PDFProfessor] {
        let existentes = pdfsProfessor(pasta, nomes: [:])
        let novos = origens.filter { origem in
            !existentes.contains { FileManager.default.contentsEqual(atPath: $0.url(em: pasta).path, andPath: origem.path) }
        }
        let tamanho = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        let total = (existentes.map { $0.url(em: pasta) } + novos).map(tamanho).reduce(0, +)
        guard total <= tamanhoMaximoPDF else {
            let mb = total / 1_048_576, maximo = tamanhoMaximoPDF / 1_048_576
            let qual = existentes.isEmpty && novos.count == 1 ? "O PDF tem \(mb) MB" : "Os PDFs desta aula ficavam com \(mb) MB"
            throw NSError(domain: "Recap", code: 40, userInfo: [NSLocalizedDescriptionKey:
                "\(qual); o máximo é \(maximo) MB. Exporta-os com menos qualidade (Pré-visualização → Exportar → Filtro Quartz \"Reduce File Size\") e tenta de novo."])
        }
        var proximo = (existentes.map(\.numero).max() ?? 0) + 1
        var juntados: [PDFProfessor] = []
        for origem in novos {
            let pdf = PDFProfessor(numero: proximo, nome: origem.lastPathComponent)
            try FileManager.default.copyItem(at: origem, to: pdf.url(em: pasta))
            // Páginas de um PDF removido que tinha este número já não correspondem; as novas são criadas em fundo.
            SlidesNosApontamentos.apagarPaginas(de: pdf, em: pasta)
            juntados.append(pdf)
            proximo += 1
        }
        return juntados
    }

    /// O PDF e as imagens das páginas vão para o Lixo (recuperáveis).
    static func removerPDFProfessor(_ pdf: PDFProfessor, em pasta: URL) throws {
        try FileManager.default.trashItem(at: pdf.url(em: pasta), resultingItemURL: nil)
        SlidesNosApontamentos.apagarPaginas(de: pdf, em: pasta)
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
