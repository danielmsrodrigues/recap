import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// As três secções do painel Estudo: todas pedem ao Claude algo sobre a aula aberta.
enum SeccaoEstudo: String, CaseIterable, Identifiable {
    case perguntas = "Perguntas"
    case exercicios = "Exercícios"
    case ligacoes = "Ligações"
    var id: String { rawValue }
}

/// O painel à direita da aula: perguntas, exercícios e ligações com as outras aulas.
struct PainelEstudo: View {
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void
    var aoClicarSeccao: (LigacaoSeccao) -> Void
    var aoAbrirAula: (URL) -> Void
    @AppStorage("seccaoEstudo") private var seccaoGuardada = SeccaoEstudo.perguntas.rawValue

    private var seccao: Binding<SeccaoEstudo> {
        Binding(get: { SeccaoEstudo(rawValue: seccaoGuardada) ?? .perguntas }, set: { seccaoGuardada = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Secção", selection: seccao) {
                ForEach(SeccaoEstudo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            switch seccao.wrappedValue {
            case .perguntas: PerguntasView(aula: aula, aoClicarTimestamp: aoClicarTimestamp, aoClicarSeccao: aoClicarSeccao)
            case .exercicios: ExerciciosView(aula: aula, aoClicarTimestamp: aoClicarTimestamp)
            case .ligacoes: LigacoesView(aula: aula, aoClicarTimestamp: aoClicarTimestamp, aoAbrirAula: aoAbrirAula)
            }
        }
        .background(.background)
    }
}

/// Perguntar à aula: conversa sobre a aula, com as respostas baseadas na transcrição, nos slides e nos apontamentos.
struct PerguntasView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    @Environment(Library.self) private var library
    @Environment(Navegacao.self) private var navegacao
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void
    /// Um link para uma secção dos apontamentos numa resposta.
    var aoClicarSeccao: (LigacaoSeccao) -> Void

    @State private var texto = ""
    @State private var perguntas: [PerguntaAula] = []
    @State private var confirmarApagar = false
    @State private var erroPDF: String?
    #if !os(macOS)
    @State private var pdfPartilhado: FicheiroPartilhado?
    #endif
    @FocusState private var focado: Bool
    @State private var escolherAnexos = false
    /// Um PDF, Excel, Word ou PowerPoint juntado, aberto no Quick Look (as imagens abrem em `ImagemEmGrande`).
    @State private var anexoAberto: URL?
    @State private var erroAnexo: String?
    #if os(macOS)
    /// O campo do Mac é um `NSTextView` (`CampoPergunta`): o foco chega e sai por aqui.
    @State private var focadoMac = false
    @State private var pedidoFoco = 0
    #endif

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(aula, .pergunta) }
    /// Trecho selecionado nos apontamentos ou na transcrição, à espera da pergunta.
    private var citacao: CitacaoPergunta? { estudo.citacao(aula) }
    /// Ficheiros já copiados para `anexos-chat/`, à espera da pergunta (ficam ao mudar de aula e voltam se a pergunta falhar).
    private var anexos: [String] { estudo.anexosPorEnviar(aula) }

    private static let sugestoes = [
        "Resume a aula em 3 frases",
        "Qual foi a parte mais difícil? Explica-a de forma simples",
        "Houve avisos de exames ou entregas?",
        "Que perguntas podem sair no exame sobre esta matéria?",
    ]

    private var podeEnviar: Bool {
        Estudo.pergunta(texto, citacao: citacao, anexos: anexos) != nil && emCurso == nil && definicoes.faltaParaGerar == nil
    }

    private var campoFocado: Bool {
        #if os(macOS)
        focadoMac
        #else
        focado
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            if perguntas.isEmpty && emCurso == nil {
                vazio
            } else {
                cabecalho
                Divider()
                NotesWebView(markdown: conversa, emStreaming: emCurso != nil, aoClicarTimestamp: aoClicarTimestamp, modo: "conversa",
                             aoClicarSeccao: aoClicarSeccao, aoGuardarPDF: aoGuardarPDF)
            }
            AvisoEsperaMac(aula: aula, tipo: .pergunta)
            if let erro = erroAnexo ?? erroPDF ?? estudo.erro(aula, .pergunta) {
                Label(erro, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 6)
            }
            if let citacao { trecho(citacao) }
            campo
        }
        .background(.background)
        #if !os(macOS)
        .sheet(item: $pdfPartilhado) { FolhaPartilha(ficheiro: $0) }
        #endif
        .quickLookPreview($anexoAberto)
        .fileImporter(isPresented: $escolherAnexos, allowedContentTypes: Anexos.tiposAceites, allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { juntar(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            juntar(urls)
            return true
        }
        // `library.versao`: uma resposta pode chegar pelo iCloud (dada no Mac, ou pedida aqui ao Mac).
        .task(id: [estudo.versao, library.versao]) { perguntas = Disco.lerPerguntas(aula.pasta) }
        .task(id: aula.pasta) {
            let usados = Set(Disco.lerPerguntas(aula.pasta).flatMap { $0.anexos ?? [] } + anexos)
            Anexos.limparOrfaos(em: aula.pasta, usados: usados)
        }
        // Um trecho escolhido (ou o painel aberto por causa dele): o cursor vai para o campo.
        .task(id: estudo.pedidosCitacao) {
            guard citacao != nil, estudo.consumirFoco() else { return }
            try? await Task.sleep(for: .milliseconds(80))
            #if os(macOS)
            pedidoFoco += 1
            #else
            focado = true
            #endif
        }
        #if DEBUG
        .task {
            // `APONTAMENTOS_PERGUNTAR="<pergunta>"`: faz essa pergunta à aula aberta (o mesmo que escrevê-la e carregar ↩).
            guard let p = ProcessInfo.processInfo.environment["APONTAMENTOS_PERGUNTAR"] else { return }
            try? await Task.sleep(for: .seconds(1))
            enviar(p, citacao: nil)
        }
        #endif
        .confirmationDialog("Apagar a conversa desta aula?", isPresented: $confirmarApagar) {
            Button("Apagar", role: .destructive) { estudo.apagarPerguntas(aula) }
        }
    }

    /// Só com conversa: o nome da secção já está no seletor do painel, e a aula é a que está aberta ao lado.
    private var cabecalho: some View {
        HStack {
            Text(perguntas.count == 1 ? "1 pergunta" : "\(perguntas.count) perguntas").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Nova conversa", systemImage: "square.and.pencil") { confirmarApagar = true }
                .buttonStyle(.borderless)
                .disabled(emCurso != nil)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var vazio: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkle.text.clipboard")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Pergunta o que quiseres sobre esta aula")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("As respostas vêm da transcrição, dos slides e dos apontamentos, com os minutos da aula.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.sugestoes, id: \.self) { s in
                    // As sugestões são sobre a aula toda, não sobre o trecho escolhido.
                    Button { enviar(s, citacao: nil) } label: {
                        Text(s)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(definicoes.faltaParaGerar != nil)
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trecho(_ c: CitacaoPergunta) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.legenda.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(c.textoLimpo)
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Tirar o trecho", systemImage: "xmark.circle.fill") { estudo.tirarCitacao(aula) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Perguntar sem este trecho")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 26)
        .padding(.top, 10)
    }

    private var marcador: String {
        if citacao != nil { return "Pergunta sobre o trecho (↩ para o explicar)" }
        return anexos.isEmpty ? "Pergunta sobre esta aula…" : "Pergunta sobre os ficheiros (↩ para os explicar)"
    }

    /// Os ficheiros juntados, cada um com um botão para o tirar. As imagens aparecem em miniatura, como no WhatsApp.
    private var fichas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(anexos, id: \.self) { nome in
                    if Anexos.tipo(nome) == .imagem {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { navegacao.imagemAberta = Anexos.url(nome, em: aula.pasta) }
                        } label: {
                            MiniaturaAnexo(nome: nome, pastaAula: aula.pasta)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            Button("Tirar \(nome)", systemImage: "xmark.circle.fill") { estudo.tirarAnexo(nome, de: aula) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .font(.body)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .padding(3)
                        }
                        .help(nome)
                    } else {
                        ficha(nome)
                    }
                }
            }
        }
    }

    private func ficha(_ nome: String) -> some View {
        HStack(spacing: 4) {
            Button { anexoAberto = Anexos.url(nome, em: aula.pasta) } label: {
                HStack(spacing: 4) {
                    Image(systemName: Self.icone(nome)).foregroundStyle(.secondary)
                    Text(nome).lineLimit(1).truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            Button("Tirar \(nome)", systemImage: "xmark.circle.fill") { estudo.tirarAnexo(nome, de: aula) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: 220)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
    }

    private static func icone(_ nome: String) -> String {
        switch Anexos.tipo(nome) {
        case .imagem: "photo"
        case .pdf: "doc.richtext"
        case .folha: "tablecells"
        case .apresentacao: "rectangle.on.rectangle"
        default: "doc.text"
        }
    }

    private var campo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !anexos.isEmpty { fichas }
            HStack(alignment: .bottom, spacing: 6) {
                Button("Juntar ficheiros", systemImage: "paperclip") { escolherAnexos = true }
                    .foregroundStyle(.secondary)
                    .help("Juntar ficheiros à pergunta (imagens, PDF, Excel, Word, PowerPoint, texto). Também podes colar ou arrastar.")
                caixaTexto
                    // O .title2 do HStack é só para os ícones dos botões.
                    .font(.body)
                    .padding(.bottom, 4)
                botaoEnviar
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title2)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(campoFocado ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
        .padding(12)
        .font(.body)
    }

    @ViewBuilder private var caixaTexto: some View {
        #if os(macOS)
        CampoPergunta(texto: $texto, marcador: marcador, pedidoFoco: pedidoFoco,
                      aoMudarFoco: { focadoMac = $0 }, aoEnviar: { enviar(texto) }, aoJuntar: juntar)
        #else
        TextField(marcador, text: $texto, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($focado)
            .onSubmit { enviar(texto) }
        #endif
    }

    @ViewBuilder private var botaoEnviar: some View {
        Group {
            if emCurso != nil {
                Button("Parar", systemImage: "stop.circle.fill") { estudo.cancelar(aula, .pergunta) }
                    .help("Parar a resposta")
            } else {
                Button("Perguntar", systemImage: "arrow.up.circle.fill") { enviar(texto) }
                    .foregroundStyle(podeEnviar ? Color.accentColor : Color.secondary)
                    .disabled(!podeEnviar)
                    .help("Perguntar (↩; ⇧↩ muda de linha)")
            }
        }
    }

    /// Copia os ficheiros para a pasta da aula. Os que não se aceitam ficam de fora, com o aviso do primeiro.
    private func juntar(_ urls: [URL]) {
        erroAnexo = nil
        var total = anexos.reduce(0) { $0 + Anexos.tamanho($1, em: aula.pasta) }
        for url in urls {
            let acesso = url.startAccessingSecurityScopedResource()
            defer { if acesso { url.stopAccessingSecurityScopedResource() } }
            do {
                let nome = try Anexos.juntar(url, em: aula.pasta)
                let tamanho = Anexos.tamanho(nome, em: aula.pasta)
                guard total + tamanho <= Anexos.tamanhoMaximo else {
                    Anexos.remover(nome, em: aula.pasta)
                    erroAnexo = "Os ficheiros desta pergunta passavam de \(Anexos.tamanhoMaximo / 1_048_576) MB: \"\(url.lastPathComponent)\" ficou de fora."
                    continue
                }
                total += tamanho
                estudo.juntarAnexo(nome, a: aula)
            } catch {
                if erroAnexo == nil { erroAnexo = error.localizedDescription }
            }
        }
    }

    /// A conversa toda num só documento (uma vista web em vez de uma por resposta).
    private var conversa: String {
        var md = perguntas.enumerated().map { i, p in
            Self.bloco(p.pergunta, p.citacao, p.anexos ?? []) + p.resposta
                + (p.documentoPDF == nil || !Self.podeGuardarPDF ? "" : "\n\n<div class=\"guardar-pdf\"><button data-resposta=\"\(i)\">Guardar PDF…</button></div>")
        }.joined(separator: "\n\n")
        if let emCurso, let pergunta = emCurso.pergunta {
            md += (md.isEmpty ? "" : "\n\n") + Self.bloco(pergunta, emCurso.citacao, emCurso.anexos)
                + (emCurso.texto.isEmpty ? "<div class=\"a-pensar\"><span></span><span></span><span></span></div>" : emCurso.texto)
        }
        return md
    }

    /// A pergunta numa bolha, com o trecho citado por cima (o `[mm:ss]` da legenda fica clicável).
    private static func bloco(_ pergunta: String, _ citacao: CitacaoPergunta?, _ anexos: [String] = []) -> String {
        let trecho = citacao.map {
            "<div class=\"citacao\"><span class=\"origem\">\(html($0.legenda))</span>\(html($0.textoLimpo))</div>"
        } ?? ""
        let ficheiros = anexos.isEmpty ? "" :
            "<div class=\"citacao\"><span class=\"origem\">📎 \(anexos.count == 1 ? "Ficheiro" : "Ficheiros")</span>\(html(anexos.joined(separator: " · ")))</div>"
        return "<div class=\"pergunta\">\(trecho)\(ficheiros)\(html(pergunta))</div>\n\n"
    }

    private static func html(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    #if os(macOS)
    /// As respostas pedidas em PDF guardam-se com o `ExportadorPDF`, que só existe no Mac.
    private static let podeGuardarPDF = true
    private var aoGuardarPDF: ((Int) -> Void)? { guardarPDF }

    /// Guarda em PDF uma resposta pedida assim, com o nome do seu título, e abre-o.
    private func guardarPDF(_ indice: Int) {
        guard perguntas.indices.contains(indice), let documento = perguntas[indice].documentoPDF else { return }
        let painel = NSSavePanel()
        painel.nameFieldStringValue = Disco.nomeDePasta(TituloAula.tema(documento) ?? aula.meta.titulo) + ".pdf"
        painel.allowedContentTypes = [.pdf]
        guard painel.runModal() == .OK, let destino = painel.url else { return }
        erroPDF = nil
        Task {
            do {
                try await ExportadorPDF.exportar(markdown: documento, pastaAula: aula.pasta, para: destino)
                NSWorkspace.shared.open(destino)
            } catch {
                erroPDF = "Não foi possível guardar o PDF: \(error.localizedDescription)"
            }
        }
    }
    #else
    private static let podeGuardarPDF = true
    private var aoGuardarPDF: ((Int) -> Void)? { guardarPDF }

    /// No iOS o PDF é criado num ficheiro temporário e vai para a folha de partilha (guardar no Ficheiros, GoodNotes…).
    private func guardarPDF(_ indice: Int) {
        guard perguntas.indices.contains(indice), let documento = perguntas[indice].documentoPDF else { return }
        let destino = FileManager.default.temporaryDirectory
            .appending(path: Disco.nomeDePasta(TituloAula.tema(documento) ?? aula.meta.titulo) + ".pdf")
        erroPDF = nil
        Task {
            do {
                try await ExportadorPDF.exportar(markdown: documento, pastaAula: aula.pasta, para: destino)
                pdfPartilhado = FicheiroPartilhado(url: destino)
            } catch {
                erroPDF = "Não foi possível criar o PDF: \(error.localizedDescription)"
            }
        }
    }
    #endif

    private func enviar(_ texto: String) { enviar(texto, citacao: citacao) }

    private func enviar(_ texto: String, citacao: CitacaoPergunta?) {
        guard let pergunta = Estudo.pergunta(texto, citacao: citacao, anexos: anexos), emCurso == nil, definicoes.faltaParaGerar == nil else { return }
        estudo.perguntar(pergunta, sobre: aula, citacao: citacao, anexos: anexos)
        self.texto = ""
        erroAnexo = nil
    }
}

/// Exercícios extra da aula, gerados a pedido (`exercicios.md`).
struct ExerciciosView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    @Environment(Library.self) private var library
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void

    @State private var markdown: String?

    private var emCurso: Estudo.EmCurso? { estudo.emCurso(aula, .exercicios) }

    var body: some View {
        VStack(spacing: 0) {
            if markdown != nil || emCurso != nil {
                barra
                Divider()
            }
            // A mesma vista web para o texto a chegar e para o guardado (ver AulaDetailView).
            if let texto = emCurso?.texto.isEmpty == false ? emCurso?.texto : (emCurso == nil ? markdown : nil) {
                NotesWebView(markdown: texto, emStreaming: emCurso != nil, aoClicarTimestamp: aoClicarTimestamp)
            } else if emCurso != nil {
                ContentUnavailableView("A criar exercícios…", systemImage: "hourglass",
                                       description: Text("O texto aparece aqui à medida que chega."))
                    .frame(maxHeight: .infinity)
            } else {
                vazio.frame(maxHeight: .infinity)
            }
            AvisoEsperaMac(aula: aula, tipo: .exercicios)
        }
        .task(id: [estudo.versao, library.versao]) { markdown = Disco.lerTexto(Disco.exerciciosMD, em: aula.pasta) }
    }

    private var barra: some View {
        HStack {
            if let erro = estudo.erro(aula, .exercicios) {
                Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                Text("Clica em \"Ver resolução\" depois de tentares cada exercício.").foregroundStyle(.secondary)
            }
            Spacer()
            if emCurso != nil {
                Button("Parar", systemImage: "stop.circle") { estudo.cancelar(aula, .exercicios) }
            } else {
                Button("Gerar outros", systemImage: "arrow.clockwise") { estudo.gerarExercicios(aula) }
                    .disabled(definicoes.faltaParaGerar != nil)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var vazio: some View {
        ContentUnavailableView {
            Label("Exercícios para treinar", systemImage: "pencil.and.list.clipboard")
        } description: {
            Text(estudo.erro(aula, .exercicios) ?? "Exercícios parecidos com os da aula, do mais fácil ao mais difícil, com a resolução escondida até a abrires. Só usam matéria desta aula.")
        } actions: {
            if definicoes.faltaParaGerar != nil {
                LigacaoDefinicoes()
            } else {
                Button("Gerar exercícios") { estudo.gerarExercicios(aula) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// O pedido foi para o Recap do Mac (motor "Mac", no iOS) e ele ainda não pegou nele. No Mac nunca aparece.
struct AvisoEsperaMac: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    let aula: Aula
    let tipo: Estudo.Tipo

    var body: some View {
        if estudo.emCurso(aula, tipo)?.aEsperarMac == true {
            VStack(alignment: .leading, spacing: 6) {
                Label("À espera do Recap no Mac. Tem de estar aberto, com a pasta das aulas no iCloud Drive.", systemImage: "desktopcomputer")
                    .foregroundStyle(.secondary)
                #if !os(macOS)
                if definicoes.temChaveAPI {
                    Button("Usar a API desta vez") { estudo.usarAPI(aula, tipo) }
                        .buttonStyle(.bordered)
                }
                #endif
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}

/// A miniatura de uma imagem juntada à pergunta, lida fora do fio principal.
private struct MiniaturaAnexo: View {
    var nome: String
    var pastaAula: URL
    @State private var imagem: CGImage?

    var body: some View {
        Group {
            if let imagem {
                Image(decorative: imagem, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .background(.quaternary.opacity(0.6))
        .clipShape(.rect(cornerRadius: 8))
        .task(id: nome) {
            let nome = nome, pasta = pastaAula
            imagem = await Task.detached { Anexos.miniatura(nome, em: pasta, lado: 168) }.value
        }
    }
}
