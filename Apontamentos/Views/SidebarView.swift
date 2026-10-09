import SwiftUI

struct SidebarView: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Binding var selecao: URL?
    @Binding var aEditarCadeira: Cadeira?

    @State private var paraLixo: Aula?
    @State private var cadeiraParaLixo: Cadeira?
    @State private var aEditarAula: Aula?
    @State private var aRenomear: Cadeira?
    @State private var novoNome = ""
    @State private var erro: String?

    var body: some View {
        List(selection: $selecao) {
            if !fila.jobs.isEmpty {
                Section("Fila") {
                    ForEach(fila.jobs) { job in
                        LinhaJob(job: job).tag(job.pastaAula)
                    }
                }
            }

            ForEach(library.cadeiras) { cadeira in
                Section {
                    ForEach(cadeira.aulas) { aula in
                        LinhaAula(aula: aula, job: fila.job(para: aula.pasta)) { menu(aula) }
                            .tag(aula.pasta)
                            .contextMenu { menu(aula) }
                    }
                } header: {
                    HStack {
                        Text(cadeira.nome)
                        Spacer()
                        let porRever = cadeira.aulas.filter { !$0.meta.revista && $0.temApontamentos }.count
                        if porRever > 0 {
                            Text("\(porRever) por rever").font(.caption2).foregroundStyle(.tint)
                        }
                        Menu("Cadeira", systemImage: "ellipsis.circle") { menu(cadeira) }
                            .labelStyle(.iconOnly)
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Glossário, renomear e outras opções da cadeira")
                    }
                    .contextMenu { menu(cadeira) }
                }
            }

            if let erro = library.erro {
                Text(erro).foregroundStyle(.red).font(.caption)
            }
        }
        .overlay {
            if library.cadeiras.isEmpty && fila.jobs.isEmpty {
                Text("Ainda não há aulas.\nAs cadeiras ficam em ~/Aulas.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $aEditarAula) { aula in
            EditarAulaSheet(aula: aula) { nova in if selecao == aula.pasta { selecao = nova } }
        }
        .alert("Renomear cadeira", isPresented: Binding(get: { aRenomear != nil }, set: { if !$0 { aRenomear = nil } }), presenting: aRenomear) { cadeira in
            TextField("Nome", text: $novoNome)
            Button("Renomear") { renomear(cadeira) }
            Button("Cancelar", role: .cancel) {}
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

    // MARK: Menus

    @ViewBuilder private func menu(_ aula: Aula) -> some View {
        let ativa = fila.job(para: aula.pasta)?.ativo == true
        Button(aula.meta.revista ? "Marcar como por rever" : "Marcar como revista") {
            tentar { try library.definirRevista(!aula.meta.revista, em: aula.pasta) }
        }
        Button("Editar aula…") { aEditarAula = aula }.disabled(ativa)
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([aula.pasta]) }
        if !aula.temTranscricao, !ativa, let ref = aula.meta.video, case .ok(let url) = VideoResolver.resolver(ref) {
            Button("Processar de novo") {
                fila.adicionar(Job(pastaAula: aula.pasta, titulo: aula.meta.titulo, video: url, gerarApontamentos: true))
            }
        }
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { paraLixo = aula }.disabled(ativa)
    }

    @ViewBuilder private func menu(_ cadeira: Cadeira) -> some View {
        let ativa = fila.jobs.contains { $0.ativo && $0.pastaAula.path.hasPrefix(cadeira.pasta.path + "/") }
        Button("Glossário e câmara do professor…") { aEditarCadeira = cadeira }
        Button("Renomear…") { novoNome = cadeira.nome; aRenomear = cadeira }.disabled(ativa)
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([cadeira.pasta]) }
        Divider()
        Button("Mover para o Lixo…", role: .destructive) { cadeiraParaLixo = cadeira }.disabled(ativa)
    }

    // MARK: Ações

    private func renomear(_ cadeira: Cadeira) {
        let nome = novoNome.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty else { return }
        tentar {
            let nova = try library.renomearCadeira(cadeira, para: nome)
            if let s = selecao, s.path.hasPrefix(cadeira.pasta.path + "/") {
                selecao = nova.appending(path: s.lastPathComponent, directoryHint: .isDirectory)
            }
        }
    }

    private func tentar(_ acao: () throws -> Void) {
        do { try acao() } catch { erro = error.localizedDescription }
    }
}

private struct LinhaAula<Acoes: View>: View {
    let aula: Aula
    let job: Job?
    @ViewBuilder let acoes: () -> Acoes
    /// Linha selecionada (fundo azul): os ícones azuis passam a brancos para não desaparecerem.
    @Environment(\.backgroundProminence) private var proeminencia
    private var cor: Color { proeminencia == .increased ? .white : .accentColor }

    var body: some View {
        HStack(spacing: 8) {
            estado.frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(aula.meta.titulo).lineLimit(1)
                Text(aula.meta.data.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Como no Mail: ponto azul = por rever.
            if aula.temApontamentos && !aula.meta.revista {
                Circle().fill(cor).frame(width: 7, height: 7).help("Por rever")
            }
            // Rótulo desenhado à mão: o estilo de menu do macOS ignorava a cor e o ícone saía preto.
            Menu(content: acoes) {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(proeminencia == .increased ? Color.white : Color.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Marcar como revista, editar, Finder, Lixo")
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
