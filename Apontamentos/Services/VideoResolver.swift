import Foundation

/// O vídeo fica onde está; a aula guarda o caminho e um security-scoped bookmark,
/// que continua a encontrá-lo se for movido ou renomeado no mesmo disco.
enum VideoResolver {
    enum Estado: Equatable, Sendable {
        case ok(URL)
        /// Encontrado noutro sítio através do bookmark; a referência deve ser atualizada.
        case movido(URL, VideoRef)
        case emFalta(caminho: String)
    }

    static func referencia(para url: URL) -> VideoRef {
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return VideoRef(caminho: url.path, bookmark: bookmark)
    }

    static func resolver(_ ref: VideoRef) -> Estado {
        if let bookmark = ref.bookmark {
            var obsoleto = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &obsoleto),
               FileManager.default.fileExists(atPath: url.path),
               !estaNoLixo(url) {
                let mesmoCaminho = url.resolvingSymlinksInPath().path == URL(fileURLWithPath: ref.caminho).resolvingSymlinksInPath().path
                if obsoleto || !mesmoCaminho {
                    return .movido(url, referencia(para: url))
                }
                return .ok(url)
            }
        }
        let url = URL(fileURLWithPath: ref.caminho)
        if FileManager.default.fileExists(atPath: url.path) { return .ok(url) }
        return .emFalta(caminho: ref.caminho)
    }

    /// Um vídeo no Lixo conta como apagado.
    private static func estaNoLixo(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash")
    }

    /// Dá acesso ao ficheiro durante `corpo`. Fora da sandbox o pedido é inofensivo.
    static func comAcesso<T>(_ url: URL, _ corpo: () async throws -> T) async rethrows -> T {
        let acedeu = url.startAccessingSecurityScopedResource()
        defer { if acedeu { url.stopAccessingSecurityScopedResource() } }
        return try await corpo()
    }
}
