#if os(macOS)
import SwiftUI

/// O que a lista do meio mostra (a barra lateral do Mac, como no Notas ou no Mail).
enum FiltroAulas: Hashable {
    /// Sem lista escolhida: a coluna da direita mostra o início. No calendário, o mês ocupa a lista e a aula.
    case inicio, calendario, todas, porRever, semana
    case cadeira(URL)
}

/// A barra lateral: as listas (Início, Todas as aulas, Por rever, Esta semana), as cadeiras do semestre com a sua
/// cor e a fila de processamento. Em baixo, o semestre e o "+".
struct BarraLateral: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(Fichas.self) private var fichas
    @Binding var filtro: FiltroAulas
    @Binding var semestre: Semestre?
    @Binding var aEditarCadeira: Cadeira?
    /// Uma aula da fila, para ver o progresso.
    var aoAbrirAula: (URL) -> Void = { _ in }
    var aoNovaCadeira: () -> Void

    @State private var cadeiraParaLixo: Cadeira?
    @State private var erro: String?

    private var cadeiras: [Cadeira] { library.cadeiras(no: semestre) }

    /// As aulas concluídas saem da fila; ficam as que esperam, correm ou falharam.
    private var jobsPorAcabar: [Job] {
        fila.jobs.filter { $0.estado != .concluido && $0.estado != .cancelado }
    }

    var body: some View {
        List(selection: Binding<FiltroAulas?>(get: { filtro }, set: { if let f = $0 { filtro = f } })) {
            Section {
                Label("Início", systemImage: "house").tag(FiltroAulas.inicio)
                Label("Calendário", systemImage: "calendar").tag(FiltroAulas.calendario)
                Label("Todas as aulas", systemImage: "list.bullet")
                    .badge(cadeiras.reduce(0) { $0 + $1.aulas.count })
                    .tag(FiltroAulas.todas)
                Label("Por rever", systemImage: "circle.inset.filled")
                    .badge(Revisao.porRever(cadeiras).count)
                    .tag(FiltroAulas.porRever)
                // Um relógio e não um calendário: são as aulas dos últimos 7 dias (o calendário é o de cima).
                Label("Esta semana", systemImage: "clock")
                    .badge(ListaAulas.daSemana(cadeiras).count)
                    .tag(FiltroAulas.semana)
            }
            Section("Cadeiras") {
                ForEach(cadeiras) { cadeira in
                    Label {
                        HStack(spacing: 4) {
                            Text(cadeira.nome).lineLimit(2)
                            if fichas.aAtualizar(cadeira) != nil {
                                Girador(tamanho: .mini)
                            } else if fichas.erro(cadeira) != nil {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            }
                        }
                    } icon: {
                        SiglaCadeira(nome: cadeira.nome, lado: 18)
                    }
                    .badge(cadeira.aulas.count)
                    .tag(FiltroAulas.cadeira(cadeira.pasta))
                    .contextMenu { menu(cadeira) }
                }
            }
            if !jobsPorAcabar.isEmpty {
                Section("Fila") {
                    ForEach(jobsPorAcabar) { job in
                        Button { aoAbrirAula(job.pastaAula) } label: { LinhaJob(job: job).contentShape(.rect) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if let erro = library.erro {
                Text(erro).foregroundStyle(.red).font(.caption)
            }
        }
        // Sem o fundo da lista, vê-se o cartão (em ContentView).
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { rodape }
        .confirmationDialog("Mover a cadeira para o Lixo?", isPresented: Binding(get: { cadeiraParaLixo != nil }, set: { if !$0 { cadeiraParaLixo = nil } }), presenting: cadeiraParaLixo) { cadeira in
            Button("Mover para o Lixo", role: .destructive) {
                tentar { try library.moverParaLixo(cadeira.pasta) }
                if filtro == .cadeira(cadeira.pasta) { filtro = .todas }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { cadeira in
            Text("\"\(cadeira.nome)\" e as suas \(cadeira.aulas.count) aula(s) vão para o Lixo, de onde as podes recuperar. Os vídeos originais não são tocados.")
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    /// O semestre (a procura é em todos) e o "+".
    private var rodape: some View {
        HStack {
            if library.organizacao != .nenhuma, let atual = semestre ?? library.semestres.first {
                Menu {
                    ForEach(library.semestres, id: \.self) { s in
                        let porRever = Revisao.porRever(library.cadeiras.filter { $0.semestre == s }).count
                        Toggle(isOn: Binding(get: { s == atual }, set: { if $0 { semestre = s } })) {
                            Text(library.nome(s))
                            if porRever > 0 { Text("\(porRever) por rever") }
                        }
                    }
                } label: {
                    Text(library.nome(atual))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Mudar de \(library.organizacao == .ano ? "ano" : library.nomePeriodo) (a procura é em todos)")
            }
            Spacer()
            // Por baixo das cadeiras, só cria cadeiras: transcrever e importar ficam no "Transcrever" e no Início.
            Button("Nova cadeira…", systemImage: "plus", action: aoNovaCadeira)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Nova cadeira")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
        // Dentro do cartão da barra lateral, que fica a 8 pt da margem esquerda e de baixo.
        .padding(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 0))
    }

    @ViewBuilder private func menu(_ cadeira: Cadeira) -> some View {
        let ativa = cadeira.aulas.contains { fila.job(para: $0.pasta)?.ativo == true }
        Button("Editar cadeira…") { aEditarCadeira = cadeira }.disabled(ativa)
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([cadeira.pasta]) }
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { cadeiraParaLixo = cadeira }.disabled(ativa)
    }

    private func tentar(_ acao: () throws -> Void) {
        do { try acao() } catch { erro = error.localizedDescription }
    }
}

/// A lista do meio: as aulas do filtro escolhido, das mais recentes para as mais antigas, com "Sobre a cadeira"
/// em cima quando o filtro é uma cadeira. O menu de contexto de cada aula tem tudo o que se faz com ela.
struct ListaAulas: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    let filtro: FiltroAulas
    let semestre: Semestre?
    @Binding var selecao: URL?
    /// O texto do campo de pesquisa no topo da coluna: com ele, a lista dá lugar aos resultados de todas as aulas.
    @Binding var pesquisa: String
    var aoTranscrever: () -> Void

    @State private var paraLixo: Aula?
    @State private var aEditarAula: Aula?
    /// A segunda gravação de uma aula a juntar a seguir à primeira (ver `Library.juntar`).
    @State private var aJuntar: (primeira: Aula, segunda: Aula)?
    @State private var erro: String?

    /// Aulas dos últimos 7 dias.
    static func daSemana(_ cadeiras: [Cadeira]) -> [Aula] {
        let desde = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return cadeiras.flatMap(\.aulas).filter { $0.meta.data >= desde }
    }

    private var cadeiraEscolhida: Cadeira? {
        guard case .cadeira(let pasta) = filtro else { return nil }
        return library.cadeiras.first { $0.pasta.mesmoCaminho(pasta) }
    }

    private var aulas: [Aula] {
        let cadeiras = library.cadeiras(no: semestre)
        let lista: [Aula] = switch filtro {
        case .inicio, .calendario, .todas: cadeiras.flatMap(\.aulas)
        case .porRever: Revisao.porRever(cadeiras)
        case .semana: Self.daSemana(cadeiras)
        case .cadeira: cadeiraEscolhida?.aulas ?? []
        }
        // A mais recente primeiro; no mesmo dia, a criada por último.
        return lista.sorted { ($0.meta.data, $0.meta.criadaEm) > ($1.meta.data, $1.meta.criadaEm) }
    }

    /// Com várias cadeiras misturadas, um cabeçalho por dia mostra a ordem (a data da aula).
    private func porDia(_ aulas: [Aula]) -> [(dia: Date, aulas: [Aula])] {
        var ordem: [Date] = []
        var grupos: [Date: [Aula]] = [:]
        for a in aulas {
            let dia = Calendar.current.startOfDay(for: a.meta.data)
            if grupos[dia] == nil { ordem.append(dia) }
            grupos[dia, default: []].append(a)
        }
        return ordem.map { ($0, grupos[$0] ?? []) }
    }

    private func nomeDoDia(_ dia: Date) -> String {
        if Calendar.current.isDateInToday(dia) { return "Hoje" }
        if Calendar.current.isDateInYesterday(dia) { return "Ontem" }
        let texto = dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_PT")))
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    private var titulo: String {
        switch filtro {
        case .inicio, .calendario, .todas: "Todas as aulas"
        case .porRever: "Por rever"
        case .semana: "Esta semana"
        case .cadeira: cadeiraEscolhida?.nome ?? "Cadeira"
        }
    }

    var body: some View {
        let aulas = aulas
        let porRever = aulas.filter { $0.temApontamentos && !$0.meta.revista }.count
        Group {
            if pesquisa.trimmingCharacters(in: .whitespaces).isEmpty {
                lista(aulas)
            } else {
                ResultadosPesquisaView(termo: pesquisa)
            }
        }
        // O título e a contagem na barra de cima, por cima da coluna (como no Mail), com o "Transcrever" ao lado,
        // sempre no mesmo sítio; a pesquisa logo por baixo.
        .safeAreaInset(edge: .top, spacing: 0) {
            CampoPesquisa(texto: $pesquisa, sugestao: "Procurar em todas as aulas")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .background(.bar)
        }
        .navigationTitle(titulo)
        .navigationSubtitle(porRever > 0 ? "\(aulas.count) aulas · \(porRever) por rever" : "\(aulas.count) aulas")
        .toolbar {
            ToolbarItem {
                BotaoTranscrever(aoTranscrever: aoTranscrever)
            }
        }
        .sheet(item: $aEditarAula) { aula in
            EditarAulaSheet(aula: aula) { nova in if selecao == aula.pasta { selecao = nova } }
        }
        .confirmationDialog("Mover a aula para o Lixo?", isPresented: Binding(get: { paraLixo != nil }, set: { if !$0 { paraLixo = nil } }), presenting: paraLixo) { aula in
            Button("Mover para o Lixo", role: .destructive) {
                tentar { try library.moverParaLixo(aula.pasta) }
                if selecao == aula.pasta { selecao = nil }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { aula in
            Text("A pasta \"\(aula.pasta.lastPathComponent)\" vai para o Lixo, de onde a podes recuperar. O vídeo original não é tocado.")
        }
        .confirmationDialog("Juntar as duas gravações?", isPresented: Binding(get: { aJuntar != nil }, set: { if !$0 { aJuntar = nil } }), presenting: aJuntar) { par in
            Button("Juntar e gerar apontamentos") { juntar(par.segunda, a: par.primeira) }
            Button("Cancelar", role: .cancel) {}
        } message: { par in
            Text("A transcrição, os slides e os PDFs de \"\(par.segunda.meta.titulo)\" passam para \"\(par.primeira.meta.titulo)\", a seguir ao que lá está, e os apontamentos são gerados de novo. A pasta de \"\(par.segunda.meta.titulo)\" vai para o Lixo, de onde a podes recuperar.")
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    private func lista(_ aulas: [Aula]) -> some View {
        List(selection: $selecao) {
            if let cadeira = cadeiraEscolhida {
                HStack(spacing: 10) {
                    SiglaCadeira(nome: cadeira.nome, lado: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sobre a cadeira").fontWeight(.semibold)
                        Text("Avaliação, datas, programa e avisos").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .tag(FichaCadeira.url(cadeira.pasta))
            }
            if cadeiraEscolhida != nil {
                ForEach(aulas) { linha($0) }
            } else {
                ForEach(porDia(aulas), id: \.dia) { grupo in
                    Section(nomeDoDia(grupo.dia)) {
                        ForEach(grupo.aulas) { linha($0) }
                    }
                }
            }
        }
        .overlay {
            if aulas.isEmpty {
                ContentUnavailableView(filtro == .porRever ? "Está tudo revisto" : "Nenhuma aula",
                                       systemImage: filtro == .porRever ? "checkmark.circle" : "tray")
            }
        }
    }

    private func linha(_ aula: Aula) -> some View {
        LinhaAula(aula: aula, numero: library.numeroDaAula(aula), cor: library.cor(aula.cadeira),
                  aCorrer: fila.job(para: aula.pasta)?.estado == .aCorrer,
                  escolhida: selecao.map { aula.pasta.mesmoCaminho($0) } ?? false)
            .tag(aula.pasta)
            .contextMenu { menu(aula) }
    }

    @ViewBuilder private func menu(_ aula: Aula) -> some View {
        let ativa = fila.job(para: aula.pasta)?.ativo == true
        Button(aula.meta.revista ? "Marcar como por rever" : "Marcar como revista") {
            tentar { try library.definirRevista(!aula.meta.revista, em: aula.pasta) }
        }
        Button("Editar aula…") { aEditarAula = aula }.disabled(ativa)
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([aula.pasta]) }
        if !aula.temTranscricao, !ativa, let ref = aula.meta.video, case .ok(let url) = VideoResolver.resolver(ref) {
            Button("Gerar de novo") {
                fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: url, gerarApontamentos: true))
            }
        }
        let outras = (library.cadeira(nome: aula.cadeira)?.aulas.reversed() ?? []).filter {
            !$0.pasta.mesmoCaminho(aula.pasta) && $0.temTranscricao && fila.job(para: $0.pasta)?.ativo != true
        }
        Menu("Juntar a seguir a esta") {
            ForEach(outras) { outra in
                Button("\(outra.meta.titulo) · \(outra.meta.data.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pt_PT"))))") {
                    aJuntar = (aula, outra)
                }
            }
        }
        .disabled(ativa || !aula.temTranscricao || outras.isEmpty)
        .help("Para uma aula gravada em duas partes: a aula escolhida entra a seguir a esta")
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { paraLixo = aula }.disabled(ativa)
    }

    private func juntar(_ segunda: Aula, a primeira: Aula) {
        tentar {
            let pasta = try library.juntar(segunda, a: primeira)
            var video: URL?
            if let ref = primeira.meta.video, case .ok(let url) = VideoResolver.resolver(ref) { video = url }
            fila.adicionar(Job(pastaAula: pasta, titulo: primeira.meta.titulo, video: video,
                               gerarApontamentos: true, soApontamentos: true))
            selecao = pasta
        }
    }

    private func tentar(_ acao: () throws -> Void) {
        do { try acao() } catch { erro = error.localizedDescription }
    }
}

/// Uma aula na lista do meio: o tema, e por baixo a cor e a sigla da cadeira, o número e a data. À direita,
/// "Por rever" ou o visto verde de revista.
private struct LinhaAula: View {
    let aula: Aula
    let numero: Int
    let cor: Color
    /// Os apontamentos desta aula estão a ser gerados.
    let aCorrer: Bool
    /// Linha escolhida (fundo azul): a etiqueta "Por rever" e o visto passam a branco para não desaparecerem.
    let escolhida: Bool

    /// "Aula 3 · Tema" → só o tema; o número vai para a linha de baixo. Outros títulos ficam inteiros.
    private var tema: String { TituloAula.separar(aula.meta.titulo)?.tema ?? aula.meta.titulo }

    private var estado: String? {
        if aCorrer { return "A gerar…" }
        if !aula.temApontamentos { return aula.temTranscricao ? "Sem apontamentos" : "Por transcrever" }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tema).fontWeight(.semibold).lineLimit(2)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 7, height: 7)
                    Text(([Revisao.sigla(aula.cadeira), "Aula \(numero)", DataAula.curta(aula.meta.data)] + [estado].compactMap { $0 })
                            .joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if aCorrer {
                Girador(tamanho: .mini)
            } else if aula.temApontamentos {
                revisao
            }
        }
        .padding(.vertical, 3)
    }

    /// "Por rever" numa etiqueta azul; revista, um visto verde. Na linha escolhida (fundo azul), a branco.
    @ViewBuilder private var revisao: some View {
        if aula.meta.revista {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(escolhida ? Color.white : Color.green)
                .help("Revista")
        } else {
            Text("Por rever")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .foregroundStyle(escolhida ? Color.white : Color.accentColor)
                .background((escolhida ? Color.white : Color.accentColor).opacity(0.18), in: .capsule)
                .fixedSize()
        }
    }
}

private struct LinhaJob: View {
    let job: Job

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch job.estado {
                case .aCorrer: Girador(tamanho: .mini)
                case .emEspera: Image(systemName: "clock")
                case .concluido: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .cancelado: Image(systemName: "stop.circle")
                case .falhou: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.titulo).lineLimit(1)
                Text(resumo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var resumo: String {
        switch job.estado {
        case .emEspera: return "Em espera"
        case .concluido: return "Concluído"
        case .cancelado: return "Cancelado"
        case .falhou: return "Falhou"
        case .aCorrer:
            guard let etapa = Etapa.allCases.first(where: { job.estadoDe($0).fase == .emCurso }) else { return "A começar…" }
            if let p = job.estadoDe(etapa).progresso {
                return "\(etapa.nome) · \(p.formatted(.percent.precision(.fractionLength(0))))"
            }
            return etapa.nome
        }
    }
}

/// O campo de pesquisa do macOS (com a lupa e o botão de limpar), no topo da coluna das aulas: o `.searchable`
/// só o põe na barra da janela ou na barra lateral.
struct CampoPesquisa: NSViewRepresentable {
    @Binding var texto: String
    var sugestao: String

    func makeNSView(context: Context) -> NSSearchField {
        let campo = Campo()
        campo.placeholderString = sugestao
        campo.delegate = context.coordinator
        // Também pela ação: o ✕ e o Esc limpam o campo sem passar pelo `controlTextDidChange`.
        campo.target = context.coordinator
        campo.action = #selector(Coordenador.mudou(_:))
        campo.controlSize = .large
        campo.sendsSearchStringImmediately = true
        return campo
    }

    func updateNSView(_ campo: NSSearchField, context: Context) {
        context.coordinator.texto = $texto
        if campo.stringValue != texto { campo.stringValue = texto }
    }

    func makeCoordinator() -> Coordenador { Coordenador(texto: $texto) }

    /// Ao abrir a janela, larga o cursor que o macOS lhe dá (as setas continuam a mexer na lista); ⌥⌘F volta a pô-lo
    /// cá. Chega-se a ele com o rato, com o Tab e com o VoiceOver.
    final class Campo: NSSearchField {
        private var aObservar = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let editor = currentEditor(), window.firstResponder === editor else { return }
                window.makeFirstResponder(nil)
            }
            if !aObservar {
                aObservar = true
                NotificationCenter.default.addObserver(self, selector: #selector(focar), name: .procurarEmTodasAsAulas, object: nil)
            }
        }

        @objc private func focar() {
            guard let window, window.isKeyWindow else { return }
            window.makeFirstResponder(self)
        }
    }

    final class Coordenador: NSObject, NSSearchFieldDelegate {
        var texto: Binding<String>
        init(texto: Binding<String>) { self.texto = texto }

        func controlTextDidChange(_ nota: Notification) {
            guard let campo = nota.object as? NSSearchField else { return }
            texto.wrappedValue = campo.stringValue
        }

        @objc func mudou(_ campo: NSSearchField) {
            if texto.wrappedValue != campo.stringValue { texto.wrappedValue = campo.stringValue }
        }
    }
}

/// "Transcrever", em cápsula azul; durante uma captação, o tempo a vermelho, que abre a janela do direto.
struct BotaoTranscrever: View {
    @Environment(SessaoDireto.self) private var direto
    @Environment(\.openWindow) private var openWindow
    var aoTranscrever: () -> Void

    var body: some View {
        Group {
            if direto.ativa {
                Button {
                    openWindow(id: "direto")
                    NSApp.activate()
                } label: {
                    Label(Timestamp.format(direto.segundosDeAula), systemImage: "stop.circle.fill").monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("A captar em direto: mostrar a janela da captação")
            } else {
                Button(action: aoTranscrever) {
                    Label("Transcrever", systemImage: "record.circle").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .help("Transcrever em direto (⇧⌘L)")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
    }
}
#endif
