import Foundation
import Observation

/// A pasta das aulas no iOS: escolhida no Ficheiros (normalmente a do iCloud Drive que o Mac usa) e
/// lembrada com um bookmark, porque fora do contentor da app só se lhe chega com âmbito de segurança.
@MainActor @Observable
final class PastaAulas {
    private static let chave = "bookmarkPastaAulas"
    private let defaults: UserDefaults
    /// A pasta escolhida, já com o acesso aberto; nil até se escolher uma.
    private(set) var url: URL?
    private(set) var erro: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        // `APONTAMENTOS_RAIZ`, como no Mac: no simulador, uma pasta do Mac com aulas de teste, sem a escolher.
        if let p = ProcessInfo.processInfo.environment["APONTAMENTOS_RAIZ"] {
            url = URL(fileURLWithPath: p, isDirectory: true)
            return
        }
        #endif
        guard let dados = defaults.data(forKey: Self.chave) else { return }
        do {
            var desatualizado = false
            let url = try URL(resolvingBookmarkData: dados, bookmarkDataIsStale: &desatualizado)
            guard url.startAccessingSecurityScopedResource() else {
                erro = "Já não tenho acesso à pasta \(url.lastPathComponent). Escolhe-a outra vez."
                return
            }
            if desatualizado, let novo = try? url.bookmarkData() { defaults.set(novo, forKey: Self.chave) }
            self.url = url
        } catch {
            erro = "Não consegui abrir a pasta das aulas: \(error.localizedDescription)"
        }
    }

    /// Guarda a pasta vinda do seletor de pastas (`fileImporter` com `.folder`). Recusa uma pasta sem aulas do Recap
    /// (o seletor abre em "No iPhone" e é fácil carregar em Abrir no sítio errado): a anterior, se houver, continua.
    func escolher(_ nova: URL) throws {
        guard nova.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "Recap", code: 30, userInfo: [NSLocalizedDescriptionKey: "Sem acesso à pasta \(nova.lastPathComponent)."])
        }
        if let problema = Disco.problemaPastaAulas(nova) {
            nova.stopAccessingSecurityScopedResource()
            throw NSError(domain: "Recap", code: 31, userInfo: [NSLocalizedDescriptionKey: problema])
        }
        defaults.set(try nova.bookmarkData(), forKey: Self.chave)
        url?.stopAccessingSecurityScopedResource()
        url = nova
        erro = nil
    }
}
