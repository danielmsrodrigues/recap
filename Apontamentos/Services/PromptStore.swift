import Foundation

/// O prompt de sistema vive num ficheiro editável em Application Support.
/// Na primeira utilização é copiado do bundle.
enum PromptStore {
    static var pastaApp: URL {
        URL.applicationSupportDirectory.appending(path: "Recap", directoryHint: .isDirectory)
    }

    static var url: URL { pastaApp.appending(path: "prompt_sistema.md") }

    static var original: String {
        guard let url = Bundle.main.url(forResource: "prompt_sistema_default", withExtension: "md"),
              let texto = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return texto
    }

    static func ler() -> String {
        if let texto = try? String(contentsOf: url, encoding: .utf8) { return texto }
        try? repor()
        return original
    }

    static func guardar(_ texto: String) throws {
        try FileManager.default.createDirectory(at: pastaApp, withIntermediateDirectories: true)
        try texto.write(to: url, atomically: true, encoding: .utf8)
    }

    static func repor() throws {
        try guardar(original)
    }
}
