import Foundation
@preconcurrency import WhisperKit

enum WhisperModelo: String, CaseIterable, Identifiable, Codable, Sendable {
    /// O large-v3-turbo da OpenAI (versão de 2024-09-30) convertido para Core ML.
    case largeV3Turbo = "openai_whisper-large-v3-v20240930"
    case largeV3 = "openai_whisper-large-v3"

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .largeV3Turbo: "Large v3 Turbo"
        case .largeV3: "Large v3"
        }
    }

    var descricao: String {
        switch self {
        case .largeV3Turbo: "Recomendado. Bastante mais rápido, qualidade quase igual. ~1,6 GB."
        case .largeV3: "Mais lento, ligeiramente mais preciso em áudio difícil. ~3 GB."
        }
    }
}

/// Modelos do WhisperKit em `~/Library/Application Support/Apontamentos/Modelos`.
struct ModelStore: Sendable {
    var base: URL = PromptStore.pastaApp.appending(path: "Modelos", directoryHint: .isDirectory)

    /// Onde o WhisperKit grava o modelo: `<base>/models/argmaxinc/whisperkit-coreml/<variante>`.
    func pasta(_ modelo: WhisperModelo) -> URL {
        base.appending(path: "models/argmaxinc/whisperkit-coreml/\(modelo.rawValue)", directoryHint: .isDirectory)
    }

    /// Só é escrito no fim de um download completo; um download interrompido é retomado.
    private func marcador(_ modelo: WhisperModelo) -> URL {
        pasta(modelo).appending(path: ".apontamentos-completo")
    }

    func estaDescarregado(_ modelo: WhisperModelo) -> Bool {
        FileManager.default.fileExists(atPath: marcador(modelo).path)
    }

    func descarregar(_ modelo: WhisperModelo, progresso: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let pasta = try await WhisperKit.download(variant: modelo.rawValue, downloadBase: base) { p in
            progresso(p.fractionCompleted)
        }
        try Data().write(to: marcador(modelo))
        return pasta
    }

    func apagar(_ modelo: WhisperModelo) throws {
        let pasta = pasta(modelo)
        if FileManager.default.fileExists(atPath: pasta.path) {
            try FileManager.default.removeItem(at: pasta)
        }
    }
}
