import Foundation
import Synchronization

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
    /// Na raiz, ao lado das cadeiras: o que o Mac e o iPad/iPhone trocam (definições, pedidos ao Claude). Não é uma cadeira.
    /// Sem ponto no nome: o iCloud Drive pode não sincronizar pastas escondidas.
    static let pastaSistema = "_recap"

    /// No Mac, a pasta Recap do iCloud Drive quando já existe, senão ~/Aulas (ver `PastaICloud.raizMac`).
    /// No iOS só serve até se abrir a pasta do iCloud Drive (ver `PastaAulas`).
    static var raizPorDefeito: URL {
        #if os(macOS)
        PastaICloud.raizMac()
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
        try decoder.decode(tipo, from: lerDados(url))
    }

    static func escrever<T: Encodable>(_ valor: T, em url: URL) throws {
        try gravar(encoder.encode(valor), em: url)
    }

    // MARK: Ficheiros (iCloud Drive)

    /// A pasta das aulas pode estar no iCloud Drive e ser mudada ao mesmo tempo noutro dispositivo: lê-se e
    /// grava-se com `NSFileCoordinator`, para o iCloud nunca apanhar um ficheiro a meio nem nós um a meio de chegar.
    ///
    /// Um ficheiro ainda não descarregado: com `esperar`, espera pelo download (só fora do fio principal); sem ele,
    /// pede o download e falha já, para a interface não ficar parada (volta-se a ler quando o `ObservadorPasta` avisar).
    static func lerDados(_ url: URL, esperar: Bool = false) throws -> Data {
        if !esperar, porDescarregar(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: url])
        }
        var erro: NSError?
        var resultado: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &erro) { url in
            resultado = Result { try Data(contentsOf: url) }
        }
        if let erro { throw erro }
        return try resultado.get()
    }

    static func lerTexto(_ url: URL, esperar: Bool = false) throws -> String {
        String(decoding: try lerDados(url, esperar: esperar), as: UTF8.self)
    }

    /// Escrita atómica e coordenada. Fica registada para o `ObservadorPasta` não tomar as nossas escritas por mudanças de fora.
    static func gravar(_ dados: Data, em url: URL) throws {
        var erro: NSError?
        var resultado: Result<Void, any Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &erro) { url in
            resultado = Result { try dados.write(to: url, options: .atomic) }
        }
        if let erro { throw erro }
        try resultado.get()
        escritas.withLock { $0[url.standardizedFileURL.path] = .now }
    }

    static func gravar(_ texto: String, em url: URL) throws {
        try gravar(Data(texto.utf8), em: url)
    }

    /// Está no iCloud Drive, mas ainda não neste dispositivo.
    static func porDescarregar(_ url: URL) -> Bool {
        let estado = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        return estado == .notDownloaded
    }

    /// Pede ao iCloud tudo o que falta da pasta de uma aula (os slides e os PDFs só se descarregam quando a aula abre).
    /// Devolve quantos ficheiros ainda estavam por descarregar.
    @discardableResult
    static func descarregar(_ pasta: URL) -> Int {
        let chaves: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey]
        guard let itens = FileManager.default.enumerator(at: pasta, includingPropertiesForKeys: chaves) else { return 0 }
        var faltam = 0
        for case let url as URL in itens where porDescarregar(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            faltam += 1
        }
        return faltam
    }

    /// Quando gravámos cada ficheiro (caminho → data), para o `ObservadorPasta` ignorar o eco das nossas escritas.
    static let escritas = Mutex<[String: Date]>([:])

    /// Gravado por nós há menos de `segundos`.
    static func gravadoHaPouco(_ url: URL, segundos: TimeInterval = 3) -> Bool {
        escritas.withLock { e in e[url.standardizedFileURL.path].map { Date.now.timeIntervalSince($0) < segundos } ?? false }
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
        try gravar(t.textoComTimestamps, em: pasta.appending(path: transcricaoTXT))
    }

    static func lerApontamentos(_ pasta: URL) -> String? {
        try? lerTexto(pasta.appending(path: apontamentosMD))
    }

    static func escreverApontamentos(_ texto: String, em pasta: URL) throws {
        try gravar(texto, em: pasta.appending(path: apontamentosMD))
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

    /// Os bytes dos PDFs do professor da aula.
    static func tamanhoPDFsProfessor(em pasta: URL) -> Int {
        pdfsProfessor(pasta, nomes: [:]).reduce(0) { $0 + ((try? $1.url(em: pasta).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Copia PDFs do professor para a aula, a seguir aos que já lá estão (um PDF igual a um já juntado é saltado).
    /// Devolve os juntados, com o nome original (quem chama guarda-o em `aula.json`). O limite conta também com
    /// os outros materiais (`Materiais`): vão todos no mesmo pedido.
    static func juntarPDFsProfessor(_ origens: [URL], em pasta: URL) throws -> [PDFProfessor] {
        let existentes = pdfsProfessor(pasta, nomes: [:])
        let novos = origens.filter { origem in
            !existentes.contains { FileManager.default.contentsEqual(atPath: $0.url(em: pasta).path, andPath: origem.path) }
        }
        let tamanho = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        let materiais = Materiais.tamanho(em: pasta)
        let total = (existentes.map { $0.url(em: pasta) } + novos).map(tamanho).reduce(0, +) + materiais
        guard total <= tamanhoMaximoPDF else {
            let mb = total / 1_048_576, maximo = tamanhoMaximoPDF / 1_048_576
            let qual = materiais > 0 ? "Os PDFs e os materiais desta aula ficavam com \(mb) MB"
                : existentes.isEmpty && novos.count == 1 ? "O PDF tem \(mb) MB" : "Os PDFs desta aula ficavam com \(mb) MB"
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

    /// nil se `pasta` parece a pasta das aulas do Recap (tem `_recap` ou alguma cadeira); senão, o que dizer a quem a escolheu.
    /// No iOS escolhe-se a pasta no Ficheiros, e é fácil ficar num nível acima ou abaixo do certo.
    static func problemaPastaAulas(_ pasta: URL) -> String? {
        let fm = FileManager.default
        let itens = (try? fm.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? []
        let nomes = itens.map(\.lastPathComponent)
        func eCadeira(_ url: URL) -> Bool { fm.fileExists(atPath: url.appending(path: cadeiraJSON).path) }
        // O nome que o Ficheiros mostra: a raiz de "No iPhone" chama-se "File Provider Storage" no disco.
        let nome = pasta.lastPathComponent == "File Provider Storage" ? "No iPhone" : pasta.lastPathComponent
        if nomes.contains(pastaSistema) || itens.contains(where: eCadeira) { return nil }
        if nomes.contains(cadeiraJSON) {
            return "\"\(nome)\" é uma cadeira. Escolhe a pasta de cima, onde estão todas as cadeiras."
        }
        if nomes.contains(aulaJSON) {
            return "\"\(nome)\" é uma aula. Escolhe a pasta onde estão todas as cadeiras (duas acima)."
        }
        if let aulas = itens.first(where: { $0.lastPathComponent == "Aulas" }), problemaPastaAulas(aulas) == nil {
            return "As aulas estão dentro de \"\(nome)\": abre a pasta Aulas e escolhe-a."
        }
        return "\"\(nome)\" não tem aulas do Recap. Escolhe a pasta que o Recap usa no Mac (Definições → Aulas), normalmente iCloud Drive → Recap."
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
