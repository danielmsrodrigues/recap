import CryptoKit
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

    /// SHA-256 das versões anteriores do prompt por defeito. Um ficheiro igual a uma delas nunca foi editado
    /// pelo utilizador e passa para a versão nova; um prompt editado à mão nunca é tocado.
    static let versoesAntigas: Set<String> = [
        "469769ba271771f4de02e97d3d4f652775f5dbcfbb306ddfbe66d7b6cf6a8097",
        "57a47886b9e4a71f8f01122e5b3a7f3af9c9aab00c8d534e83974bd2cfddfe63",
    ]

    static func ler() -> String {
        if let texto = try? String(contentsOf: url, encoding: .utf8) {
            guard versoesAntigas.contains(sha256(texto)) else { return texto }
            try? repor()
            return original
        }
        try? repor()
        return original
    }

    static func sha256(_ texto: String) -> String {
        SHA256.hash(data: Data(texto.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func guardar(_ texto: String) throws {
        try FileManager.default.createDirectory(at: pastaApp, withIntermediateDirectories: true)
        try texto.write(to: url, atomically: true, encoding: .utf8)
    }

    static func repor() throws {
        try guardar(original)
    }
}
