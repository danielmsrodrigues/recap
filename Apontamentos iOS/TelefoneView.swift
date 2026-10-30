import SwiftUI

/// O iPhone: separadores do iOS (Hoje · Cadeiras · Por rever, e Procurar à parte), cada um com a sua pilha.
struct TelefoneView: View {
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    var inicial: URL?

    enum Separador: Hashable { case hoje, cadeiras, porRever, procurar }

    @State private var separador: Separador = .hoje
    @State private var caminhos: [Separador: [DestinoIOS]] = [:]
    @State private var semestre: Semestre?
    @State private var termo = ""
    @State private var aviso = AvisoRevista()

    var body: some View {
        TabView(selection: $separador) {
            Tab("Hoje", systemImage: "calendar", value: .hoje) {
                pilha(.hoje) { HojeView(semestre: $semestre) { separador = .porRever } }
            }
            Tab("Cadeiras", systemImage: "square.grid.2x2", value: .cadeiras) {
                pilha(.cadeiras) { CadeirasView(semestre: $semestre) }
            }
            Tab("Por rever", systemImage: "checkmark.circle", value: .porRever) {
                pilha(.porRever) { PorReverView() }
            }
            .badge(Revisao.porRever(library.cadeiras).count)
            Tab(value: .procurar, role: .search) {
                pilha(.procurar) { ProcurarView(termo: termo) }
                    // Só no separador Procurar: o campo fica na barra de separadores.
                    .searchable(text: $termo, prompt: "Aulas e temas")
            }
        }
        .overlay(alignment: .bottom) {
            if let atual = aviso.atual {
                VistaAvisoRevista(aviso: atual) { proxima in
                    aviso.fechar()
                    abrir(.aula(proxima.pasta), substituindo: true)
                } aoDesfazer: {
                    do { try aviso.desfazer(library) } catch { aviso.erro = error.localizedDescription }
                }
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(aviso)
        .alert("Não foi possível gravar", isPresented: Binding(get: { aviso.erro != nil }, set: { if !$0 { aviso.erro = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aviso.erro ?? "")
        }
        .onChange(of: separador) { aviso.fechar() }
        // Resultados da pesquisa e links do painel Estudo: com um momento ou um texto a realçar, abre a aula completa
        // (que o aplica e o apaga); uma ficha de cadeira abre "Sobre a cadeira" (idem).
        .onChange(of: navegacao.destino) { _, destino in
            guard let destino else { return }
            if destino.pasta.lastPathComponent == FichaCadeira.fichaMD {
                abrir(.sobre(destino.pasta.deletingLastPathComponent()), substituindo: false)
                return
            }
            let simples = destino.tempo == nil && destino.termos.isEmpty && destino.seccao == nil && destino.separador == .apontamentos
            abrir(simples ? .aula(destino.pasta) : .completa(destino.pasta), substituindo: false)
            // A leitura não usa o pedido: se ficasse, a aula completa aplicava-o mais tarde.
            if simples { navegacao.destino = nil }
        }
        .task {
            if let inicial { abrir(.aula(inicial), substituindo: false) }
        }
    }

    private func pilha<Raiz: View>(_ s: Separador, @ViewBuilder raiz: () -> Raiz) -> some View {
        NavigationStack(path: Binding(get: { caminhos[s] ?? [] }, set: { caminhos[s] = $0 })) {
            raiz().navigationDestination(for: DestinoIOS.self) { destino in
                switch destino {
                // Pela pasta: a "Próxima" troca a aula no mesmo sítio da pilha, e as secções abertas são de outra.
                case .aula(let pasta): AulaLeitura(pasta: pasta).id(pasta)
                case .completa(let pasta):
                    if let aula = library.aula(em: pasta) { AulaCompletaIOS(aula: aula).id(pasta) }
                case .cadeira(let pasta): CadeiraView(pasta: pasta)
                case .sobre(let pasta):
                    if let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(pasta) }) {
                        FichaCadeiraView(cadeira: cadeira).navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
    }

    /// No separador aberto. `substituindo`: a aula aberta dá lugar a esta (a "Próxima" do aviso).
    private func abrir(_ destino: DestinoIOS, substituindo: Bool) {
        var c = caminhos[separador] ?? []
        if substituindo, case .aula = c.last { c.removeLast() }
        c.append(destino)
        caminhos[separador] = c
    }
}

/// Hoje: continuar a ler, as aulas por rever e as mais recentes, do semestre escolhido.
private struct HojeView: View {
    @Environment(Library.self) private var library
    @AppStorage("ultimaAulaLida") private var ultimaLida = ""
    @Binding var semestre: Semestre?
    var verPorRever: () -> Void

    private var cadeiras: [Cadeira] { library.cadeiras(no: semestre) }
    private var porRever: [Aula] { Revisao.porRever(cadeiras) }

    /// A última aula aberta, se ainda estiver por rever; senão, a mais recente por rever.
    private var continuar: Aula? {
        if let a = library.aula(em: URL(filePath: ultimaLida)), !ultimaLida.isEmpty, !a.meta.revista, a.temApontamentos { return a }
        return porRever.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let continuar { cartaoContinuar(continuar) }
                if !porRever.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Por rever").font(.title2.bold())
                        Spacer()
                        Button("Ver as \(porRever.count)", action: verPorRever)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(porRever.prefix(6)) { aula in
                                NavigationLink(value: DestinoIOS.aula(aula.pasta)) { cartao(aula) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .padding(.bottom, 26)
                }
                let recentes = Revisao.recentes(cadeiras)
                if !recentes.isEmpty {
                    Text("Aulas recentes").font(.title2.bold()).padding(.horizontal, 20).padding(.bottom, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(recentes.enumerated()), id: \.element.id) { i, aula in
                            if i > 0 { Divider().padding(.leading, 37) }
                            NavigationLink(value: DestinoIOS.aula(aula.pasta)) {
                                LinhaAulaIOS(aula: aula, detalhe: "\(aula.cadeira) · \(DataAula.curta(aula.meta.data))", mostrarRevista: true)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(.background.secondary, in: .rect(cornerRadius: 26))
                    .padding(.horizontal, 16)
                }
                if library.cadeiras.isEmpty {
                    ContentUnavailableView("Ainda sem aulas", systemImage: "book",
                                           description: Text("As aulas gravadas no Mac aparecem aqui pelo iCloud Drive."))
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { library.recarregar(forcar: true) }
        .navigationTitle("Hoje")
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_PT"))))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Definições", systemImage: "gearshape") { NotificationCenter.default.post(name: .abrirDefinicoes, object: nil) }
            }
            ToolbarItem(placement: .topBarTrailing) { SeletorSemestre(semestre: $semestre) }
        }
    }

    private func cartaoContinuar(_ aula: Aula) -> some View {
        NavigationLink(value: DestinoIOS.aula(aula.pasta)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Continuar a ler").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(library.cor(aula.cadeira))
                Text(aula.meta.titulo).font(.title3.bold()).multilineTextAlignment(.leading)
                Text("\(aula.cadeira) · Aula \(library.numeroDaAula(aula))").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                LinearGradient(colors: [library.cor(aula.cadeira).opacity(0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 26))
            .background(.background.secondary, in: .rect(cornerRadius: 26))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
    }

    private func cartao(_ aula: Aula) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(aula.cadeira).lineLimit(1)
            } icon: {
                RoundedRectangle(cornerRadius: 3).fill(library.cor(aula.cadeira)).frame(width: 8, height: 8)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(library.cor(aula.cadeira))
            Text(aula.meta.titulo).font(.headline).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            Text("Aula \(library.numeroDaAula(aula)) · \(DataAula.curta(aula.meta.data))").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: 236, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .contentShape(.rect)
    }
}

/// As cadeiras do semestre, em cartões com o que falta rever.
private struct CadeirasView: View {
    @Environment(Library.self) private var library
    @Binding var semestre: Semestre?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(library.cadeiras(no: semestre)) { cadeira in
                    NavigationLink(value: DestinoIOS.cadeira(cadeira.pasta)) { cartao(cadeira) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { library.recarregar(forcar: true) }
        .navigationTitle("Cadeiras")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SeletorSemestre(semestre: $semestre) } }
        .overlay {
            if library.cadeiras.isEmpty {
                ContentUnavailableView("Ainda sem cadeiras", systemImage: "square.grid.2x2",
                                       description: Text("As cadeiras criadas no Mac aparecem aqui pelo iCloud Drive."))
            }
        }
    }

    private func cartao(_ cadeira: Cadeira) -> some View {
        let comApontamentos = cadeira.aulas.filter(\.temApontamentos)
        let porRever = Revisao.porRever([cadeira]).count
        return VStack(alignment: .leading, spacing: 10) {
            SiglaCadeira(nome: cadeira.nome)
            Text(cadeira.nome).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            ProgressView(value: Double(comApontamentos.count - porRever), total: Double(max(1, comApontamentos.count)))
                .tint(library.cor(cadeira.nome))
            Text(porRever > 0 ? "\(porRever) por rever" : "Tudo revisto")
                .font(.caption).foregroundStyle(porRever > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .contentShape(.rect)
    }
}

/// Uma cadeira: "Sobre a cadeira" e as aulas, com o círculo para marcar como revista.
struct CadeiraView: View {
    let pasta: URL
    @Environment(Library.self) private var library
    @Environment(AvisoRevista.self) private var aviso: AvisoRevista?

    private var cadeira: Cadeira? { library.cadeiras.first { $0.pasta.mesmoCaminho(pasta) } }

    var body: some View {
        if let cadeira {
            List {
                Section {
                    HStack(spacing: 14) {
                        SiglaCadeira(nome: cadeira.nome, lado: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cadeira.nome).font(.title2.bold())
                            Text(cadeira.aulas.count == 1 ? "1 aula" : "\(cadeira.aulas.count) aulas").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    NavigationLink(value: DestinoIOS.sobre(cadeira.pasta)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sobre a cadeira")
                            Text("Docente, avaliação e programa").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Aulas") {
                    ForEach(cadeira.aulas.sorted { $0.meta.data < $1.meta.data }) { aula in
                        HStack(spacing: 12) {
                            BotaoRevista(aula: aula) { marcar(aula) }
                            NavigationLink(value: DestinoIOS.aula(aula.pasta)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(aula.meta.titulo)
                                    Text("Aula \(library.numeroDaAula(aula)) · \(DataAula.curta(aula.meta.data))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Cadeira não encontrada", systemImage: "questionmark.folder")
        }
    }

    /// Com o aviso ao marcar, para se poder desfazer um toque por engano.
    private func marcar(_ aula: Aula) {
        do {
            if let aviso {
                try aviso.marcar(aula, revista: !aula.meta.revista, library: library, mostrar: true)
            } else {
                try library.definirRevista(!aula.meta.revista, em: aula.pasta)
            }
        } catch {
            aviso?.erro = error.localizedDescription
        }
    }
}

/// Por rever: todas as aulas ainda por rever, por cadeira; o círculo marca sem abrir.
private struct PorReverView: View {
    @Environment(Library.self) private var library
    @Environment(AvisoRevista.self) private var aviso

    var body: some View {
        let porRever = Revisao.porRever(library.cadeiras)
        List {
            ForEach(library.cadeiras) { cadeira in
                let aulas = Revisao.porRever([cadeira])
                if !aulas.isEmpty {
                    Section {
                        ForEach(aulas) { aula in
                            HStack(spacing: 12) {
                                // Com o aviso: a aula sai da lista, e um toque por engano desfaz-se.
                                BotaoRevista(aula: aula) {
                                    do { try aviso.marcar(aula, revista: true, library: library, mostrar: true) }
                                    catch { aviso.erro = error.localizedDescription }
                                }
                                NavigationLink(value: DestinoIOS.aula(aula.pasta)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(aula.meta.titulo)
                                        Text("Aula \(library.numeroDaAula(aula)) · \(DataAula.curta(aula.meta.data))")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label {
                            Text(cadeira.nome)
                        } icon: {
                            RoundedRectangle(cornerRadius: 3).fill(library.cor(cadeira.nome)).frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .refreshable { library.recarregar(forcar: true) }
        .navigationTitle("Por rever")
        .navigationSubtitle(porRever.isEmpty ? "" : "\(porRever.count) \(porRever.count == 1 ? "aula" : "aulas") · toca no círculo para marcar")
        .overlay {
            if porRever.isEmpty {
                ContentUnavailableView("Está tudo revisto", systemImage: "checkmark.circle")
            }
        }
    }
}

/// Procurar: o campo está na barra de separadores; os resultados são os da pesquisa do Mac.
private struct ProcurarView: View {
    let termo: String

    var body: some View {
        Group {
            if termo.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Procurar nas aulas", systemImage: "magnifyingglass",
                                       description: Text("Títulos, apontamentos, transcrições e fichas das cadeiras."))
            } else {
                ResultadosPesquisaView(termo: termo)
            }
        }
        .navigationTitle("Procurar")
    }
}
