#if os(macOS)
import AppKit
import SwiftUI

/// O campo das perguntas no Mac. Um `NSTextView` e não um `TextField` do SwiftUI: cresce com o texto até
/// `linhasMaximas` (depois faz scroll), ↩ envia, ⇧↩ muda de linha onde está o cursor, e ⌘V ou arrastar
/// de um ficheiro ou de uma imagem junta-o à pergunta em vez de colar o caminho.
struct CampoPergunta: NSViewRepresentable {
    @Binding var texto: String
    var marcador: String
    var linhasMaximas = 8
    /// Muda para pôr o cursor no campo.
    var pedidoFoco = 0
    var aoMudarFoco: (Bool) -> Void = { _ in }
    var aoEnviar: () -> Void
    var aoJuntar: ([URL]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let t = TextoPergunta()
        t.delegate = context.coordinator
        t.autoresizingMask = [.width]
        scroll.documentView = t
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let t = scroll.documentView as? TextoPergunta else { return }
        context.coordinator.pai = self
        if t.string != texto { t.string = texto }
        if t.marcador != marcador { t.marcador = marcador; t.needsDisplay = true }
        t.aoEnviar = aoEnviar
        t.aoJuntar = aoJuntar
        t.aoMudarFoco = aoMudarFoco
        if context.coordinator.pedidoFoco != pedidoFoco {
            context.coordinator.pedidoFoco = pedidoFoco
            DispatchQueue.main.async { t.window?.makeFirstResponder(t) }
        }
    }

    func sizeThatFits(_ proposta: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let t = scroll.documentView as? TextoPergunta else { return nil }
        let largura = proposta.width ?? 300
        // O texto fica com a largura do scroll sem a barra (quando o sistema a mostra sempre).
        let util = NSScrollView.contentSize(forFrameSize: NSSize(width: largura, height: 100), horizontalScrollerClass: nil,
                                            verticalScrollerClass: NSScroller.self, borderType: .noBorder,
                                            controlSize: .regular, scrollerStyle: scroll.scrollerStyle).width
        return CGSize(width: largura, height: Self.altura(texto: t, largura: util, linhasMaximas: linhasMaximas))
    }

    /// A altura do texto, sem passar de `linhasMaximas` linhas.
    static func altura(texto t: TextoPergunta, largura: CGFloat, linhasMaximas: Int) -> CGFloat {
        min(t.alturaDoTexto(largura: largura), t.alturaDaLinha * CGFloat(linhasMaximas))
    }

    func makeCoordinator() -> Coordenador { Coordenador(self) }

    final class Coordenador: NSObject, NSTextViewDelegate {
        var pai: CampoPergunta
        var pedidoFoco: Int

        init(_ pai: CampoPergunta) {
            self.pai = pai
            pedidoFoco = pai.pedidoFoco
        }

        func textDidChange(_ notificacao: Notification) {
            guard let t = notificacao.object as? NSTextView else { return }
            pai.texto = t.string
            // A altura muda com o texto: o SwiftUI volta a perguntar o tamanho.
            t.enclosingScrollView?.invalidateIntrinsicContentSize()
        }
    }
}

final class TextoPergunta: NSTextView {
    var aoEnviar: () -> Void = {}
    var aoJuntar: ([URL]) -> Void = { _ in }
    var aoMudarFoco: (Bool) -> Void = { _ in }
    var marcador = ""

    convenience init() { self.init(frame: NSRect(x: 0, y: 0, width: 300, height: 20)) }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configurar()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configurar()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurar()
    }

    private func configurar() {
        font = .preferredFont(forTextStyle: .body)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
    }

    private var fonte: NSFont { font ?? .preferredFont(forTextStyle: .body) }

    var alturaDaLinha: CGFloat { NSLayoutManager().defaultLineHeight(for: fonte) }

    /// A altura de todo o texto com esta largura (uma linha, se estiver vazio). Medida numa cópia do texto:
    /// o SwiftUI experimenta várias larguras, e mexer no contentor do campo deixava-o com a errada.
    func alturaDoTexto(largura: CGFloat) -> CGFloat {
        let texto = NSTextStorage(string: string, attributes: [.font: fonte])
        let gestor = NSLayoutManager()
        let contentor = NSTextContainer(size: NSSize(width: max(1, largura), height: .greatestFiniteMagnitude))
        contentor.lineFragmentPadding = 0
        gestor.addTextContainer(contentor)
        texto.addLayoutManager(gestor)
        gestor.ensureLayout(for: contentor)
        // O `usedRect` já conta a linha vazia por baixo de um texto que acaba em ⇧↩.
        return max(alturaDaLinha, ceil(gestor.usedRect(for: contentor).height))
    }

    override func keyDown(with evento: NSEvent) {
        // 36 é o Return, 76 o Enter do teclado numérico. A meio de compor um acento, o Return é para isso.
        guard evento.keyCode == 36 || evento.keyCode == 76, !hasMarkedText() else { return super.keyDown(with: evento) }
        if evento.modifierFlags.contains(.shift) {
            insertNewlineIgnoringFieldEditor(nil)
        } else {
            aoEnviar()
        }
    }

    override func paste(_ sender: Any?) {
        guard let urls = Self.ficheirosParaColar(.general) else { return super.paste(sender) }
        aoJuntar(urls)
        // Uma imagem colada foi gravada numa pasta temporária: já foi copiada para a aula.
        for url in urls where url.deletingLastPathComponent().lastPathComponent.hasPrefix("Recap-colado-") {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    override func performDragOperation(_ arrasto: any NSDraggingInfo) -> Bool {
        if let urls = Self.ficheirosParaColar(arrasto.draggingPasteboard) {
            aoJuntar(urls)
            return true
        }
        return super.performDragOperation(arrasto)
    }

    /// Ficheiros copiados (no Finder) ou uma imagem sem texto (uma captura de ecrã com ⌃⇧⌘4), gravada num
    /// ficheiro temporário. nil = é texto, cola-se como texto.
    static func ficheirosParaColar(_ pb: NSPasteboard) -> [URL]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        // Texto copiado do Word ou do Pages também traz uma imagem dele: aí o que se quer é o texto.
        if let s = pb.string(forType: .string), !s.isEmpty { return nil }
        guard let imagem = NSImage(pasteboard: pb), let tiff = imagem.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let pasta = FileManager.default.temporaryDirectory.appending(path: "Recap-colado-\(UUID().uuidString)", directoryHint: .isDirectory)
        let url = pasta.appending(path: "Imagem colada.png")
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            try png.write(to: url)
        } catch { return nil }
        return [url]
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { aoMudarFoco(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { aoMudarFoco(false) }
        return ok
    }

    override func draw(_ area: NSRect) {
        super.draw(area)
        guard string.isEmpty, !marcador.isEmpty else { return }
        (marcador as NSString).draw(at: .zero, withAttributes: [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }
}
#endif
