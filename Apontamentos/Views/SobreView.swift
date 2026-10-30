import SwiftUI

/// "Sobre o Recap": a versão instalada e o que veio com cada versão, da mais recente para a mais antiga.
struct SobreView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("Recap").font(.largeTitle.bold())
                    Text("Versão \(Novidades.atual)").foregroundStyle(.secondary)
                    Text("Transcreve as aulas e faz os apontamentos com o Claude.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            ForEach(Novidades.todas) { versao in
                Section {
                    ItensNovidade(itens: versao.itens)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Versão \(versao.numero)").font(.headline)
                        Spacer()
                        Text(versao.data).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Sobre o Recap")
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 620)
        #endif
    }
}

/// Os pontos de uma versão.
private struct ItensNovidade: View {
    let itens: [String]

    var body: some View {
        ForEach(itens, id: \.self) { item in
            Label {
                Text(item).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "sparkle").foregroundStyle(.tint)
            }
        }
    }
}

/// "O que há de novo", uma vez depois de cada atualização, só com as versões que ainda não se viram.
struct NovidadesView: View {
    let versoes: [Novidades.Versao]
    var aoFechar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(versoes.count == 1 ? "O que há de novo na \(versoes[0].numero)" : "O que há de novo")
                .font(.title2.bold())
                .padding(.top, 24)
                .padding(.bottom, 8)
            List {
                ForEach(versoes) { versao in
                    Section(versoes.count == 1 ? "" : "Versão \(versao.numero)") {
                        ItensNovidade(itens: versao.itens)
                    }
                }
            }
            Button(action: aoFechar) {
                Text("Continuar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(20)
        }
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
    }
}

/// Mostra "O que há de novo" depois de uma atualização. Numa instalação nova não mostra nada; quem já usava o Recap
/// antes de isto existir vê as novidades da versão atual.
struct ComNovidades: ViewModifier {
    @Environment(Library.self) private var library
    @State private var porVer: [Novidades.Versao] = []

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { !porVer.isEmpty }, set: { if !$0 { fechar() } })) {
                NovidadesView(versoes: porVer) { fechar() }
            }
            .task {
                let defaults = UserDefaults.standard
                let atual = Novidades.atual
                var ultima = defaults.string(forKey: Novidades.chaveUltimaVista)
                // Sem registo, mas com aulas: já usava o Recap antes disto; vê as novidades desta versão.
                if ultima == nil, !library.cadeiras.isEmpty {
                    ultima = Novidades.todas.first { Novidades.menor($0.numero, atual) }?.numero
                }
                porVer = Novidades.porVer(ultimaVista: ultima, atual: atual)
                if porVer.isEmpty { defaults.set(atual, forKey: Novidades.chaveUltimaVista) }
            }
    }

    private func fechar() {
        UserDefaults.standard.set(Novidades.atual, forKey: Novidades.chaveUltimaVista)
        porVer = []
    }
}
