import Foundation
#if os(macOS)
import CoreServices
#endif

/// Avisa (no fio principal, com ~1 s de folga para juntar rajadas) quando algo muda dentro da pasta das aulas
/// sem ter sido esta app: o iCloud Drive a trazer o que se fez no outro dispositivo.
///
/// No Mac usa FSEvents, que já ignora as escritas do próprio processo. No iOS é um `NSFilePresenter`
/// (o iCloud Drive coordena as escritas que traz), e as nossas escritas ignoram-se por `Disco.gravadoHaPouco`.
@MainActor
final class ObservadorPasta {
    private let aoMudar: @MainActor () -> Void
    private let raiz: URL
    private var pendente: Task<Void, Never>?
    #if os(macOS)
    private var stream: FSEventStreamRef?
    #else
    private var presenter: Presenter?
    #endif

    /// Os pedidos entre o iPhone e o Mac mudam a cada poucos segundos enquanto o Mac responde, e cada lado já os vigia
    /// sozinho (`PonteMac`, `Estudo`): não obrigam a reler a biblioteca toda.
    nonisolated static func ignorar(_ caminho: String, raiz: URL) -> Bool {
        let pedidos = raiz.appending(path: Disco.pastaSistema).appending(path: "pedidos").standardizedFileURL.path
        return caminho == pedidos || caminho.hasPrefix(pedidos + "/")
    }

    init(_ raiz: URL, aoMudar: @escaping @MainActor () -> Void) {
        self.aoMudar = aoMudar
        self.raiz = raiz
        #if os(macOS)
        var contexto = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let chamada: FSEventStreamCallback = { _, info, _, caminhos, _, _ in
            guard let info else { return }
            let observador = Unmanaged<ObservadorPasta>.fromOpaque(info).takeUnretainedValue()
            let lista = (Unmanaged<CFArray>.fromOpaque(caminhos).takeUnretainedValue() as? [String]) ?? []
            MainActor.assumeIsolated {
                guard lista.isEmpty || lista.contains(where: { !ObservadorPasta.ignorar($0, raiz: observador.raiz) }) else { return }
                observador.mudou()
            }
        }
        stream = FSEventStreamCreate(nil, chamada, &contexto, [raiz.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     1.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
        #else
        let p = Presenter(raiz) { [weak self] url in
            guard !Disco.gravadoHaPouco(url), !Self.ignorar(url.standardizedFileURL.path, raiz: raiz) else { return }
            self?.mudou()
        }
        NSFileCoordinator.addFilePresenter(p)
        presenter = p
        #endif
    }

    isolated deinit {
        pendente?.cancel()
        #if os(macOS)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        #else
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        #endif
    }

    private func mudou() {
        pendente?.cancel()
        pendente = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.aoMudar()
        }
    }

    #if !os(macOS)
    private final class Presenter: NSObject, NSFilePresenter {
        let presentedItemURL: URL?
        let presentedItemOperationQueue = OperationQueue.main
        private let aoMudar: @MainActor @Sendable (URL) -> Void

        init(_ raiz: URL, aoMudar: @escaping @MainActor @Sendable (URL) -> Void) {
            presentedItemURL = raiz
            self.aoMudar = aoMudar
        }

        func presentedSubitemDidChange(at url: URL) { avisar(url) }
        func presentedSubitemDidAppear(at url: URL) { avisar(url) }
        func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
            avisar(url)
            completionHandler(nil)
        }

        private func avisar(_ url: URL) {
            let aoMudar = aoMudar
            MainActor.assumeIsolated { aoMudar(url) }
        }
    }
    #endif
}
