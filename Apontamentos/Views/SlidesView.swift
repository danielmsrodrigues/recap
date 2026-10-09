import ImageIO
import PDFKit
import SwiftUI

/// Grelha dos slides extraídos, com o momento em que apareceram.
struct SlidesView: View {
    let pasta: URL
    /// nil = ainda não extraídos.
    let slides: [Slide]?
    /// PDF dos slides publicado pelo professor, se foi juntado à aula.
    let pdf: URL?
    let podeExtrair: Bool
    let aoExtrair: () -> Void
    @State private var aberto: Slide?
    @State private var verPDF = true

    var body: some View {
        if let pdf {
            VStack(spacing: 0) {
                if let slides, !slides.isEmpty {
                    Picker("Origem", selection: $verPDF) {
                        Text("PDF do professor").tag(true)
                        Text("Capturas do vídeo (\(slides.count))").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding(.vertical, 8)
                    Divider()
                }
                if verPDF || slides?.isEmpty != false {
                    VistaPDF(url: pdf)
                } else {
                    capturas
                }
            }
        } else {
            capturas
        }
    }

    @ViewBuilder private var capturas: some View {
        if let slides, !slides.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("\(slides.count) slides").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Extrair de novo", systemImage: "arrow.clockwise", action: aoExtrair)
                        .disabled(!podeExtrair)
                        .help("Volta a analisar o vídeo com as definições atuais (Definições → Slides e região da cadeira)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(Array(slides.enumerated()), id: \.element.id) { i, s in
                            Button { aberto = s } label: { Miniatura(url: Disco.urlSlide(s, em: pasta), legenda: legenda(s, numero: i + 1)) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .sheet(item: $aberto) { s in
                SlideAmpliado(url: Disco.urlSlide(s, em: pasta), legenda: legenda(s, numero: (slides.firstIndex(of: s) ?? 0) + 1))
            }
        } else {
            ContentUnavailableView {
                Label(slides == nil ? "Slides ainda não extraídos" : "Nenhum slide encontrado", systemImage: "rectangle.on.rectangle")
            } description: {
                Text(slides == nil
                     ? "Os slides são extraídos do vídeo depois da transcrição."
                     : "Parece não haver partilha de ecrã, ou a deteção falhou. Experimenta outra região a ignorar no glossário da cadeira, ou outro limiar em Definições → Slides.")
            } actions: {
                Button("Extrair slides", action: aoExtrair).disabled(!podeExtrair)
            }
        }
    }

    private func legenda(_ s: Slide, numero: Int) -> String {
        var t = "\(Timestamp.format(s.inicio)) · Slide \(numero)"
        if !s.reaparicoes.isEmpty { t += " · volta em " + s.reaparicoes.map { Timestamp.format($0) }.joined(separator: ", ") }
        return t
    }
}

private struct Miniatura: View {
    let url: URL
    let legenda: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let imagem = Self.miniatura(url) {
                    Image(decorative: imagem, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text(legenda).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(.rect)
    }

    /// Lê já reduzida (480 px): a imagem completa ocuparia ~3,7 MB de RAM por slide.
    static func miniatura(_ url: URL) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}

private struct SlideAmpliado: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let legenda: String

    var body: some View {
        VStack(spacing: 10) {
            if let imagem = NSImage(contentsOf: url) {
                Image(nsImage: imagem).resizable().aspectRatio(contentMode: .fit)
            }
            HStack {
                Text(legenda).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 500)
    }
}

/// O PDF do professor, com scroll contínuo.
private struct VistaPDF: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .clear
        v.document = PDFDocument(url: url)
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}
