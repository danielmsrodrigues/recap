import AppKit
import SwiftUI

/// Ir para um momento da transcrição. O `id` deixa repetir o mesmo momento (clicar duas vezes no mesmo `[mm:ss]`).
struct SaltoTempo: Equatable {
    var segundos: Double
    var id = UUID()
}

struct TranscricaoView: View {
    let transcricao: Transcricao
    /// Momento a mostrar (um `[mm:ss]` clicado, um resultado da pesquisa).
    var irPara: SaltoTempo?
    /// Perguntar sobre o texto selecionado (botão junto à seleção e menu de contexto).
    var aoPerguntar: ((CitacaoPergunta) -> Void)?
    @State private var pesquisa = ""
    /// O salto a aplicar, já com a pesquisa limpa (o segmento tem de estar no texto para se poder ir até ele).
    @State private var salto: SaltoTempo?

    private var indices: [Int] {
        let termo = pesquisa.trimmingCharacters(in: .whitespaces)
        guard !termo.isEmpty else { return Array(transcricao.segmentos.indices) }
        return transcricao.segmentos.indices.filter {
            transcricao.segmentos[$0].texto.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Pesquisar na transcrição", text: $pesquisa)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Text("\(transcricao.segmentos.count) segmentos · \(transcricao.modelo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Copiar tudo", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcricao.textoComTimestamps, forType: .string)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            TextoTranscricaoView(segmentos: transcricao.segmentos, indices: indices, salto: salto, aoPerguntar: aoPerguntar)
        }
        .task(id: irPara) {
            guard let irPara else { return }
            pesquisa = ""
            salto = irPara
        }
    }
}

/// O texto da transcrição como aparece na vista (uma linha `mm:ss  texto` por segmento) e onde fica cada segmento,
/// para saber de que segmentos é o texto selecionado.
enum TextoTranscricao {
    struct Faixa: Equatable {
        var segmento: Int
        /// O que foi dito (sem o tempo nem a etiqueta "Aluno").
        var texto: NSRange
        /// A linha toda.
        var linha: NSRange
        /// A etiqueta "Aluno", que tem fundo próprio.
        var etiqueta: NSRange?
    }

    static let recuo: CGFloat = 52

    static func construir(_ segmentos: [Segmento], indices: [Int]) -> (NSAttributedString, [Faixa]) {
        let paragrafo = NSMutableParagraphStyle()
        paragrafo.tabStops = [NSTextTab(textAlignment: .left, location: recuo)]
        paragrafo.headIndent = recuo
        paragrafo.paragraphSpacing = 7
        paragrafo.lineSpacing = 1
        let corpo = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let resultado = NSMutableAttributedString()
        var faixas: [Faixa] = []
        for i in indices {
            let s = segmentos[i]
            let inicioLinha = resultado.length
            resultado.append(NSAttributedString(string: Timestamp.format(s.inicio) + "\t", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.controlAccentColor,
            ]))
            var etiqueta: NSRange?
            if s.orador == .aluno {
                etiqueta = NSRange(location: resultado.length, length: 7)
                resultado.append(NSAttributedString(string: " Aluno ", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .toolTip: "Identificado pela voz como um aluno (pode falhar)",
                ]))
                resultado.append(NSAttributedString(string: " ", attributes: [.font: corpo]))
            }
            let texto = NSAttributedString(string: s.texto.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [
                .font: corpo,
                .foregroundColor: s.orador == .aluno ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ])
            let inicioTexto = resultado.length
            resultado.append(texto)
            faixas.append(Faixa(segmento: i, texto: NSRange(location: inicioTexto, length: texto.length),
                                linha: NSRange(location: inicioLinha, length: resultado.length - inicioLinha), etiqueta: etiqueta))
            resultado.append(NSAttributedString(string: "\n", attributes: [.font: corpo]))
        }
        resultado.addAttribute(.paragraphStyle, value: paragrafo, range: NSRange(location: 0, length: resultado.length))
        return (resultado, faixas)
    }

    /// O que foi dito na parte selecionada (sem os tempos nem as etiquetas), com o momento do primeiro segmento.
    static func citacao(_ texto: String, faixas: [Faixa], segmentos: [Segmento], selecao: NSRange) -> CitacaoPergunta? {
        let ns = texto as NSString
        var partes: [String] = []
        var inicio: Double?
        for f in faixas {
            let comum = NSIntersectionRange(f.texto, selecao)
            guard comum.length > 0 else { continue }
            partes.append(ns.substring(with: comum))
            if inicio == nil { inicio = segmentos[f.segmento].inicio }
        }
        let junto = partes.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard junto.count >= 2 else { return nil }
        return CitacaoPergunta(texto: junto, origem: .transcricao, inicio: inicio)
    }
}

/// A transcrição num NSTextView só de leitura: deixa selecionar texto de vários segmentos e perguntar sobre ele.
struct TextoTranscricaoView: NSViewRepresentable {
    let segmentos: [Segmento]
    let indices: [Int]
    var salto: SaltoTempo?
    var aoPerguntar: ((CitacaoPergunta) -> Void)?

    func makeCoordinator() -> Coordenador { Coordenador() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let texto = NSTextView(usingTextLayoutManager: false)
        texto.isEditable = false
        texto.isSelectable = true
        texto.isRichText = true
        texto.drawsBackground = true
        texto.backgroundColor = .textBackgroundColor
        texto.textContainerInset = NSSize(width: 14, height: 12)
        texto.isVerticallyResizable = true
        texto.isHorizontallyResizable = false
        texto.autoresizingMask = [.width]
        texto.minSize = .zero
        texto.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        texto.textContainer?.widthTracksTextView = true
        texto.delegate = context.coordinator
        texto.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordenador.mudouTamanho),
                                               name: NSView.frameDidChangeNotification, object: texto)
        scroll.documentView = texto
        context.coordinator.texto = texto
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.aoPerguntar = aoPerguntar
        c.mostrar(segmentos, indices: indices)
        c.saltar(salto)
    }

    @MainActor
    final class Coordenador: NSObject, NSTextViewDelegate {
        weak var texto: NSTextView?
        var aoPerguntar: ((CitacaoPergunta) -> Void)?
        private var segmentos: [Segmento] = []
        private var indices: [Int]?
        private var faixas: [TextoTranscricao.Faixa] = []
        private var destacado: Int?
        private var ultimoSalto: UUID?
        private lazy var botao: NSView = {
            let b = NSHostingView(rootView: BotaoPerguntar { [weak self] in self?.perguntar() })
            b.isHidden = true
            texto?.addSubview(b)
            return b
        }()

        func mostrar(_ segmentos: [Segmento], indices: [Int]) {
            guard let texto, indices != self.indices || segmentos != self.segmentos else { return }
            self.segmentos = segmentos
            self.indices = indices
            let (atribuido, faixas) = TextoTranscricao.construir(segmentos, indices: indices)
            self.faixas = faixas
            texto.textStorage?.setAttributedString(atribuido)
            realcar()
            esconderBotao()
            #if DEBUG
            selecionarParaTeste()
            #endif
        }

        func saltar(_ salto: SaltoTempo?) {
            guard let salto, salto.id != ultimoSalto else { return }
            ultimoSalto = salto.id
            destacado = segmentos.lastIndex { $0.inicio <= salto.segundos + 0.5 } ?? 0
            realcar()
            // Depois do layout, para o NSTextView já ter a largura certa.
            DispatchQueue.main.async { [weak self] in
                guard let self, let f = self.faixas.first(where: { $0.segmento == self.destacado }) else { return }
                self.centrar(f.linha)
            }
        }

        private func realcar() {
            guard let armazem = texto?.textStorage else { return }
            armazem.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: armazem.length))
            for f in faixas {
                if let e = f.etiqueta { armazem.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: e) }
            }
            if let f = faixas.first(where: { $0.segmento == destacado }) {
                armazem.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.18), range: f.texto)
            }
        }

        private func retangulo(_ intervalo: NSRange) -> NSRect? {
            guard let texto, let lm = texto.layoutManager, let tc = texto.textContainer else { return nil }
            lm.ensureLayout(for: tc)
            let glifos = lm.glyphRange(forCharacterRange: intervalo, actualCharacterRange: nil)
            return lm.boundingRect(forGlyphRange: glifos, in: tc)
                .offsetBy(dx: texto.textContainerOrigin.x, dy: texto.textContainerOrigin.y)
        }

        private func centrar(_ intervalo: NSRange) {
            texto?.enclosingScrollView?.layoutSubtreeIfNeeded()
            guard let texto, let scroll = texto.enclosingScrollView, let r = retangulo(intervalo) else { return }
            let altura = scroll.contentView.bounds.height
            let y = min(max(0, r.midY - altura / 2), max(0, texto.frame.height - altura))
            NSAnimationContext.runAnimationGroup { _ in
                scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            }
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Perguntar sobre a seleção

        private var citacaoSelecionada: CitacaoPergunta? {
            guard let texto, aoPerguntar != nil else { return nil }
            return TextoTranscricao.citacao(texto.string, faixas: faixas, segmentos: segmentos, selecao: texto.selectedRange())
        }

        func perguntar() {
            guard let c = citacaoSelecionada, let texto else { return }
            aoPerguntar?(c)
            texto.setSelectedRange(NSRange(location: texto.selectedRange().location, length: 0))
        }

        private func esconderBotao() { botao.isHidden = true }

        /// A largura mudou (janela, painel): o texto voltou a partir as linhas e o botão tem de o acompanhar.
        @objc func mudouTamanho() {
            guard !botao.isHidden else { return }
            textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        }

        /// Só é chamado quando a seleção acaba (não enquanto se arrasta).
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let texto, citacaoSelecionada != nil else { esconderBotao(); return }
            // Por baixo do fim da seleção (o último carácter que não é a mudança de linha), alinhado à direita dele.
            let sel = texto.selectedRange()
            var fim = NSMaxRange(sel) - 1
            let ns = texto.string as NSString
            while fim > sel.location, ns.character(at: fim) == 10 { fim -= 1 }
            guard let r = retangulo(NSRange(location: fim, length: 1)) else { return }
            let tamanho = botao.fittingSize
            let x = min(max(8, r.maxX - tamanho.width), texto.bounds.width - tamanho.width - 8)
            botao.frame = NSRect(origin: NSPoint(x: x, y: r.maxY + 6), size: tamanho)
            botao.isHidden = false
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard citacaoSelecionada != nil else { return menu }
            let item = NSMenuItem(title: "Perguntar sobre a seleção", action: #selector(perguntarDoMenu), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc private func perguntarDoMenu() { perguntar() }

        #if DEBUG
        /// `APONTAMENTOS_SELECAO="<texto>"`: seleciona esse texto (capturas de ecrã sem arrastar o rato);
        /// com `APONTAMENTOS_PERGUNTAR_SELECAO=1`, pergunta logo sobre ele.
        private func selecionarParaTeste() {
            guard let alvo = ProcessInfo.processInfo.environment["APONTAMENTOS_SELECAO"], let texto else { return }
            let r = (texto.string as NSString).range(of: alvo, options: [.caseInsensitive, .diacriticInsensitive])
            guard r.location != NSNotFound else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                texto.window?.makeFirstResponder(texto)
                texto.setSelectedRange(r)
                self?.centrar(r)
                if ProcessInfo.processInfo.environment["APONTAMENTOS_PERGUNTAR_SELECAO"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.perguntar() }
                }
            }
        }
        #endif
    }
}

/// O botão que aparece junto ao texto selecionado (o mesmo aspeto do das notas).
private struct BotaoPerguntar: View {
    var acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Label("Perguntar", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .help("Perguntar sobre o texto selecionado")
        .padding(4)
    }
}
