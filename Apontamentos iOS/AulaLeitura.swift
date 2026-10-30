import SwiftUI

/// Uma aula para ler, no iPhone e no iPad: o resumo e as secções dos apontamentos, que abrem e fecham, e
/// "Marcar como revista". A transcrição, os slides e as perguntas ficam no menu, fora do caminho.
struct AulaLeitura: View {
    let pasta: URL
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    /// Só no iPhone: marcar dentro da aula mostra o aviso com a próxima.
    @Environment(AvisoRevista.self) private var aviso: AvisoRevista?
    @AppStorage("ultimaAulaLida") private var ultimaLida = ""

    @State private var partes: SeccoesApontamentos.Partidos?
    @State private var abertas: Set<Int> = [0]
    @State private var perguntar = false
    @State private var verCompleta = false

    private var aula: Aula? { library.aula(em: pasta) }

    var body: some View {
        if let aula {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    cabecalho(aula)
                    if let partes {
                        conteudo(partes, aula: aula)
                    } else if !aula.temApontamentos {
                        ContentUnavailableView("Ainda sem apontamentos", systemImage: "doc.text",
                                               description: Text("Os apontamentos são feitos no Mac e aparecem aqui pelo iCloud Drive."))
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { barra(aula) }
            .navigationDestination(isPresented: $verCompleta) { AulaDetailView(aula: aula) }
            .sheet(isPresented: $perguntar) { painelEstudo(aula) }
            .task(id: "\(pasta.path)#\(library.versao)") { await carregar() }
            .onAppear { ultimaLida = pasta.path }
        } else {
            ContentUnavailableView("Aula não encontrada", systemImage: "questionmark.folder")
        }
    }

    private func cabecalho(_ aula: Aula) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(aula.cadeira) · Aula \(library.numeroDaAula(aula))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(library.cor(aula.cadeira))
            Text(aula.meta.titulo).font(.title.bold())
            Text(([DataAula.longa(aula.meta.data)] + (aula.meta.duracao.map { [Timestamp.duracao($0)] } ?? [])).joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    @ViewBuilder private func conteudo(_ partes: SeccoesApontamentos.Partidos, aula: Aula) -> some View {
        if let resumo = partes.resumo, !resumo.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resumo").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                TextoApontamentos(markdown: resumo, pastaAula: aula.pasta)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 22))
            .padding(.bottom, 22)
        }
        if !partes.seccoes.isEmpty {
            let todas = abertas.count == partes.seccoes.count
            HStack(alignment: .firstTextBaseline) {
                Text("Secções").font(.title3.bold())
                Spacer()
                Button(todas ? "Fechar tudo" : "Abrir tudo") {
                    withAnimation(.snappy) { abertas = todas ? [] : Set(partes.seccoes.indices) }
                }
            }
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(partes.seccoes.enumerated()), id: \.offset) { i, seccao in
                    if i > 0 { Divider() }
                    DisclosureGroup(isExpanded: Binding(get: { abertas.contains(i) },
                                                        set: { if $0 { abertas.insert(i) } else { abertas.remove(i) } })) {
                        TextoApontamentos(markdown: seccao.corpo, pastaAula: aula.pasta)
                            .padding(.top, 8)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(.tertiary)
                            Text(seccao.titulo.isEmpty ? aula.meta.titulo : seccao.titulo)
                                .font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.vertical, 12)
                    // O DisclosureGroup pinta o rótulo com a cor de destaque; no design é texto normal.
                    .tint(.primary)
                }
            }
            .padding(.horizontal, 16)
            .background(.background.secondary, in: .rect(cornerRadius: 22))
        }
        botaoRevista(aula).padding(.top, 24)
    }

    @ViewBuilder private func botaoRevista(_ aula: Aula) -> some View {
        if aula.meta.revista {
            Button { marcar(aula) } label: {
                Label("Revista", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.green)
        } else {
            Button { marcar(aula) } label: {
                Text("Marcar como revista").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    @ToolbarContentBuilder private func barra(_ aula: Aula) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(aula.meta.revista ? "Marcar como por rever" : "Marcar como revista",
                   systemImage: aula.meta.revista ? "checkmark.circle.fill" : "checkmark.circle") { marcar(aula) }
                .tint(aula.meta.revista ? .green : nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("Mais", systemImage: "ellipsis") {
                Button("Perguntar à aula", systemImage: "bubble.left.and.text.bubble.right") { perguntar = true }
                Button("Transcrição, slides e materiais", systemImage: "doc.text.magnifyingglass") { verCompleta = true }
            }
        }
    }

    private func painelEstudo(_ aula: Aula) -> some View {
        NavigationStack {
            PainelEstudo(aula: aula) { segundos in
                perguntar = false
                navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos)
            } aoClicarSeccao: { ligacao in
                perguntar = false
                navegacao.destino = estudo.destino(ligacao, aPartirDe: aula)
            } aoAbrirAula: { outra in
                perguntar = false
                navegacao.destino = DestinoAula(pasta: outra, separador: .apontamentos)
            }
            .navigationTitle("Estudo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { perguntar = false } }
            }
        }
    }

    private func marcar(_ aula: Aula) {
        let revista = !aula.meta.revista
        if let aviso {
            aviso.marcar(aula, revista: revista, library: library, mostrar: true)
        } else {
            try? library.definirRevista(revista, em: aula.pasta)
        }
    }

    /// Lê fora do fio principal: no iPhone, os apontamentos podem ainda estar a descarregar do iCloud.
    private func carregar() async {
        let pasta = pasta
        let md = await Task.detached { Disco.lerApontamentos(pasta) }.value
        guard let md else { partes = nil; return }
        let novas = SeccoesApontamentos.partir(md)
        if novas != partes { partes = novas }
    }
}
