import SwiftUI

/// Uma aula para ler, no iPhone e no iPad: o resumo e as secções dos apontamentos, que abrem e fecham, e
/// "Marcar como revista". O painel Estudo abre ao lado (no iPhone, onde não cabe, por baixo); a transcrição,
/// os slides e os materiais ficam no menu.
struct AulaLeitura: View {
    let pasta: URL
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    @Environment(\.horizontalSizeClass) private var largura
    /// Só no iPhone: marcar dentro da aula mostra o aviso com a próxima.
    @Environment(AvisoRevista.self) private var aviso: AvisoRevista?
    @AppStorage("ultimaAulaLida") private var ultimaLida = ""
    /// No iPad o painel Estudo fica aberto de uma aula para a outra; no iPhone abre só quando se pede.
    @AppStorage("mostrarEstudo") private var estudoGuardado = true
    @State private var estudoAqui = false

    @State private var partes: SeccoesApontamentos.Partidos?
    @State private var abertas: Set<Int> = [0]
    /// A altura de cada secção já desenhada: ao abrir de novo, não começa pequena e salta.
    @State private var alturas: [Int: CGFloat] = [:]
    @State private var verCompleta = false
    @State private var erro: String?
    /// Os apontamentos tal como estão no disco, para "Ouvir".
    @State private var markdown: String?
    @State private var leitor = LeitorAula()

    private var aula: Aula? { library.aula(em: pasta) }
    private var mostrarEstudo: Binding<Bool> { largura == .compact ? $estudoAqui : $estudoGuardado }

    var body: some View {
        if let aula {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if leitor.ativo { BarraLeitor(leitor: leitor) }
            }
            // Ao abrir a transcrição, os slides e os materiais a leitura continua; ao sair da aula, para.
            .onDisappear { if !verCompleta { leitor.parar() } }
            .navigationDestination(isPresented: $verCompleta) { AulaCompletaIOS(aula: aula) }
            .modifier(ComEstudo(aula: aula, mostrar: mostrarEstudo))
            .alert("Não foi possível marcar a aula", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(erro ?? "")
            }
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
                texto(resumo, aula: aula, altura: -1)
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
                        texto(seccao.corpo, aula: aula, altura: i).padding(.top, 8)
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

    /// O texto de uma secção, com os `[mm:ss]` (vão para a transcrição), os links para outras secções e
    /// "Perguntar" sobre o que se seleciona. `altura`: a chave da altura guardada (-1 = o resumo).
    private func texto(_ markdown: String, aula: Aula, altura: Int) -> some View {
        TextoApontamentos(markdown: markdown, pastaAula: aula.pasta,
                          altura: Binding(get: { alturas[altura] ?? 24 }, set: { alturas[altura] = $0 }),
                          aoClicarTimestamp: { navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: $0) },
                          aoClicarSeccao: { navegacao.destino = estudo.destino($0, aPartirDe: aula) },
                          aoPerguntar: { texto in
                              estudo.citar(CitacaoPergunta(texto: texto, origem: .apontamentos), em: aula)
                              UserDefaults.standard.set(SeccaoEstudo.perguntas.rawValue, forKey: "seccaoEstudo")
                              mostrarEstudo.wrappedValue = true
                          })
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
            Button("Estudo", systemImage: "bubble.left.and.text.bubble.right") { mostrarEstudo.wrappedValue.toggle() }
                .help("Perguntas, exercícios e ligações sobre esta aula")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("Mais", systemImage: "ellipsis") {
                Button("Ouvir a aula", systemImage: "headphones") {
                    if let markdown { leitor.comecar(markdown, idioma: TextoFalado.idiomaVoz(definicoes.linguaApontamentos)) }
                }
                .disabled(markdown == nil)
                Button("Transcrição, slides e materiais", systemImage: "doc.text.magnifyingglass") { verCompleta = true }
            }
        }
    }

    private func marcar(_ aula: Aula) {
        let revista = !aula.meta.revista
        do {
            if let aviso {
                try aviso.marcar(aula, revista: revista, library: library, mostrar: true)
            } else {
                try library.definirRevista(revista, em: aula.pasta)
            }
        } catch {
            erro = error.localizedDescription
        }
    }

    /// Lê fora do fio principal: no iPhone, os apontamentos podem ainda estar a descarregar do iCloud.
    private func carregar() async {
        let pasta = pasta
        let md = await Task.detached { Disco.lerApontamentos(pasta) }.value
        markdown = md
        guard let md else { partes = nil; return }
        let novas = SeccoesApontamentos.partir(md)
        guard novas != partes else { return }
        // Os apontamentos mudaram (gerados de novo no Mac): as secções podem já não ser as mesmas.
        if let antigas = partes, antigas.seccoes.count != novas.seccoes.count {
            abertas = abertas.filter { novas.seccoes.indices.contains($0) }
            alturas = [:]
        }
        partes = novas
    }
}

/// A aula completa (apontamentos, transcrição, slides e materiais), com o painel Estudo ao lado.
struct AulaCompletaIOS: View {
    let aula: Aula
    /// O mesmo interruptor da barra da `AulaDetailView`.
    @AppStorage("mostrarEstudo") private var mostrarEstudo = true

    var body: some View {
        AulaDetailView(aula: aula).modifier(ComEstudo(aula: aula, mostrar: $mostrarEstudo))
    }
}

/// O painel Estudo (perguntas, exercícios, ligações) ao lado da aula: no iPad, um cartão à direita; no iPhone,
/// onde não cabe, uma folha a meio do ecrã com a aula por cima, que continua a ler-se e a mexer-se. Um link para
/// outra aula ou para a transcrição fecha a folha do iPhone.
struct ComEstudo: ViewModifier {
    let aula: Aula
    @Binding var mostrar: Bool
    @Environment(Navegacao.self) private var navegacao
    @Environment(Estudo.self) private var estudo
    @Environment(\.horizontalSizeClass) private var largura

    func body(content: Content) -> some View {
        if largura == .compact {
            // Uma folha e não o inspector: dentro do inspector, o iPhone punha-lhe o vidro translúcido (cinzento
            // e baço) e ignorava o fundo pedido.
            content.sheet(isPresented: $mostrar) {
                painel
                    .padding(.top, 14)
                    // Numa folha, `.background` é o vidro da folha, também dentro do painel: a cor do fundo da app,
                    // à letra.
                    .backgroundStyle(Color(uiColor: .systemBackground))
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Color(uiColor: .systemBackground))
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationContentInteraction(.scrolls)
            }
        } else {
            // No iPad, um cartão solto ao lado da aula, com os quatro cantos arredondados e a cor da barra lateral
            // das cadeiras. O inspector dava uma coluna do sistema com toda a altura, de vidro e de lado direito.
            HStack(spacing: 0) {
                content
                if mostrar {
                    painel
                        .backgroundStyle(Color(uiColor: .secondarySystemBackground))
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(.rect(cornerRadius: 26))
                        .frame(width: 380)
                        .padding([.trailing, .bottom], 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: mostrar)
        }
    }

    private var painel: some View {
        PainelEstudo(aula: aula) { segundos in
            ir(DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: segundos))
        } aoClicarSeccao: { ligacao in
            ir(estudo.destino(ligacao, aPartirDe: aula))
        } aoAbrirAula: { outra in
            ir(DestinoAula(pasta: outra, separador: .apontamentos))
        }
    }

    private func ir(_ destino: DestinoAula?) {
        if largura == .compact { mostrar = false }
        navegacao.destino = destino
    }
}
