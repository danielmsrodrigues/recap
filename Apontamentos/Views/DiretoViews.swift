import SwiftUI

/// Configura uma captação em direto: de que app vem o som, para que aula, a que velocidade.
struct ConfigDiretoSheet: View {
    @Environment(Library.self) private var library
    @Environment(ProcessingQueue.self) private var fila
    @Environment(SessaoDireto.self) private var sessao
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @AppStorage("ultimaCadeira") private var ultimaCadeira = ""
    /// "vivo" ou a velocidade a que a gravação está a tocar ("1", "1.5"…).
    @State private var modo = "vivo"
    private var velocidade: Double { Double(modo) ?? 1 }
    @AppStorage("gerarApontamentos") private var gerarApontamentos = true
    @AppStorage("capturarSlides") private var capturarSlides = true
    @State private var fontes: [FonteAudio] = []
    @State private var miniaturas: [CGWindowID: CGImage] = [:]
    @State private var verOutras = false
    @State private var fonte: FonteAudio?
    @State private var dados = DadosAula()
    @State private var erro: String?

    /// Altura da lista de janelas: até duas filas de quatro; com mais, faz scroll.
    private var alturaJanelas: CGFloat {
        verOutras ? 300 : min(300, CGFloat((fontes.filter(\.ehConhecida).count + 3) / 4) * 150 + 34)
    }

    /// Uma folha só (o design "Recap macOS"): a janela em cima, a aula e as opções por baixo.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Transcrever em direto").font(.title2.bold())
            janela
            aula
        }
        .padding(20)
        .frame(width: 760)
        .task { await carregarFontes() }
        .onAppear { dados.escolherCadeira(library: library, ultima: ultimaCadeira) }
    }

    /// Que janela ouvir.
    private var janela: some View {
        Group {
            Text("O Recap ouve o som da aplicação dessa janela enquanto a aula toca e transcreve-o no fim. Não guarda vídeo nem áudio.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if let erro {
                VStack(alignment: .leading, spacing: 8) {
                    Label(erro, systemImage: "lock.shield").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Abrir Definições do Sistema") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                .font(.callout)
            }

            HStack {
                Text("Janela da aula").font(.headline)
                Spacer()
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await carregarFontes() } }
                    .buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    grelha(fontes.filter(\.ehConhecida))
                    let outras = fontes.filter { !$0.ehConhecida }
                    if !outras.isEmpty {
                        DisclosureGroup("Outras janelas (\(outras.count))", isExpanded: $verOutras) {
                            grelha(outras).padding(.top, 8)
                        }
                    }
                }
                .padding(2)
            }
            .frame(minHeight: min(alturaJanelas, 150), idealHeight: alturaJanelas, maxHeight: alturaJanelas)

            Text("A janela tem de ficar à vista para os slides saírem (atrás de outras ou minimizada, as capturas saem pretas). O som é o da aplicação inteira: não ponhas outro som a tocar.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Que aula é, e como.
    private var aula: some View {
        Group {
            Form {
                FormularioAula(dados: $dados, rotuloData: "Data da aula")
                Section {
                    Picker("A aula é", selection: $modo) {
                        Text("Ao vivo").tag("vivo")
                        Divider()
                        Text("Gravação a 1×").tag("1")
                        Text("Gravação a 1,25×").tag("1.25")
                        Text("Gravação a 1,5×").tag("1.5")
                        Text("Gravação a 2×").tag("2")
                    }
                    Toggle("Capturar os slides", isOn: $capturarSlides)
                    Toggle("Gerar apontamentos no fim", isOn: $gerarApontamentos)
                } footer: {
                    Text("Numa gravação, põe o leitor à velocidade escolhida aqui: assim os [mm:ss] batem com o minuto da aula. O Recap termina sozinho ao fim de 3 minutos de silêncio.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let falta = fonte == nil ? "Escolhe a janela da aula" : dados.falta {
                    Label(falta, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                } else if let fonte {
                    Text(fonte.tituloJanela).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Começar") { comecar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!dados.valido || fonte == nil)
            }
        }
    }

    private func grelha(_ janelas: [FonteAudio]) -> some View {
        GrelhaJanelas(janelas: janelas, miniaturas: miniaturas, escolhida: $fonte, colunas: 4)
    }

    private func carregarFontes() async {
        do {
            fontes = try await CapturaAudio.fontes()
            // Mantém a escolha ao atualizar a lista, se a janela ainda existir (o título pode ter mudado com o separador).
            if !fontes.contains(where: \.ehConhecida) { verOutras = true }
            miniaturas = await CapturaAudio.miniaturas(fontes.map(\.janela))
            // Por defeito, a primeira janela de browser que se vê (as minimizadas não dão slides).
            fonte = fontes.first { $0.id == fonte?.id }
                ?? fontes.first { $0.ehConhecida && miniaturas[$0.janela] != nil }
                ?? fontes.first(where: \.ehConhecida) ?? fontes.first
            erro = fontes.isEmpty ? "Não encontrei janelas abertas. Abre a aula no browser primeiro." : nil
        } catch {
            erro = error.localizedDescription
        }
    }

    private func comecar() {
        guard let fonte else { return }
        ultimaCadeira = dados.nomeCadeira
        let titulo = dados.tituloLimpo
        Task {
            await sessao.comecar(fonte: fonte, cadeira: dados.nomeCadeira, titulo: titulo, data: dados.data, velocidade: velocidade,
                                 gerarApontamentos: gerarApontamentos, capturarSlides: capturarSlides, library: library, fila: fila)
            if case .falhou(let mensagem) = sessao.estado {
                erro = mensagem
                sessao.fecharErro()
            } else {
                openWindow(id: "direto")
                dismiss()
            }
        }
    }
}

/// Janela pequena que fica por cima enquanto a aula está a ser captada.
struct DiretoView: View {
    @Environment(SessaoDireto.self) private var sessao
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var confirmarDescarte = false

    var body: some View {
        // A escolher outra janela da aula, a janela "Em direto" alarga para a grelha.
        if sessao.escolherJanela, sessao.ativa {
            EscolherOutraJanela { sessao.escolherJanela = false }
                .padding(16)
        } else {
            estado
        }
    }

    private var estado: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(sessao.estado == .aOuvir ? .red : .secondary)
                    .frame(width: 10, height: 10)
                Text(titulo).font(.headline).lineLimit(1)
                Spacer()
            }

            switch sessao.estado {
            case .parada:
                Text("A captação terminou. A aula está na fila: a transcrição aparece na janela principal.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Fechar") { dismissWindow(id: "direto") }
            case .falhou(let mensagem):
                Text(mensagem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Fechar") { sessao.fecharErro(); dismissWindow(id: "direto") }
            case .aPreparar:
                ProgressView("A preparar…")
            case .aOuvir, .emPausa:
                emCurso
            }
        }
        .padding(16)
        .frame(width: 340)
        .confirmationDialog("Descartar esta aula?", isPresented: $confirmarDescarte) {
            Button("Descartar", role: .destructive) { Task { await sessao.descartar(); dismissWindow(id: "direto") } }
        } message: {
            Text("O que foi captado é apagado e a aula não é criada.")
        }
    }

    private var estadoSom: String {
        let app = sessao.fonte?.nome ?? "a app"
        if sessao.estado == .emPausa { return "Em pausa" }
        if !sessao.houveSom { return "À espera de som do \(app)… dá play à aula" }
        return sessao.comSom ? "A ouvir o \(app)" : "Sem som neste momento"
    }

    private var titulo: String {
        let fonte = sessao.fonte.map { " · \($0.nome)" } ?? ""
        return (sessao.titulo.isEmpty ? "Em direto" : sessao.titulo) + fonte
    }

    @ViewBuilder private var emCurso: some View {
        if let previa = sessao.previa {
            Image(decorative: previa, scale: 1).resizable().aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        }
        if let fonte = sessao.fonte {
            HStack(spacing: 6) {
                if let icone = NSRunningApplication(processIdentifier: fonte.pid)?.icon {
                    Image(nsImage: icone).resizable().frame(width: 14, height: 14)
                }
                Text(fonte.tituloJanela).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Mudar…") { sessao.escolherJanela = true }
                    .buttonStyle(.link)
                    .help("Captar outra janela sem parar: o som, o tempo e a aula continuam")
            }
            .font(.caption)
        }
        LabeledContent("Aula captada") {
            Text(Timestamp.format(sessao.segundosDeAula)).monospacedDigit()
        }
        if sessao.velocidade != 1 {
            Text("A \(sessao.velocidade.formatted())×: \(Timestamp.format(sessao.segundos)) de tempo real")
                .font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
            IndicadorSom(ativo: sessao.comSom)
            Text(estadoSom).font(.callout).foregroundStyle(.secondary)
        }
        if sessao.estado == .aOuvir, sessao.silencio > 20 {
            let resta = max(0, SessaoDireto.limiteSilencio - sessao.silencio)
            Text("Em silêncio: termina sozinho daqui a \(Timestamp.format(resta)).")
                .font(.caption).foregroundStyle(.orange)
        }
        if sessao.avisoPreto {
            Text("O vídeo está a sair preto: a janela da aula está escondida. Põe-na à vista (por exemplo no monitor) ou usa o picture-in-picture do leitor.")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        if let aviso = sessao.aviso {
            Text(aviso).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button(sessao.estado == .emPausa ? "Retomar" : "Pausar") { sessao.pausar(sessao.estado != .emPausa) }
            Button("Descartar", role: .destructive) { confirmarDescarte = true }
            Spacer()
            Button("Terminar") { Task { await sessao.terminar() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// As janelas para escolher, em grelha.
private struct GrelhaJanelas: View {
    let janelas: [FonteAudio]
    let miniaturas: [CGWindowID: CGImage]
    @Binding var escolhida: FonteAudio?
    var colunas = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: colunas), spacing: 12) {
            ForEach(janelas) { j in
                CartaoJanela(fonte: j, miniatura: miniaturas[j.janela], escolhida: escolhida?.id == j.id)
                    .onTapGesture { escolhida = j }
            }
        }
    }
}

/// A meio da captação, escolher outra janela da aula (#39): o som, o tempo e a aula continuam.
private struct EscolherOutraJanela: View {
    @Environment(SessaoDireto.self) private var sessao
    var aoFechar: () -> Void
    @State private var fontes: [FonteAudio] = []
    @State private var miniaturas: [CGWindowID: CGImage] = [:]
    @State private var escolhida: FonteAudio?
    @State private var verOutras = false
    @State private var aMudar = false

    private var podeMudar: Bool { escolhida != nil && escolhida?.id != sessao.fonte?.id && !aMudar }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mudar de janela").font(.headline)
                Spacer()
                Button("Atualizar", systemImage: "arrow.clockwise") { Task { await carregar() } }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
            }
            Text("A captação não para: o som, o tempo e a aula continuam. Os slides passam a vir da janela escolhida.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GrelhaJanelas(janelas: fontes.filter(\.ehConhecida), miniaturas: miniaturas, escolhida: $escolhida, colunas: 2)
                    let outras = fontes.filter { !$0.ehConhecida }
                    if !outras.isEmpty {
                        DisclosureGroup("Outras janelas (\(outras.count))", isExpanded: $verOutras) {
                            GrelhaJanelas(janelas: outras, miniaturas: miniaturas, escolhida: $escolhida, colunas: 2).padding(.top, 8)
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 320)
            if let escolhida, let atual = sessao.fonte, escolhida.bundleID != atual.bundleID {
                Label("O som passa a vir do \(escolhida.nome) (até agora vinha do \(atual.nome)).", systemImage: "speaker.wave.2")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if aMudar { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancelar", role: .cancel, action: aoFechar)
                Button("Mudar") { mudar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!podeMudar)
            }
        }
        .frame(width: 520)
        .task { await carregar() }
    }

    private func carregar() async {
        fontes = (try? await CapturaAudio.fontes()) ?? []
        if !fontes.contains(where: \.ehConhecida) { verOutras = true }
        // A janela que está a ser captada aparece escolhida: é a referência.
        escolhida = fontes.first { $0.id == (escolhida ?? sessao.fonte)?.id }
        miniaturas = await CapturaAudio.miniaturas(fontes.map(\.janela))
    }

    private func mudar() {
        guard let escolhida else { return }
        aMudar = true
        Task {
            await sessao.mudarJanela(escolhida)
            aMudar = false
            aoFechar()
        }
    }
}

/// Uma janela para escolher, com a miniatura do que mostra (como na partilha de ecrã do Meet).
private struct CartaoJanela: View {
    let fonte: FonteAudio
    let miniatura: CGImage?
    let escolhida: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if let miniatura {
                    Image(decorative: miniatura, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Text("Sem imagem\n(minimizada?)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(height: 110)
            .clipShape(.rect(cornerRadius: 6))
            HStack(spacing: 5) {
                if let icone = NSRunningApplication(processIdentifier: fonte.pid)?.icon {
                    Image(nsImage: icone).resizable().frame(width: 16, height: 16)
                }
                Text(fonte.tituloJanela).font(.caption).lineLimit(1).truncationMode(.middle)
            }
            .help("\(fonte.nome) — \(fonte.tituloJanela)")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(escolhida ? Color.accentColor.opacity(0.15) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(escolhida ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(.rect)
    }
}

/// Ponto que pulsa devagar enquanto chega som (em vez de um medidor a saltar).
private struct IndicadorSom: View {
    let ativo: Bool
    @State private var pulso = false

    var body: some View {
        Circle()
            .fill(ativo ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 9, height: 9)
            .scaleEffect(ativo && pulso ? 1.35 : 1)
            .opacity(ativo && pulso ? 0.6 : 1)
            .animation(ativo ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulso)
            .onAppear { pulso = true }
    }
}

/// O que aparece na barra de menus durante a captação: estado e tempo de aula.
struct RotuloDireto: View {
    @Environment(SessaoDireto.self) private var sessao

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: sessao.estado == .emPausa ? "pause.circle" : "waveform")
            Text(Timestamp.format(sessao.segundosDeAula)).monospacedDigit()
        }
    }
}

/// Menu do ícone na barra de menus enquanto uma aula está a ser captada.
struct DiretoMenu: View {
    @Environment(SessaoDireto.self) private var sessao
    @Environment(\.openWindow) private var openWindow

    // Só conteúdo que muda raramente: o menu é refeito a cada mudança e perdia o realce do rato
    // se mostrasse o tempo (que já está na barra de menus) ou o nível do som.
    var body: some View {
        Text(sessao.estado == .emPausa ? "\(sessao.titulo) · em pausa" : sessao.titulo)
        Divider()
        Button(sessao.estado == .emPausa ? "Retomar" : "Pausar") { sessao.pausar(sessao.estado != .emPausa) }
        Button("Terminar") { Task { await sessao.terminar() } }
        Divider()
        Button("Mostrar janela") {
            openWindow(id: "direto")
            NSApp.activate()
        }
    }
}
