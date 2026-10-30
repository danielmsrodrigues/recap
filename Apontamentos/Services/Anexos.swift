import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

enum ErroAnexo: LocalizedError {
    case tipoNaoSuportado(String)
    case grandeDemais(String, mb: Int)
    case naoLido(String)

    var errorDescription: String? {
        switch self {
        case .tipoNaoSuportado(let nome):
            "\"\(nome)\" não é um tipo de ficheiro que o Recap saiba ler. Funciona com imagens, PDF, Excel, Word, PowerPoint e ficheiros de texto (CSV, código…)."
        case .grandeDemais(let nome, let mb):
            "\"\(nome)\" tem \(mb) MB; o máximo é \(Anexos.tamanhoMaximo / 1_048_576) MB."
        case .naoLido(let nome):
            "Não foi possível ler \"\(nome)\"."
        }
    }
}

/// Ficheiros juntados a uma pergunta no chat, guardados na pasta da aula (`anexos-chat/`) para continuarem
/// à mão nas perguntas seguintes e chegarem ao Mac pelo iCloud. As imagens ficam em JPEG; Excel, Word e
/// PowerPoint vão para o Claude como texto (a API só lê imagens, PDF e texto).
enum Anexos {
    enum Tipo: Equatable, Sendable { case imagem, pdf, texto, folha, documento, apresentacao }

    static let pasta = "anexos-chat"
    /// Por ficheiro, e no total dos de uma pergunta: o pedido ao Claude já leva a aula toda.
    static let tamanhoMaximo = 10 * 1_048_576
    /// O texto de um ficheiro (ou de uma folha de Excel inteira) é cortado a partir daqui.
    static let maximoCaracteres = 100_000
    /// Lado maior das imagens guardadas: legível para o Claude sem pesar no pedido.
    static let ladoMaximoImagem = 2000

    private static let imagens: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]
    private static let textos: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm", "tex", "bib", "log", "yaml", "yml",
        "py", "ipynb", "r", "rmd", "m", "jl", "sql", "swift", "java", "kt", "c", "h", "cpp", "hpp", "cs", "js", "ts", "go", "rs", "sh",
    ]

    static func tipo(_ nome: String) -> Tipo? {
        let ext = (nome as NSString).pathExtension.lowercased()
        if imagens.contains(ext) { return .imagem }
        if textos.contains(ext) { return .texto }
        return switch ext {
        case "pdf": .pdf
        case "xlsx", "xlsm": .folha
        case "docx": .documento
        case "pptx": .apresentacao
        default: nil
        }
    }

    /// O símbolo (SF Symbols) com que o ficheiro aparece na app.
    static func icone(_ nome: String) -> String {
        switch tipo(nome) {
        case .imagem: "photo"
        case .pdf: "doc.richtext"
        case .folha: "tablecells"
        case .apresentacao: "rectangle.on.rectangle"
        default: "doc.text"
        }
    }

    /// Para os seletores de ficheiros.
    static var tiposAceites: [UTType] {
        (imagens.union(textos).union(["pdf", "xlsx", "xlsm", "docx", "pptx"])).compactMap { UTType(filenameExtension: $0) }
    }

    /// `subpasta`: a do chat, ou a dos materiais do professor (`Materiais`), que guarda os ficheiros da mesma maneira.
    static func url(_ nome: String, em pastaAula: URL, subpasta: String = pasta) -> URL {
        pastaAula.appending(path: subpasta, directoryHint: .isDirectory).appending(path: nome)
    }

    /// O nome, se for só um nome de ficheiro. Os nomes chegam também do iPhone (`PedidoMac`): um caminho
    /// como `../../x` levava ao Claude um ficheiro de fora da aula.
    static func nomeSeguro(_ nome: String) -> String? {
        guard !nome.isEmpty, nome != ".", nome != "..", !nome.contains("/"), !nome.contains(":") else { return nil }
        return nome
    }

    static func tamanho(_ nome: String, em pastaAula: URL, subpasta: String = pasta) -> Int {
        guard let nome = nomeSeguro(nome) else { return 0 }
        return (try? url(nome, em: pastaAula, subpasta: subpasta).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    // MARK: Juntar

    /// Copia o ficheiro para a pasta da aula e devolve o nome com que ficou (com " 2", " 3"… se já houver um igual).
    /// As imagens são convertidas para JPEG com no máximo `ladoMaximoImagem` píxeis.
    @discardableResult
    static func juntar(_ origem: URL, em pastaAula: URL, subpasta: String = pasta) throws -> String {
        let nomeOriginal = origem.lastPathComponent
        guard let tipo = tipo(nomeOriginal) else { throw ErroAnexo.tipoNaoSuportado(nomeOriginal) }
        let destinoPasta = pastaAula.appending(path: subpasta, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destinoPasta, withIntermediateDirectories: true)

        if tipo == .imagem {
            let jpeg = try jpeg(de: origem)
            try verificarTamanho(jpeg.count, nomeOriginal)
            let nome = nomeLivre(((nomeOriginal as NSString).deletingPathExtension) + ".jpg", em: destinoPasta)
            try jpeg.write(to: destinoPasta.appending(path: nome), options: .atomic)
            return nome
        }
        let bytes = (try? origem.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try verificarTamanho(bytes, nomeOriginal)
        let nome = nomeLivre(nomeOriginal, em: destinoPasta)
        try FileManager.default.copyItem(at: origem, to: destinoPasta.appending(path: nome))
        return nome
    }

    static func remover(_ nome: String, em pastaAula: URL) {
        guard let nome = nomeSeguro(nome) else { return }
        try? FileManager.default.removeItem(at: url(nome, em: pastaAula))
    }

    /// Apaga os ficheiros que nenhuma pergunta usa (juntados e nunca enviados) com mais de `idade` segundos:
    /// um mais recente pode estar à espera da pergunta, ou da `perguntas.json` que ainda vem pelo iCloud.
    static func limparOrfaos(em pastaAula: URL, usados: Set<String>, idade: TimeInterval = 86_400) {
        let pasta = pastaAula.appending(path: pasta, directoryHint: .isDirectory)
        guard let ficheiros = try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for f in ficheiros where !usados.contains(f.lastPathComponent) {
            let data = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date.now.timeIntervalSince(data) >= idade { try? FileManager.default.removeItem(at: f) }
        }
    }

    private static func verificarTamanho(_ bytes: Int, _ nome: String) throws {
        guard bytes <= tamanhoMaximo else { throw ErroAnexo.grandeDemais(nome, mb: max(1, bytes / 1_048_576)) }
    }

    private static func nomeLivre(_ nome: String, em pasta: URL) -> String {
        guard FileManager.default.fileExists(atPath: pasta.appending(path: nome).path) else { return nome }
        let base = (nome as NSString).deletingPathExtension, ext = (nome as NSString).pathExtension
        var n = 2
        while true {
            let candidato = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !FileManager.default.fileExists(atPath: pasta.appending(path: candidato).path) { return candidato }
            n += 1
        }
    }

    /// Uma miniatura de um ficheiro juntado, com no máximo `lado` píxeis, para o mostrar no campo. nil = não é
    /// uma imagem (ou não se lê).
    static func miniatura(_ nome: String, em pastaAula: URL, lado: Int) -> CGImage? {
        guard tipo(nome) == .imagem, let nome = nomeSeguro(nome) else { return nil }
        return miniatura(de: url(nome, em: pastaAula), lado: lado)
    }

    static func miniatura(de url: URL, lado: Int) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
        ] as CFDictionary)
    }

    /// A imagem em JPEG, reduzida e sobre fundo branco (a transparência de uma captura ficava preta).
    private static func jpeg(de origem: URL) throws -> Data {
        let nome = origem.lastPathComponent
        guard let fonte = CGImageSourceCreateWithURL(origem as CFURL, nil),
              let reduzida = CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: ladoMaximoImagem,
              ] as CFDictionary),
              let ctx = CGContext(data: nil, width: reduzida.width, height: reduzida.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ErroAnexo.naoLido(nome) }
        let area = CGRect(x: 0, y: 0, width: reduzida.width, height: reduzida.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(area)
        ctx.draw(reduzida, in: area)
        let dados = NSMutableData()
        guard let imagem = ctx.makeImage(),
              let destino = CGImageDestinationCreateWithData(dados, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ErroAnexo.naoLido(nome) }
        CGImageDestinationAddImage(destino, imagem, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { throw ErroAnexo.naoLido(nome) }
        return dados as Data
    }

    // MARK: Para o Claude

    /// Cada ficheiro precedido do nome. Um que não se consegue ler fica só com o aviso, em vez de estragar o pedido.
    static func blocos(_ nomes: [String], em pastaAula: URL, subpasta: String = pasta) -> [BlocoConteudo] {
        nomes.flatMap { nome -> [BlocoConteudo] in
            do {
                return try blocos(nome, em: pastaAula, subpasta: subpasta)
            } catch {
                return [.texto("Ficheiro \"\(nome)\": não foi possível lê-lo.")]
            }
        }
    }

    private static func blocos(_ nome: String, em pastaAula: URL, subpasta: String) throws -> [BlocoConteudo] {
        guard nomeSeguro(nome) != nil else { throw ErroAnexo.naoLido(nome) }
        guard let tipo = tipo(nome) else { throw ErroAnexo.tipoNaoSuportado(nome) }
        // Vindo do iPhone pelo iCloud, pode ainda estar a descarregar.
        let dados = try Disco.lerDados(url(nome, em: pastaAula, subpasta: subpasta), esperar: true)
        let titulo = "Ficheiro \"\(nome)\":"
        let texto: String
        switch tipo {
        case .imagem:
            let ext = (nome as NSString).pathExtension.lowercased()
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg"
            return [.texto(titulo), .imagem(mediaType: mime, base64: dados.base64EncodedString())]
        case .pdf:
            return [.texto(titulo), .documentoPDF(base64: dados.base64EncodedString())]
        case .texto:
            texto = String(data: dados, encoding: .utf8) ?? String(data: dados, encoding: .isoLatin1) ?? ""
        case .folha:
            texto = try self.texto(folha: dados)
        case .documento:
            texto = try self.texto(documento: dados)
        case .apresentacao:
            texto = try self.texto(apresentacao: dados)
        }
        return [.texto("\(titulo)\n\n<ficheiro>\n\(cortado(texto))\n</ficheiro>")]
    }

    private static func cortado(_ texto: String) -> String {
        guard texto.count > maximoCaracteres else { return texto }
        return String(texto.prefix(maximoCaracteres))
            + "\n… (cortado: o ficheiro tem mais \(texto.count - maximoCaracteres) caracteres)"
    }

    /// Dos ficheiros (do mais recente para o mais antigo), os que cabem em `bytes`. Um grande demais
    /// fica de fora, mas os seguintes, mais pequenos, ainda podem entrar.
    static func queCabem(_ ficheiros: [(nome: String, bytes: Int)], bytes: Int) -> [String] {
        var resta = bytes
        return ficheiros.compactMap { f in
            guard f.bytes <= resta else { return nil }
            resta -= f.bytes
            return f.nome
        }
    }

    /// Os ficheiros que vão num pedido: os desta pergunta sempre (até `tamanhoMaximo`), e dos anteriores os mais
    /// recentes que ainda cabem. `espaco` é o que sobra no pedido depois dos PDFs do professor; nil se nem os
    /// desta pergunta cabem.
    static func paraOPedido(atuais: [(nome: String, bytes: Int)], anteriores: [(nome: String, bytes: Int)],
                            espaco: Int) -> (atuais: [String], anteriores: [String])? {
        let limite = min(espaco, tamanhoMaximo)
        let usados = atuais.reduce(0) { $0 + $1.bytes }
        guard usados <= limite else { return nil }
        return (atuais.map(\.nome), queCabem(anteriores, bytes: limite - usados))
    }

    // MARK: Office

    /// Cada folha em CSV, com o nome por cima. Mostra os valores calculados das fórmulas, não as fórmulas.
    static func texto(folha dados: Data) throws -> String {
        let zip = try Archive(data: dados, accessMode: .read)
        let partilhados = try (entrada("xl/sharedStrings.xml", em: zip)).map { try LeitorXML.textosPartilhados($0) } ?? []
        guard let livro = try entrada("xl/workbook.xml", em: zip) else { throw ErroAnexo.naoLido("xl/workbook.xml") }
        let ligacoes = try entrada("xl/_rels/workbook.xml.rels", em: zip).map(LeitorXML.ligacoes) ?? [:]
        return try LeitorXML.folhas(livro).map { folha in
            let alvo = ligacoes[folha.id].map { $0.hasPrefix("/") ? String($0.dropFirst()) : "xl/" + $0 }
            let linhas = try alvo.flatMap { try entrada($0, em: zip) }.map { try LeitorXML.linhas($0, partilhados: partilhados) } ?? []
            let csv = linhas.map { $0.map(campoCSV).joined(separator: ",") }.joined(separator: "\n")
            return "## Folha \"\(folha.nome)\"\n" + (csv.isEmpty ? "(vazia)" : csv)
        }.joined(separator: "\n\n")
    }

    static func texto(documento dados: Data) throws -> String {
        let zip = try Archive(data: dados, accessMode: .read)
        guard let xml = try entrada("word/document.xml", em: zip) else { throw ErroAnexo.naoLido("word/document.xml") }
        return try LeitorXML.paragrafos(xml).joined(separator: "\n")
    }

    static func texto(apresentacao dados: Data) throws -> String {
        let zip = try Archive(data: dados, accessMode: .read)
        let slides = zip.compactMap { e -> (Int, String)? in
            let caminho = e.path
            guard caminho.hasPrefix("ppt/slides/slide"), caminho.hasSuffix(".xml"),
                  let n = Int(caminho.dropFirst("ppt/slides/slide".count).dropLast(".xml".count)) else { return nil }
            return (n, caminho)
        }.sorted { $0.0 < $1.0 }
        return try slides.map { n, caminho in
            let texto = try entrada(caminho, em: zip).map { try LeitorXML.paragrafos($0).joined(separator: "\n") } ?? ""
            return "## Slide \(n)\n" + (texto.isEmpty ? "(sem texto)" : texto)
        }.joined(separator: "\n\n")
    }

    private static func entrada(_ caminho: String, em zip: Archive) throws -> Data? {
        guard let e = zip[caminho] else { return nil }
        var dados = Data()
        _ = try zip.extract(e, skipCRC32: true) { dados.append($0) }
        return dados
    }

    private static func campoCSV(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Leitura dos XML dentro dos ficheiros do Office, pelos nomes locais das etiquetas (sem os prefixos `w:`, `a:`…).
private final class LeitorXML: NSObject, XMLParserDelegate {
    private var aoAbrir: (String, [String: String]) -> Void = { _, _ in }
    private var aoFechar: (String) -> Void = { _ in }
    private var aoLer: (String) -> Void = { _ in }

    private func ler(_ dados: Data) throws {
        let p = XMLParser(data: dados)
        p.shouldProcessNamespaces = true
        p.delegate = self
        guard p.parse() else { throw p.parserError ?? ErroAnexo.naoLido("XML") }
    }

    func parser(_ parser: XMLParser, didStartElement nome: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) { aoAbrir(nome, attributes) }
    func parser(_ parser: XMLParser, didEndElement nome: String, namespaceURI: String?, qualifiedName: String?) { aoFechar(nome) }
    func parser(_ parser: XMLParser, foundCharacters texto: String) { aoLer(texto) }

    /// O texto de cada parágrafo (`<w:p>` no Word, `<a:p>` no PowerPoint), sem os vazios.
    static func paragrafos(_ dados: Data) throws -> [String] {
        let l = LeitorXML()
        var paragrafos: [String] = [], atual = "", emTexto = false
        l.aoAbrir = { nome, _ in
            switch nome {
            case "p": atual = ""
            case "t": emTexto = true
            case "tab": atual += "\t"
            case "br": atual += "\n"
            default: break
            }
        }
        l.aoFechar = { nome in
            if nome == "t" { emTexto = false }
            if nome == "p", !atual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { paragrafos.append(atual) }
        }
        l.aoLer = { if emTexto { atual += $0 } }
        try l.ler(dados)
        return paragrafos
    }

    /// `xl/sharedStrings.xml`: o texto de cada `<si>`, juntando os pedaços com formatação diferente.
    static func textosPartilhados(_ dados: Data) throws -> [String] {
        let l = LeitorXML()
        var textos: [String] = [], atual = "", emTexto = false, fonetica = false
        l.aoAbrir = { nome, _ in
            switch nome {
            case "si": atual = ""
            case "t": emTexto = !fonetica
            case "rPh": fonetica = true
            default: break
            }
        }
        l.aoFechar = { nome in
            switch nome {
            case "si": textos.append(atual)
            case "t": emTexto = false
            case "rPh": fonetica = false
            default: break
            }
        }
        l.aoLer = { if emTexto { atual += $0 } }
        try l.ler(dados)
        return textos
    }

    /// `xl/_rels/workbook.xml.rels`: id → caminho da folha.
    static func ligacoes(_ dados: Data) throws -> [String: String] {
        let l = LeitorXML()
        var ligacoes: [String: String] = [:]
        l.aoAbrir = { nome, a in
            if nome == "Relationship", let id = a["Id"], let alvo = a["Target"] { ligacoes[id] = alvo }
        }
        try l.ler(dados)
        return ligacoes
    }

    /// `xl/workbook.xml`: as folhas, pela ordem do livro.
    static func folhas(_ dados: Data) throws -> [(nome: String, id: String)] {
        let l = LeitorXML()
        var folhas: [(String, String)] = []
        l.aoAbrir = { nome, a in
            // Com os espaços de nomes processados, o `r:id` chega só como `id`.
            if nome == "sheet", let n = a["name"], let id = a["r:id"] ?? a["id"] { folhas.append((n, id)) }
        }
        try l.ler(dados)
        return folhas
    }

    /// As linhas de uma folha, com as células vazias pelo meio preenchidas. Linhas vazias ficam de fora.
    static func linhas(_ dados: Data, partilhados: [String]) throws -> [[String]] {
        let l = LeitorXML()
        var linhas: [[String]] = [], linha: [Int: String] = [:]
        var coluna = 0, tipo: String?, valor = "", emValor = false
        l.aoAbrir = { nome, a in
            switch nome {
            case "row": linha = [:]; coluna = 0
            case "c":
                coluna = a["r"].map(Self.coluna) ?? coluna + 1
                tipo = a["t"]; valor = ""
            case "v", "t": emValor = true
            default: break
            }
        }
        l.aoFechar = { nome in
            switch nome {
            case "v", "t": emValor = false
            case "c":
                let texto = switch tipo {
                case "s": Int(valor).flatMap { partilhados.indices.contains($0) ? partilhados[$0] : nil } ?? ""
                case "b": valor == "1" ? "TRUE" : "FALSE"
                default: valor
                }
                if !texto.isEmpty { linha[coluna] = texto }
            case "row":
                if let ultima = linha.keys.max() { linhas.append((1...ultima).map { linha[$0] ?? "" }) }
            default: break
            }
        }
        l.aoLer = { if emValor { valor += $0 } }
        try l.ler(dados)
        return linhas
    }

    /// "C4" → 3 (as colunas começam em 1).
    private static func coluna(_ referencia: String) -> Int {
        referencia.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
    }
}
