import AppKit
import Darwin

/// O Chrome (e os outros browsers Chromium) deixa de desenhar uma janela que não se vê: noutro desktop,
/// atrás de uma app em ecrã inteiro… O vídeo pára e as capturas para os slides saem pretas.
/// Aberto com `--disable-backgrounding-occluded-windows`, continua a desenhá-la. A opção vale para o
/// browser inteiro (todos os perfis) e só enquanto ele estiver aberto: reaberto pelo Dock, volta ao normal.
@MainActor
enum NavegadorAcordado {
    static let opcao = "--disable-backgrounding-occluded-windows"

    /// Browsers Chromium (aceitam a opção), com o nome a mostrar.
    static let chromium = ["com.google.Chrome": "Chrome", "com.microsoft.edgemac": "Edge", "com.brave.Browser": "Brave"]

    enum Estado: Equatable {
        /// Não é um browser Chromium: a opção não existe.
        case naoSeAplica
        case precisaReabrir
        case pronto
    }

    enum Erro: LocalizedError {
        case naoFechou(String)
        case naoAbriu(String, String)

        var errorDescription: String? {
            switch self {
            case .naoFechou(let nome):
                "O \(nome) não fechou. Pode estar a perguntar alguma coisa (por exemplo, por causa de uma transferência): responde-lhe e tenta outra vez."
            case .naoAbriu(let nome, let detalhe):
                "O \(nome) fechou mas não voltou a abrir: \(detalhe). Abre-o à mão; os separadores voltam com ⌘⇧T."
            }
        }
    }

    static func estado(bundleID: String, pid: pid_t) -> Estado {
        guard chromium[bundleID] != nil else { return .naoSeAplica }
        return argumentos(pid: pid).contains(opcao) ? .pronto : .precisaReabrir
    }

    /// Fecha o browser e volta a abri-lo com a opção e os separadores que tinha.
    static func reabrir(bundleID: String) async throws {
        let nome = chromium[bundleID] ?? bundleID
        let abertos = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let url = abertos.first?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw Erro.naoAbriu(nome, "não o encontrei nas Aplicações")
        }
        try await fechar(abertos, nome: nome)
        // --restore-last-session: os separadores voltam mesmo que o browser esteja configurado para abrir uma página nova.
        try await abrir(url, argumentos: [opcao, "--restore-last-session"], nome: nome)
    }

    /// Pede para fechar como o ⌘Q; se não der (ou não chegar a fechar), manda o SIGTERM,
    /// que o Chrome também trata como um fecho normal e grava a sessão.
    static func fechar(_ apps: [NSRunningApplication], nome: String) async throws {
        for app in apps where !app.terminate() { kill(app.processIdentifier, SIGTERM) }
        if await esperarFecho(apps, segundos: 8) { return }
        for app in apps where !app.isTerminated { kill(app.processIdentifier, SIGTERM) }
        guard await esperarFecho(apps, segundos: 7) else { throw Erro.naoFechou(nome) }
    }

    static func abrir(_ url: URL, argumentos: [String], nome: String, novaInstancia: Bool = false) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = argumentos
        config.createsNewApplicationInstance = novaInstancia
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            throw Erro.naoAbriu(nome, error.localizedDescription)
        }
    }

    private static func esperarFecho(_ apps: [NSRunningApplication], segundos: Double) async -> Bool {
        let limite = Date.now.addingTimeInterval(segundos)
        while Date.now < limite {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return apps.allSatisfy(\.isTerminated)
    }

    /// Os argumentos com que um processo foi aberto (como no `ps`), sem o executável.
    nonisolated static func argumentos(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var tamanho = 0
        guard sysctl(&mib, 3, nil, &tamanho, nil, 0) == 0, tamanho > MemoryLayout<Int32>.size else { return [] }
        var dados = [UInt8](repeating: 0, count: tamanho)
        guard sysctl(&mib, 3, &dados, &tamanho, nil, 0) == 0, tamanho > MemoryLayout<Int32>.size else { return [] }
        // Formato: argc (Int32), o caminho do executável, zeros de alinhamento, depois argv[0], argv[1]…
        let argc = Int(dados.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < tamanho, dados[i] != 0 { i += 1 }
        while i < tamanho, dados[i] == 0 { i += 1 }
        var resultado: [String] = []
        while resultado.count < argc, i < tamanho {
            let inicio = i
            while i < tamanho, dados[i] != 0 { i += 1 }
            resultado.append(String(decoding: dados[inicio..<i], as: UTF8.self))
            i += 1
        }
        return Array(resultado.dropFirst())
    }
}
