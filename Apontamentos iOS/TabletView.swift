import SwiftUI

/// O iPad: as três colunas do Mac. À esquerda, Por rever, Todas as aulas e as cadeiras; ao meio, as aulas; à
/// direita, a aula para ler (ou "Sobre a cadeira").
struct TabletView: View {
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    var inicial: URL?

    enum Filtro: Hashable { case porRever, todas, cadeira(URL) }
    enum Selecao: Hashable { case aula(URL), completa(URL), sobre(URL) }

    @State private var filtro: Filtro? = .porRever
    @State private var selecao: Selecao?
    @State private var semestre: Semestre?
    @State private var termo = ""

    private var cadeiraEscolhida: Cadeira? {
        guard case .cadeira(let pasta) = filtro else { return nil }
        return library.cadeiras.first { $0.pasta.mesmoCaminho(pasta) }
    }

    private var aulas: [Aula] {
        switch filtro {
        case .porRever, nil: Revisao.porRever(library.cadeiras)
        case .todas: library.cadeiras.flatMap(\.aulas).sorted { $0.meta.data > $1.meta.data }
        case .cadeira: cadeiraEscolhida?.aulas.sorted { $0.meta.data > $1.meta.data } ?? []
        }
    }

    var body: some View {
        NavigationSplitView {
            barraLateral
        } content: {
            lista
        } detail: {
            NavigationStack { detalhe }
        }
        // Resultados da pesquisa e links do painel Estudo (ver o mesmo no `TelefoneView`).
        .onChange(of: navegacao.destino) { _, destino in
            guard let destino else { return }
            termo = ""
            if destino.pasta.lastPathComponent == FichaCadeira.fichaMD {
                selecao = .sobre(destino.pasta.deletingLastPathComponent())
                return
            }
            let simples = destino.tempo == nil && destino.termos.isEmpty && destino.seccao == nil && destino.separador == .apontamentos
            selecao = simples ? .aula(destino.pasta) : .completa(destino.pasta)
            if simples { navegacao.destino = nil }
        }
        .task {
            if let inicial {
                selecao = .aula(inicial)
                filtro = .todas
            }
        }
    }

    private var barraLateral: some View {
        List(selection: $filtro) {
            Section {
                Label("Por rever", systemImage: "circle.inset.filled")
                    .badge(Revisao.porRever(library.cadeiras).count)
                    .tag(Filtro.porRever)
                Label("Todas as aulas", systemImage: "list.bullet")
                    .badge(library.cadeiras.reduce(0) { $0 + $1.aulas.count })
                    .tag(Filtro.todas)
            }
            Section("Cadeiras") {
                ForEach(library.cadeiras(no: semestre)) { cadeira in
                    Label {
                        Text(cadeira.nome)
                    } icon: {
                        SiglaCadeira(nome: cadeira.nome, lado: 22)
                    }
                    .badge(cadeira.aulas.count)
                    .tag(Filtro.cadeira(cadeira.pasta))
                }
            }
        }
        .refreshable { library.recarregar(forcar: true) }
        .navigationTitle("Recap")
        .searchable(text: $termo, placement: .sidebar, prompt: "Procurar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Definições", systemImage: "gearshape") { NotificationCenter.default.post(name: .abrirDefinicoes, object: nil) }
            }
            ToolbarItem(placement: .topBarTrailing) { SeletorSemestre(semestre: $semestre) }
        }
    }

    @ViewBuilder private var lista: some View {
        if !termo.trimmingCharacters(in: .whitespaces).isEmpty {
            ResultadosPesquisaView(termo: termo).navigationTitle("Procurar")
        } else {
            List(selection: $selecao) {
                if let cadeira = cadeiraEscolhida {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sobre a cadeira").font(.headline)
                            Text("Docente, avaliação e programa").font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        SiglaCadeira(nome: cadeira.nome, lado: 32)
                    }
                    .tag(Selecao.sobre(cadeira.pasta))
                }
                ForEach(aulas) { aula in
                    HStack(alignment: .firstTextBaseline) {
                        LinhaAulaIOS(aula: aula, detalhe: "\(Revisao.sigla(aula.cadeira)) · Aula \(library.numeroDaAula(aula)) · \(DataAula.curta(aula.meta.data))")
                        if aula.temApontamentos && !aula.meta.revista {
                            Circle().fill(.tint).frame(width: 10, height: 10).accessibilityLabel("Por rever")
                        }
                    }
                    .tag(Selecao.aula(aula.pasta))
                }
            }
            .refreshable { library.recarregar(forcar: true) }
            .navigationTitle(titulo)
            .navigationSubtitle(aulas.count == 1 ? "1 aula" : "\(aulas.count) aulas")
            .overlay {
                if aulas.isEmpty && filtro == .porRever {
                    ContentUnavailableView("Está tudo revisto", systemImage: "checkmark.circle")
                }
            }
        }
    }

    private var titulo: String {
        switch filtro {
        case .porRever, nil: "Por rever"
        case .todas: "Todas as aulas"
        case .cadeira: cadeiraEscolhida?.nome ?? ""
        }
    }

    @ViewBuilder private var detalhe: some View {
        switch selecao {
        case .aula(let pasta): AulaLeitura(pasta: pasta).id(pasta)
        case .completa(let pasta):
            if let aula = library.aula(em: pasta) { AulaCompletaIOS(aula: aula).id(pasta) }
        case .sobre(let pasta):
            if let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(pasta) }) {
                FichaCadeiraView(cadeira: cadeira).id(pasta).navigationBarTitleDisplayMode(.inline)
            }
        case nil:
            ContentUnavailableView("Escolhe uma aula", systemImage: "book",
                                   description: Text("As aulas gravadas no Mac aparecem aqui pelo iCloud Drive."))
        }
    }
}
