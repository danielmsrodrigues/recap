import SwiftUI

/// Por agora só a lista das cadeiras e das aulas (fase 1): a aula abre-se nas fases seguintes.
struct InicioIOS: View {
    @State private var library: Library
    @State private var definicoes = Definicoes()
    @Environment(\.scenePhase) private var fase

    init(raiz: URL) {
        let d = Definicoes()
        _definicoes = State(initialValue: d)
        _library = State(initialValue: Library(raiz: raiz, organizacao: d.organizacao,
                                               iniciosPeriodos: d.iniciosPeriodos, duracaoCurso: d.duracaoCurso))
    }

    var body: some View {
        NavigationSplitView {
            List {
                if let erro = library.erro {
                    Text(erro).foregroundStyle(.red)
                }
                ForEach(library.cadeirasPorSemestre, id: \.semestre) { grupo in
                    Section(library.nome(grupo.semestre)) {
                        ForEach(grupo.cadeiras) { cadeira in
                            NavigationLink(value: cadeira.pasta) {
                                LabeledContent(cadeira.nome, value: "\(cadeira.aulas.count)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recap")
            .navigationDestination(for: URL.self) { pasta in
                if let cadeira = library.cadeiras.first(where: { $0.pasta.mesmoCaminho(pasta) }) {
                    List(cadeira.aulas) { aula in
                        VStack(alignment: .leading) {
                            Text(aula.meta.titulo)
                            Text(aula.meta.data, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(cadeira.nome)
                }
            }
            .refreshable { library.recarregar() }
        } detail: {
            ContentUnavailableView("Escolhe uma aula", systemImage: "book")
        }
        .onChange(of: fase) { if fase == .active { library.recarregar() } }
    }
}

struct EscolherPastaView: View {
    @Environment(PastaAulas.self) private var pasta
    @State private var aEscolher = false
    @State private var erro: String?

    var body: some View {
        ContentUnavailableView {
            Label("Escolhe a pasta das aulas", systemImage: "folder")
        } description: {
            Text("A mesma pasta do iCloud Drive que o Recap usa no Mac (Definições → Aulas).")
            if let e = erro ?? pasta.erro { Text(e).foregroundStyle(.red) }
        } actions: {
            Button("Escolher pasta…") { aEscolher = true }
                .buttonStyle(.borderedProminent)
        }
        .fileImporter(isPresented: $aEscolher, allowedContentTypes: [.folder]) { resultado in
            do { try pasta.escolher(resultado.get()) } catch { erro = error.localizedDescription }
        }
    }
}
