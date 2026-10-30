#if os(macOS)
import SwiftUI

/// No Início do Mac: quando a pasta Recap do iCloud Drive já existe (criada pelo iPhone ou pelo iPad) e as aulas
/// ainda estão em ~/Aulas, propõe mudá-las para lá. Só muda quando se carrega no botão.
struct MudarParaICloud: View {
    @Environment(Library.self) private var library
    @Environment(Definicoes.self) private var definicoes
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var direto
    @State private var mostrar = false
    @State private var aMudar = false
    @State private var erro: String?

    private var ocupada: Bool { fila.jobs.contains(where: \.ativo) || direto.ativa }

    var body: some View {
        Group {
            if mostrar {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Aulas no iPhone e no iPad", systemImage: "icloud").font(.headline)
                    Text("Já há uma pasta Recap no iCloud Drive. Muda as aulas de ~/Aulas para lá e passam a aparecer sozinhas no iPhone e no iPad.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let erro { Text(erro).font(.callout).foregroundStyle(.red) }
                    HStack {
                        Button(aMudar ? "A mudar…" : "Mudar para o iCloud Drive") { mudar() }
                            .buttonStyle(.borderedProminent)
                            .disabled(aMudar || ocupada)
                        if ocupada { Text("Espera que a aula em curso acabe.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.08), in: .rect(cornerRadius: 14))
            }
        }
        .task(id: library.versao) {
            mostrar = PastaICloud.deveOferecerMudanca(pastaEscolhida: definicoes.pastaAulas)
        }
    }

    private func mudar() {
        aMudar = true
        erro = nil
        let origem = library.raiz, destino = PastaICloud.documentosMac()
        Task {
            do {
                // Na mesma pasta pessoal: são só mudanças de nome, mas fora da thread principal na mesma.
                let ficaram = try await Task.detached { try PastaICloud.mudar(de: origem, para: destino) }.value
                try library.mudarRaiz(para: destino, mover: false)
                definicoes.pastaAulas = destino.path
                if !ficaram.isEmpty {
                    erro = "Ficaram em ~/Aulas \(ficaram.count) ficheiro(s) que já existiam no iCloud: \(ficaram.prefix(3).joined(separator: ", "))."
                }
                mostrar = !ficaram.isEmpty
            } catch {
                erro = "Não foi possível mudar as aulas: \(error.localizedDescription)"
            }
            aMudar = false
        }
    }
}
#endif
