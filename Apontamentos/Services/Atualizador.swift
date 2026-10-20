import AppKit
import Foundation
import Observation
import Security

/// Procura versões novas nas releases do GitHub e atualiza a app no sítio.
///
/// A versão nova só é aceite se estiver assinada com o mesmo certificado desta (o "designated requirement"
/// da app em execução), para que um zip trocado no caminho não seja instalado.
@MainActor @Observable
final class Atualizador {
    enum Estado: Equatable {
        case parado
        case aProcurar
        case disponivel(versao: String)
        case aInstalar(versao: String)
        case emDia
        case falhou(String)
        /// O macOS não deixou a app substituir-se (Definições → Privacidade e Segurança → Gestão de apps).
        case semPermissao
    }

    nonisolated static let repositorio = "danielmsrodrigues/recap"
    private static let chaveUltimaProcura = "ultimaProcuraAtualizacao"

    private(set) var estado: Estado = .parado
    /// A versão encontrada pela última procura. Fica guardada aqui, e não só no estado, porque o botão
    /// "Atualizar agora" fecha o aviso (e `dispensar()` põe o estado em `.parado`) antes de `instalar()` correr.
    private var encontrada: Release?

    static var versaoAtual: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Ao arrancar: no máximo uma vez por dia, e sem mostrar nada se não houver novidades ou não houver rede.
    func procurarSeForAltura() async {
        let ultima = UserDefaults.standard.double(forKey: Self.chaveUltimaProcura)
        guard Date.now.timeIntervalSince1970 - ultima > 20 * 3600 else { return }
        await procurar(silencioso: true)
    }

    func procurar(silencioso: Bool = false) async {
        guard estado != .aProcurar else { return }
        if case .aInstalar = estado { return }
        estado = .aProcurar
        do {
            let ultima = try await Self.ultimaRelease()
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.chaveUltimaProcura)
            if Self.maisRecente(ultima.versao, que: Self.versaoAtual) {
                encontrada = ultima
                estado = .disponivel(versao: ultima.versao)
            } else {
                estado = silencioso ? .parado : .emDia
            }
        } catch {
            estado = silencioso ? .parado : .falhou("Não foi possível procurar atualizações: \(error.localizedDescription)")
        }
    }

    func dispensar() {
        if case .aInstalar = estado { return }
        estado = .parado
    }

    /// Descarrega, verifica a assinatura, troca a app e volta a abri-la.
    func instalar() async {
        guard let encontrada else { return }
        if case .aInstalar = estado { return }
        estado = .aInstalar(versao: encontrada.versao)
        do {
            let nova = try await Self.descarregar(encontrada.zip)
            try Self.verificarAssinatura(nova)
            // O script fica pronto antes da troca: depois dela a app tem de fechar, mesmo que algo falhe.
            let reabrir = try Self.scriptReabrir(Bundle.main.bundleURL, descarregada: nova)
            try await Self.trocar(por: nova)
            try? reabrir.run()
            NSApp.terminate(nil)
        } catch Erro.semPermissao {
            estado = .semPermissao
        } catch {
            estado = .falhou("A atualização falhou: \(error.localizedDescription)")
        }
    }

    // MARK: Passos

    struct Release: Sendable { var versao: String; var zip: URL }

    enum Erro: LocalizedError {
        case semZip, descompactar, assinatura, naoInstalada, semPermissao, copiar, copiarSemRepor
        var errorDescription: String? {
            switch self {
            case .semZip: "a versão publicada não tem o ficheiro Recap.zip."
            case .descompactar: "não foi possível abrir o ficheiro descarregado."
            case .assinatura: "a versão descarregada não está assinada pelo mesmo autor desta app."
            case .naoInstalada: "esta cópia do Recap não está numa pasta onde se possa atualizar."
            case .semPermissao: "o macOS não deixou o Recap substituir-se."
            case .copiar: "não foi possível copiar a versão nova. Ficou a versão que tinhas."
            case .copiarSemRepor: "não foi possível copiar a versão nova, nem repor a anterior. Ela está em Recap.app.antiga, na mesma pasta: muda-lhe o nome para Recap.app."
            }
        }
    }

    @concurrent
    static func ultimaRelease() async throws -> Release {
        struct Resposta: Decodable {
            struct Ficheiro: Decodable { var name: String; var browser_download_url: URL }
            var tag_name: String
            var assets: [Ficheiro]
        }
        #if DEBUG
        // `RECAP_ATUALIZACAO_ZIP=<url>` e `RECAP_ATUALIZACAO_VERSAO=<x.y>`: testar a atualização sem publicar nada.
        let env = ProcessInfo.processInfo.environment
        if let zip = env["RECAP_ATUALIZACAO_ZIP"].flatMap(URL.init(string:)), let versao = env["RECAP_ATUALIZACAO_VERSAO"] {
            return Release(versao: versao, zip: zip)
        }
        #endif
        var pedido = URLRequest(url: URL(string: "https://api.github.com/repos/\(repositorio)/releases/latest")!)
        pedido.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        pedido.timeoutInterval = 15
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        guard (resposta as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let r = try JSONDecoder().decode(Resposta.self, from: dados)
        guard let zip = r.assets.first(where: { $0.name == "Recap.zip" })?.browser_download_url else { throw Erro.semZip }
        return Release(versao: r.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")), zip: zip)
    }

    /// "1.10" é mais recente do que "1.9": compara número a número.
    nonisolated static func maisRecente(_ a: String, que b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Descarrega o zip para uma pasta temporária e devolve o `Recap.app` lá dentro.
    @concurrent
    private static func descarregar(_ zip: URL) async throws -> URL {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "Recap-atualizacao-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        let (ficheiro, _) = try await URLSession.shared.download(from: zip)
        let destino = pasta.appending(path: "Recap.zip")
        try FileManager.default.moveItem(at: ficheiro, to: destino)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", destino.path, pasta.path]
        try p.run()
        p.waitUntilExit()
        let app = pasta.appending(path: "Recap.app", directoryHint: .isDirectory)
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else { throw Erro.descompactar }
        return app
    }

    /// A app nova tem de cumprir o "designated requirement" desta (mesmo identificador e mesmo certificado).
    nonisolated static func verificarAssinatura(_ app: URL) throws {
        var eu: SecCode?
        var requisito: SecRequirement?
        var nova: SecStaticCode?
        guard SecCodeCopySelf([], &eu) == errSecSuccess, let eu else { throw Erro.assinatura }
        var estatico: SecStaticCode?
        guard SecCodeCopyStaticCode(eu, [], &estatico) == errSecSuccess, let estatico,
              SecCodeCopyDesignatedRequirement(estatico, [], &requisito) == errSecSuccess, let requisito,
              SecStaticCodeCreateWithPath(app as CFURL, [], &nova) == errSecSuccess, let nova,
              SecStaticCodeCheckValidity(nova, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate), requisito) == errSecSuccess
        else { throw Erro.assinatura }
    }

    /// Põe a versão nova no lugar desta; a app em execução continua a correr a partir da cópia antiga, ao lado.
    /// A troca é feita aqui, e não no script que reabre a app, para que uma recusa apareça como erro: quando
    /// o macOS a recusava (a app não tem Team ID, por isso precisa de "Gestão de apps"), o script saía calado
    /// e a app fechava sem voltar a abrir, na versão antiga.
    @concurrent
    private static func trocar(por nova: URL) async throws {
        let fm = FileManager.default
        let atual = Bundle.main.bundleURL
        guard atual.pathExtension == "app", fm.isWritableFile(atPath: atual.deletingLastPathComponent().path) else {
            throw Erro.naoInstalada
        }
        let antiga = URL(fileURLWithPath: atual.path + ".antiga")
        try? fm.removeItem(at: antiga)
        do {
            try fm.moveItem(at: atual, to: antiga)
        } catch {
            throw semPermissao(error) ? Erro.semPermissao : error
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [nova.path, atual.path]
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw Erro.copiar }
        } catch {
            try? fm.removeItem(at: atual)
            do { try fm.moveItem(at: antiga, to: atual) } catch { throw Erro.copiarSemRepor }
            throw Erro.copiar
        }
    }

    private nonisolated static func semPermissao(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && e.code == NSFileWriteNoPermissionError { return true }
        let posix = (e.userInfo[NSUnderlyingErrorKey] as? NSError) ?? e
        return posix.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(posix.code)
    }

    /// Um script que espera que esta app feche, apaga a cópia antiga e o que foi descarregado, e abre a nova.
    private static func scriptReabrir(_ atual: URL, descarregada nova: URL) throws -> Process {
        let script = nova.deletingLastPathComponent().appending(path: "reabrir.sh")
        let conteudo = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        ATUAL="$1"; NOVA="$2"
        rm -rf "${ATUAL}.antiga"
        /usr/bin/open "${ATUAL}"
        rm -rf "$(dirname "${NOVA}")"
        """
        try conteudo.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "/bin/sh \"$0\" \"$1\" \"$2\" >/dev/null 2>&1 &", script.path, atual.path, nova.path]
        return p
    }
}
