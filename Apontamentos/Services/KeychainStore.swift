import Foundation
import Security

/// Chave API da Anthropic na Keychain do utilizador.
enum KeychainStore {
    private static let servico = "pt.danielrodrigues.Apontamentos.anthropic"
    private static let conta = "api-key"

    private static var consultaBase: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servico,
            kSecAttrAccount as String: conta,
        ]
    }

    static func chaveAPI() -> String? {
        var consulta = consultaBase
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let data = resultado as? Data,
              let chave = String(data: data, encoding: .utf8),
              !chave.isEmpty
        else { return nil }
        return chave
    }

    /// Só os atributos: não pede autorização ao utilizador, ao contrário de ler o segredo.
    static func temChave() -> Bool {
        var consulta = consultaBase
        consulta[kSecReturnAttributes as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        var resultado: CFTypeRef?
        return SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess
    }

    static func guardar(_ chave: String) throws {
        let data = Data(chave.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let estado = SecItemUpdate(consultaBase as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if estado == errSecItemNotFound {
            var novo = consultaBase
            novo[kSecValueData as String] = data
            novo[kSecAttrLabel as String] = "Recap — chave API da Anthropic"
            try verificar(SecItemAdd(novo as CFDictionary, nil))
        } else {
            try verificar(estado)
        }
    }

    static func apagar() throws {
        let estado = SecItemDelete(consultaBase as CFDictionary)
        if estado != errSecItemNotFound { try verificar(estado) }
    }

    private static func verificar(_ estado: OSStatus) throws {
        guard estado == errSecSuccess else {
            let mensagem = SecCopyErrorMessageString(estado, nil) as String? ?? "erro \(estado)"
            throw NSError(domain: "Keychain", code: Int(estado), userInfo: [NSLocalizedDescriptionKey: "Keychain: \(mensagem)"])
        }
    }
}
