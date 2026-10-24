import Foundation

/// O prompt de sistema vive num ficheiro editável em Application Support.
/// Na primeira utilização é copiado do bundle. Os marcadores (`{{contexto}}`, `{{idioma}}`, `{{regras_lingua}}`…)
/// são substituídos ao enviar (`Definicoes.prompt`), pelo curso e pelas línguas das Definições.
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
        "276b739eee9dc9a7af6de6d727ffd6182943fc2148fb5b71434a5c3727adf2cc",
        "cbb5b78db8a926614ea49e70a4036936d4640f4bea72c18c60710c1419d59ba3",
        "80cbd786859057d0c7ae2b2aaa66e8c4c3c876aa944021d7a13cc6e79a157b15",
        "30ca986fbd45aaa9d40653252621f2daf543f02d2fd9e6954dd48fdc997d997d",
        "c7b241b77c10652db29988d6689a77bb2be241d59c583814a693c174c1f4085c",
        "24fb55da1c76dacc4b0c7bfa9ff2b35db6be5a99e7a15a32701a966ecd3baaac",
        "468f26682049875b9b9020d4f6f67fe5e86005e97276d7f245246066916806e5",
        "22a06c776110762338c24feaf2e2da62db24ebc66c4b63f19588f51277b409ef",
        "613b53d22fdbd2768520f4d77fa21de206d9d967c7fa46c9f766318c459a3fe1",
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

    static func sha256(_ texto: String) -> String { FichaCadeira.hash(texto) }

    static func guardar(_ texto: String) throws {
        try FileManager.default.createDirectory(at: pastaApp, withIntermediateDirectories: true)
        try texto.write(to: url, atomically: true, encoding: .utf8)
    }

    static func repor() throws {
        try guardar(original)
    }
}
