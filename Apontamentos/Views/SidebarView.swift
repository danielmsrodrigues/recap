import SwiftUI

struct SidebarView: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(Fichas.self) private var fichas
    @Binding var selecao: URL?
    @Binding var aEditarCadeira: Cadeira?

    @State private var paraLixo: Aula?
    @State private var cadeiraParaLixo: Cadeira?
    @State private var aEditarAula: Aula?
    @State private var erro: String?
    /// nil = o semestre mais recente. Não fica guardado: ao abrir, a app mostra sempre o semestre em curso.
    @State private var semestreEscolhido: Semestre?
    /// Nomes das cadeiras recolhidas, um por linha.
    @AppStorage("cadeirasRecolhidas") private var recolhidas = ""

    private var semestre: Semestre? {
        if let semestreEscolhido, library.semestres.contains(semestreEscolhido) { return semestreEscolhido }
        return library.semestres.first
    }

    /// As aulas concluídas saem da fila; ficam as que esperam, correm ou falharam.
    private var jobsPorAcabar: [Job] {
        fila.jobs.filter { $0.estado != .concluido && $0.estado != .cancelado }
    }

    var body: some View {
        List(selection: $selecao) {
            if !jobsPorAcabar.isEmpty {
                Section("Fila") {
                    ForEach(jobsPorAcabar) { job in
                        LinhaJob(job: job).tag(job.pastaAula)
                    }
                }
            }

            ForEach(library.cadeiras.filter { $0.semestre == semestre }) { cadeira in
                Section(isExpanded: expandida(cadeira)) {
                    ForEach(cadeira.aulas) { aula in
                        LinhaAula(aula: aula, job: fila.job(para: aula.pasta))
                            .tag(aula.pasta)
                            .contextMenu { menu(aula) }
                    }
                } header: {
                    CabecalhoCadeira(cadeira: cadeira, porRever: Self.porRever(cadeira.aulas),
                                     aAtualizar: fichas.aAtualizar(cadeira) != nil, comErro: fichas.erro(cadeira) != nil,
                                     selecionada: selecao?.mesmoCaminho(FichaCadeira.url(cadeira.pasta)) == true,
                                     aoAbrir: { selecao = FichaCadeira.url(cadeira.pasta) }) { menu(cadeira) }
                        .contextMenu { menu(cadeira) }
                }
            }

            if let erro = library.erro {
                Text(erro).foregroundStyle(.red).font(.caption)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let semestre, library.organizacao != .nenhuma { seletorSemestre(semestre) }
        }
        // Uma aula de outro semestre aberta pela pesquisa ou por um link: a lista muda para lá e abre a cadeira.
        .onChange(of: selecao) { _, nova in
            guard let nova, let cadeira = library.cadeiras.first(where: { nova.path.hasPrefix($0.pasta.path + "/") }) else { return }
            if cadeira.semestre != semestre { semestreEscolhido = cadeira.semestre }
            if !nova.mesmoCaminho(FichaCadeira.url(cadeira.pasta)) { expandida(cadeira).wrappedValue = true }
        }
        .overlay {
            if library.cadeiras.isEmpty && jobsPorAcabar.isEmpty {
                Text("Ainda não há aulas.\nAs cadeiras ficam em \((library.raiz.path as NSString).abbreviatingWithTildeInPath).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
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
        .confirmationDialog("Mover a cadeira para o Lixo?", isPresented: Binding(get: { cadeiraParaLixo != nil }, set: { if !$0 { cadeiraParaLixo = nil } }), presenting: cadeiraParaLixo) { cadeira in
            Button("Mover para o Lixo", role: .destructive) {
                tentar { try library.moverParaLixo(cadeira.pasta) }
                if let s = selecao, s.path.hasPrefix(cadeira.pasta.path + "/") { selecao = nil }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { cadeira in
            Text("\"\(cadeira.nome)\" e as suas \(cadeira.aulas.count) aula(s) vão para o Lixo, de onde as podes recuperar. Os vídeos originais não são tocados.")
        }
        .alert("Erro", isPresented: Binding(get: { erro != nil }, set: { if !$0 { erro = nil } }), presenting: erro) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    // MARK: Semestre

    private func seletorSemestre(_ atual: Semestre) -> some View {
        HStack {
            Menu {
                ForEach(library.semestres, id: \.self) { s in
                    let porRever = Self.porRever(library.cadeiras.filter { $0.semestre == s }.flatMap(\.aulas))
                    Toggle(isOn: Binding(get: { s == atual }, set: { if $0 { semestreEscolhido = s } })) {
                        Text(library.nome(s))
                        if porRever > 0 { Text("\(porRever) por rever") }
                    }
                }
            } label: {
                // Uma cápsula, para se ler como seletor e não como mais um título acima das cadeiras.
                HStack(spacing: 5) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text(library.nome(atual)).fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: .capsule)
                .contentShape(.capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mudar de \(library.organizacao == .ano ? "ano" : library.nomePeriodo) (a procura é em todos)")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func expandida(_ cadeira: Cadeira) -> Binding<Bool> {
        Binding {
            !recolhidas.split(separator: "\n").contains { $0 == cadeira.nome }
        } set: { aberta in
            var nomes = Set(recolhidas.split(separator: "\n").map(String.init))
            if aberta { nomes.remove(cadeira.nome) } else { nomes.insert(cadeira.nome) }
            recolhidas = nomes.sorted().joined(separator: "\n")
        }
    }

    private static func porRever(_ aulas: [Aula]) -> Int {
        aulas.filter { !$0.meta.revista && $0.temApontamentos }.count
    }

    // MARK: Menus

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
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { paraLixo = aula }.disabled(ativa)
    }

    @ViewBuilder private func menu(_ cadeira: Cadeira) -> some View {
        let ativa = fila.jobs.contains { $0.ativo && $0.pastaAula.path.hasPrefix(cadeira.pasta.path + "/") }
        Button("Editar cadeira…") { aEditarCadeira = cadeira }.disabled(ativa)
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([cadeira.pasta]) }
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { cadeiraParaLixo = cadeira }.disabled(ativa)
    }

    // MARK: Ações

    private func tentar(_ acao: () throws -> Void) {
        do { try acao() } catch { erro = error.localizedDescription }
    }
}

/// O nome da cadeira é o cabeçalho do grupo e abre a ficha da cadeira ("Sobre a cadeira"): avaliação, datas,
/// programa e avisos juntados de todas as aulas. As opções da cadeira ficam no "…" e no menu de contexto.
private struct CabecalhoCadeira<Acoes: View>: View {
    let cadeira: Cadeira
    let porRever: Int
    let aAtualizar: Bool
    let comErro: Bool
    let selecionada: Bool
    let aoAbrir: () -> Void
    @ViewBuilder let acoes: () -> Acoes
    @State private var sobreposto = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: aoAbrir) {
                HStack(spacing: 6) {
                    // O cabeçalho de secção do macOS é pequeno e cinzento; o nome da cadeira tem de se ler bem.
                    Text(cadeira.nome)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(selecionada ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(2)
                    if aAtualizar {
                        ProgressView().controlSize(.mini)
                    } else if comErro {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selecionada ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .opacity(sobreposto || selecionada ? 1 : 0)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Sobre a cadeira: avaliação, datas, programa e avisos, juntados de todas as aulas")
            Spacer()
            if porRever > 0 {
                Text("\(porRever) por rever").font(.caption2).foregroundStyle(.tint)
            }
            Menu("Cadeira", systemImage: "ellipsis.circle", content: acoes)
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
        .padding(.top, 4)
        .onHover { sobreposto = $0 }
    }
}

private struct LinhaAula: View {
    let aula: Aula
    let job: Job?
    /// Linha selecionada (fundo azul): os ícones azuis passam a brancos para não desaparecerem.
    @Environment(\.backgroundProminence) private var proeminencia
    private var cor: Color { proeminencia == .increased ? .white : .accentColor }

    /// "Aula 3 · Tema" → o tema em cima e "Aula 3" ao lado da data, para o tema caber; outros títulos ficam inteiros.
    private var partes: (numero: String?, tema: String) {
        let p = aula.meta.titulo.components(separatedBy: " · ")
        guard p.count >= 2, p[0].hasPrefix("Aula ") else { return (nil, aula.meta.titulo) }
        return (p[0], p.dropFirst().joined(separator: " · "))
    }

    var body: some View {
        HStack(spacing: 8) {
            estado.frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(partes.tema).lineLimit(2)
                Text([partes.numero, aula.meta.data.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "pt_PT")))]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Como no Mail: ponto azul = por rever. As ações estão no menu de contexto.
            if aula.temApontamentos && !aula.meta.revista {
                Circle().fill(cor).frame(width: 7, height: 7).help("Por rever")
            }
        }
    }

    @ViewBuilder private var estado: some View {
        if job?.estado == .aCorrer {
            ProgressView().controlSize(.mini)
        } else if aula.meta.revista {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(proeminencia == .increased ? Color.white : Color.green)
        } else if aula.temApontamentos {
            Image(systemName: "doc.text.fill").foregroundStyle(cor)
        } else if aula.temTranscricao {
            Image(systemName: "waveform").foregroundStyle(.secondary)
        } else {
            Image(systemName: "clock").foregroundStyle(.tertiary)
        }
    }
}

private struct LinhaJob: View {
    let job: Job

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch job.estado {
                case .aCorrer: ProgressView().controlSize(.mini)
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
