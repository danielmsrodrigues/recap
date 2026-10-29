import SwiftUI
import UIKit

/// A transcrição num `UITextView` só de leitura (no Mac é um `NSTextView`, em `TranscricaoView.swift`):
/// deixa selecionar texto de vários segmentos e escolher "Perguntar" no menu da seleção.
struct TextoTranscricaoView: UIViewRepresentable {
    let segmentos: [Segmento]
    let indices: [Int]
    var salto: SaltoTempo?
    var aoPerguntar: ((CitacaoPergunta) -> Void)?

    func makeCoordinator() -> Coordenador { Coordenador() }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1: o retângulo de um segmento (para o centrar) vem do layout manager, como no Mac.
        let texto = UITextView(usingTextLayoutManager: false)
        texto.isEditable = false
        texto.isSelectable = true
        texto.backgroundColor = .systemBackground
        texto.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        texto.adjustsFontForContentSizeCategory = true
        texto.delegate = context.coordinator
        context.coordinator.texto = texto
        return texto
    }

    func updateUIView(_ texto: UITextView, context: Context) {
        let c = context.coordinator
        c.aoPerguntar = aoPerguntar
        c.mostrar(segmentos, indices: indices)
        c.saltar(salto)
    }

    @MainActor
    final class Coordenador: NSObject, UITextViewDelegate {
        weak var texto: UITextView?
        var aoPerguntar: ((CitacaoPergunta) -> Void)?
        private var segmentos: [Segmento] = []
        private var indices: [Int]?
        private var faixas: [TextoTranscricao.Faixa] = []
        private var destacado: Int?
        private var ultimoSalto: UUID?

        func mostrar(_ segmentos: [Segmento], indices: [Int]) {
            guard let texto, indices != self.indices || segmentos != self.segmentos else { return }
            self.segmentos = segmentos
            self.indices = indices
            let (atribuido, faixas) = TextoTranscricao.construir(segmentos, indices: indices)
            self.faixas = faixas
            texto.attributedText = atribuido
            realcar()
        }

        func saltar(_ salto: SaltoTempo?) {
            guard let salto, salto.id != ultimoSalto else { return }
            ultimoSalto = salto.id
            destacado = segmentos.lastIndex { $0.inicio <= salto.segundos + 0.5 } ?? 0
            realcar()
            // Depois do layout, para o texto já ter a largura certa.
            DispatchQueue.main.async { [weak self] in
                guard let self, let f = self.faixas.first(where: { $0.segmento == self.destacado }) else { return }
                self.centrar(f.linha)
            }
        }

        private func realcar() {
            guard let armazem = texto?.textStorage else { return }
            armazem.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: armazem.length))
            for f in faixas {
                if let e = f.etiqueta { armazem.addAttribute(.backgroundColor, value: UIColor.quaternaryLabel, range: e) }
            }
            if let f = faixas.first(where: { $0.segmento == destacado }) {
                armazem.addAttribute(.backgroundColor, value: UIColor.tintColor.withAlphaComponent(0.18), range: f.texto)
            }
        }

        private func centrar(_ intervalo: NSRange) {
            guard let texto else { return }
            let lm = texto.layoutManager
            lm.ensureLayout(for: texto.textContainer)
            let glifos = lm.glyphRange(forCharacterRange: intervalo, actualCharacterRange: nil)
            let r = lm.boundingRect(forGlyphRange: glifos, in: texto.textContainer)
                .offsetBy(dx: texto.textContainerInset.left, dy: texto.textContainerInset.top)
            let altura = texto.bounds.height
            let y = min(max(-texto.adjustedContentInset.top, r.midY - altura / 2),
                        max(0, texto.contentSize.height - altura + texto.adjustedContentInset.bottom))
            texto.setContentOffset(CGPoint(x: 0, y: y), animated: true)
        }

        // MARK: Perguntar sobre a seleção

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard aoPerguntar != nil,
                  let citacao = TextoTranscricao.citacao(textView.text, faixas: faixas, segmentos: segmentos, selecao: range)
            else { return nil }
            let perguntar = UIAction(title: "Perguntar", image: UIImage(systemName: "sparkles")) { [weak self, weak textView] _ in
                self?.aoPerguntar?(citacao)
                if let textView { textView.selectedRange = NSRange(location: textView.selectedRange.location, length: 0) }
            }
            return UIMenu(children: [perguntar] + suggestedActions)
        }
    }
}
