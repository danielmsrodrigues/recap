import CoreGraphics
import Security
import SwiftUI

/// O que falta para o Recap funcionar num Mac novo: Claude Code com sessão iniciada, modelo do Whisper
/// e (para transcrever em direto) a autorização de gravação de ecrã. Abre sozinha no primeiro arranque.
struct PreparacaoView: View {
    @Environment(Definicoes.self) private var definicoes
    @Environment(\.dismiss) private var dismiss

    @State private var claudeInstalado = false
    @State private var sessaoClaude = false
    @State private var modeloPronto = false
    @State private var gravacao = false
    @State private var aInstalarClaude = false
    @State private var progressoModelo: Double?
    @State private var erro: String?
    private let store = ModelStore()

    /// Falta algo essencial (o assistente abre sozinho ao arrancar).
    @MainActor
    static func faltaAlgo(_ definicoes: Definicoes) -> Bool {
        let motorPronto = definicoes.motor == .api ? definicoes.temChaveAPI
            : (definicoes.claudeCode != nil && temSessaoClaude())
        return !motorPronto || !ModelStore().estaDescarregado(definicoes.modeloWhisper)
    }

    /// O Claude Code guarda o login na Keychain; ler só os atributos não pede autorização.
    static func temSessaoClaude() -> Bool {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultado: CFTypeRef?
        return SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preparar o Recap").font(.title2.bold())
                    Text("Três passos, só desta vez.").foregroundStyle(.secondary)
                }
            }

            passo(1, "Claude", feito: claudeInstalado && sessaoClaude,
                  detalhe: !claudeInstalado ? "Escreve os apontamentos com a tua conta Claude (Pro ou Max). Falta instalar o Claude Code."
                      : (sessaoClaude ? "Instalado e com sessão iniciada." : "Instalado. Falta iniciar sessão com a tua conta Claude.")) {
                if !claudeInstalado {
                    if aInstalarClaude {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Instalar") { Task { await instalarClaude() } }
                    }
                } else if !sessaoClaude {
                    Button("Iniciar sessão") { iniciarSessao() }
                }
            }

            passo(2, "Modelo de transcrição", feito: modeloPronto,
                  detalhe: modeloPronto ? "Descarregado." : "O Whisper transcreve as aulas no teu Mac. São cerca de 1,5 GB, descarregados uma vez.") {
                if let p = progressoModelo {
                    ProgressView(value: p).frame(width: 120)
                } else if !modeloPronto {
                    Button("Descarregar") { Task { await descarregarModelo() } }
                }
            }

            passo(3, "Transcrever em direto (opcional)", feito: gravacao,
                  detalhe: gravacao ? "Autorizado." : "Para ouvir uma aula a tocar no browser, o macOS pede autorização de gravação de ecrã e áudio. Depois de autorizar, volta a abrir o Recap.") {
                if !gravacao {
                    Button("Autorizar") { autorizarGravacao() }
                }
            }

            if let erro {
                Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Podes voltar aqui em Recap → Preparar o Recap…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(claudeInstalado && sessaoClaude && modeloPronto ? "Começar" : "Mais tarde") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { await verificar() }
        // Ao voltar do Terminal (login) ou das Definições do Sistema.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await verificar() }
        }
    }

    private func passo(_ n: Int, _ titulo: String, feito: Bool, detalhe: String,
                       @ViewBuilder acao: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(feito ? Color.green : Color.secondary.opacity(0.18)).frame(width: 26, height: 26)
                if feito {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(n)").font(.callout.bold()).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.headline)
                Text(detalhe).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            acao()
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
    }

    // MARK: Ações

    private func verificar() async {
        claudeInstalado = definicoes.claudeCode != nil
        sessaoClaude = Self.temSessaoClaude()
        modeloPronto = store.estaDescarregado(definicoes.modeloWhisper)
        gravacao = CGPreflightScreenCaptureAccess()
    }

    /// O instalador oficial do Claude Code (instala em ~/.local/bin/claude, sem pedir a palavra-passe).
    private func instalarClaude() async {
        aInstalarClaude = true
        erro = nil
        defer { aInstalarClaude = false }
        let (codigo, saida) = await Self.correr("/bin/bash", ["-c", "curl -fsSL https://claude.ai/install.sh | bash"])
        await verificar()
        if codigo != 0 || !claudeInstalado {
            erro = "Não foi possível instalar o Claude Code: \(saida.suffix(300))"
        }
    }

    /// Abre o Terminal com o Claude Code: o login é feito lá, no browser.
    private func iniciarSessao() {
        guard let claude = definicoes.claudeCode else { return }
        let script = FileManager.default.temporaryDirectory.appending(path: "Recap-login.command")
        let conteudo = """
        #!/bin/zsh
        clear
        echo "Inicia sessão com a tua conta Claude. Quando terminares, escreve /exit e volta ao Recap."
        echo
        '\(claude.path)'
        """
        do {
            try conteudo.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            erro = "Não foi possível abrir o Terminal: \(error.localizedDescription)"
        }
    }

    private func descarregarModelo() async {
        progressoModelo = 0
        erro = nil
        defer { progressoModelo = nil }
        do {
            _ = try await store.descarregar(definicoes.modeloWhisper) { p in
                Task { @MainActor in progressoModelo = p }
            }
        } catch {
            erro = "Falhou o download do modelo: \(error.localizedDescription)"
        }
        await verificar()
    }

    private func autorizarGravacao() {
        // Da primeira vez o macOS mostra o pedido; depois disso só nas Definições do Sistema.
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    @concurrent
    private static func correr(_ executavel: String, _ argumentos: [String]) async -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executavel)
        p.arguments = argumentos
        let saida = Pipe()
        p.standardOutput = saida
        p.standardError = saida
        guard (try? p.run()) != nil else { return (-1, "não foi possível correr \(executavel)") }
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: dados, encoding: .utf8) ?? "")
    }
}
