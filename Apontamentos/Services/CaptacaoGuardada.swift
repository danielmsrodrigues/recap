import Foundation

/// Uma captação em direto guardada numa pasta da app (e não na pasta temporária), com uma ficha a dizer de que aula é.
/// Se a app fechar antes de a transcrever (ou a meio), ao abrir volta à fila: a aula não se perde e os ficheiros
/// não ficam esquecidos. Fica fora da pasta das aulas, que pode estar no iCloud (não se sincronizam centenas de MB).
struct CaptacaoGuardada: Sendable {
    let pasta: URL
    var audio: URL { pasta.appending(path: "audio.caf") }
    var frames: URL { pasta.appending(path: "frames", directoryHint: .isDirectory) }
    private var urlFicha: URL { pasta.appending(path: "captacao.json") }

    struct Ficha: Codable, Equatable, Sendable {
        var pastaAula: URL
        var titulo: String
        var velocidade: Double
        var gerarApontamentos: Bool
    }

    /// ~/Library/Application Support/pt.danielrodrigues.Recap/Captacoes
    static var raizPorDefeito: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "pt.danielrodrigues.Recap", directoryHint: .isDirectory)
            .appending(path: "Captacoes", directoryHint: .isDirectory)
    }

    static func criar(em raiz: URL = raizPorDefeito) throws -> CaptacaoGuardada {
        let c = CaptacaoGuardada(pasta: raiz.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: c.pasta, withIntermediateDirectories: true)
        return c
    }

    func guardar(_ ficha: Ficha) throws {
        try JSONEncoder().encode(ficha).write(to: urlFicha, options: .atomic)
    }

    func apagar() { try? FileManager.default.removeItem(at: pasta) }

    /// Já sem áudio (transcrito) nem imagens (slides extraídos): a pasta vai-se.
    func apagarSeAcabada() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: audio.path), !fm.fileExists(atPath: frames.path) { apagar() }
    }

    /// A captação a que pertence um ficheiro de áudio (para a apagar quando a aula fica transcrita).
    static func de(audio: URL) -> CaptacaoGuardada? {
        let pasta = audio.deletingLastPathComponent()
        guard audio.lastPathComponent == "audio.caf",
              FileManager.default.fileExists(atPath: pasta.appending(path: "captacao.json").path) else { return nil }
        return CaptacaoGuardada(pasta: pasta)
    }

    /// As captações por transcrever (com áudio e com a aula ainda lá). As outras (já transcritas, aula apagada,
    /// sem ficha) são apagadas. `aulaExiste`: a pasta da aula ainda existe.
    static func pendentes(em raiz: URL = raizPorDefeito, aulaExiste: (URL) -> Bool) -> [(captacao: CaptacaoGuardada, ficha: Ficha)] {
        let pastas = (try? FileManager.default.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return pastas.compactMap { pasta in
            let c = CaptacaoGuardada(pasta: pasta)
            guard let dados = try? Data(contentsOf: c.urlFicha), let ficha = try? JSONDecoder().decode(Ficha.self, from: dados),
                  FileManager.default.fileExists(atPath: c.audio.path), aulaExiste(ficha.pastaAula)
            else {
                c.apagar()
                return nil
            }
            return (c, ficha)
        }
    }

    /// As pastas temporárias de versões anteriores (sem ficha, não há como saber de que aula eram).
    static func limparTemporariasAntigas() {
        let tmp = FileManager.default.temporaryDirectory
        let itens = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for item in itens where item.lastPathComponent.hasPrefix("Recap-direto-") || item.lastPathComponent.hasPrefix("Recap-slides-") {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
