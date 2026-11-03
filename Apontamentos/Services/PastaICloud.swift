import Foundation

/// A pasta Recap no iCloud Drive: o contentor iCloud da app do iPhone e do iPad, que aparece no Ficheiros e no
/// Finder como "Recap". O iOS chega-lhe pelo contentor (sem escolher nada); o Mac, que não tem o direito do iCloud,
/// escreve diretamente na pasta do contentor em ~/Library/Mobile Documents, que o iCloud Drive sincroniza.
enum PastaICloud {
    static let contentor = "iCloud.pt.danielrodrigues.Recap"

    #if os(macOS)
    /// No Mac: a pasta das aulas dentro do contentor (só existe depois de a app do iPhone ou do iPad a criar).
    static func documentosMac(casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        casa.appending(path: "Library/Mobile Documents", directoryHint: .isDirectory)
            .appending(path: contentor.replacingOccurrences(of: ".", with: "~"), directoryHint: .isDirectory)
            .appending(path: "Documents", directoryHint: .isDirectory)
    }

    static func aulasAntigas(casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        casa.appending(path: "Aulas", directoryHint: .isDirectory)
    }

    /// A pasta das aulas do Mac quando não se escolheu outra: a do iCloud, se já existe e não há aulas por mudar
    /// em ~/Aulas; senão ~/Aulas (nunca troca para uma pasta vazia sem perguntar, ver `deveOferecerMudanca`).
    static func raizMac(casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let icloud = documentosMac(casa: casa)
        guard FileManager.default.fileExists(atPath: icloud.path), !temAulas(aulasAntigas(casa: casa)) else {
            return aulasAntigas(casa: casa)
        }
        return icloud
    }

    /// Perguntar se se mudam as aulas de ~/Aulas para o iCloud: a pasta do iCloud já existe, há aulas em ~/Aulas
    /// e não se escolheu outra pasta à mão nas Definições.
    static func deveOferecerMudanca(pastaEscolhida: String, casa: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        pastaEscolhida.isEmpty
            && FileManager.default.fileExists(atPath: documentosMac(casa: casa).path)
            && temAulas(aulasAntigas(casa: casa))
    }

    #endif

    /// Muda o que está em `origem` para `destino`. Pastas com o mesmo nome juntam-se; um ficheiro que já existe no
    /// destino não é substituído e fica em `origem`. As pastas que ficam vazias em `origem` são apagadas.
    /// Devolve o que ficou por mudar (caminhos relativos a `origem`).
    @discardableResult
    static func mudar(de origem: URL, para destino: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)
        var ficaram: [String] = []
        let itens = try fm.contentsOfDirectory(at: origem, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent != ".DS_Store" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for item in itens {
            let nome = item.lastPathComponent
            let alvo = destino.appending(path: nome)
            var alvoEPasta: ObjCBool = false
            if !fm.fileExists(atPath: alvo.path, isDirectory: &alvoEPasta) {
                try fm.moveItem(at: item, to: alvo)
            } else if alvoEPasta.boolValue, (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                ficaram += try mudar(de: item, para: alvo).map { "\(nome)/\($0)" }
            } else {
                ficaram.append(nome)
            }
        }
        if ficaram.isEmpty { try? fm.removeItem(at: origem) }
        return ficaram
    }

    /// Cria a pasta (se faltar) e marca-a como do Recap, para o iOS a aceitar logo como a pasta das aulas.
    static func preparar(_ documentos: URL) throws {
        try FileManager.default.createDirectory(at: documentos.appending(path: Disco.pastaSistema, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
    }

    private static func temAulas(_ pasta: URL) -> Bool {
        FileManager.default.fileExists(atPath: pasta.path) && Disco.problemaPastaAulas(pasta) == nil
    }
}
