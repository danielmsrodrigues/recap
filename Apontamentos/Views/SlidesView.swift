import ImageIO
import PDFKit
import SwiftUI

/// Grelha dos slides extraídos, com o momento em que apareceram.
struct SlidesView: View {
    let pasta: URL
    /// nil = ainda não extraídos.
    let slides: [Slide]?
    /// PDFs dos slides publicados pelo professor juntados à aula.
    let pdfs: [PDFProfessor]
    let podeExtrair: Bool
    let aoExtrair: () -> Void
    /// Juntar os slides em PDF publicados pelo professor, e tirar um já junto (vai para o Lixo).
    let aoJuntarPDF: () -> Void
    let aoRemoverPDF: (PDFProfessor) -> Void
    @State private var aberto: Slide?
    /// O que se escolheu ver; começa no primeiro PDF.
    @State private var escolha: Origem?

    /// Um PDF (pelo número) ou as capturas.
    private enum Origem: Hashable { case pdf(Int), capturas }

    /// A escolha, se ainda existe (o PDF pode ter sido removido).
    private var origem: Origem {
        switch escolha {
        case .pdf(let n) where pdfs.contains(where: { $0.numero == n }): .pdf(n)
        case .capturas where slides?.isEmpty == false: .capturas
        default: pdfs.first.map { .pdf($0.numero) } ?? .capturas
        }
    }

    var body: some View {
        if pdfs.isEmpty {
            capturas
        } else {
            VStack(spacing: 0) {
                HStack {
                    if pdfs.count > 1 || slides?.isEmpty == false {
                        let seletor = Picker("Origem", selection: Binding(get: { origem }, set: { escolha = $0 })) {
                            ForEach(pdfs) { pdf in
                                Text(pdfs.count == 1 ? "PDF do professor" : pdf.titulo).tag(Origem.pdf(pdf.numero))
                            }
                            if let slides, !slides.isEmpty {
                                Text("Capturas (\(slides.count))").tag(Origem.capturas)
                            }
                        }
                        .labelsHidden()
                        // Vários PDFs, com nomes compridos, não cabem lado a lado: um menu com o escolhido.
                        if pdfs.count == 1 {
                            seletor.pickerStyle(.segmented).fixedSize()
                        } else {
                            seletor.pickerStyle(.menu).frame(maxWidth: 360)
                        }
                    } else {
                        Text("PDF do professor").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    menuPDFs
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                if case .pdf(let n) = origem, let pdf = pdfs.first(where: { $0.numero == n }) {
                    VistaPDF(url: pdf.url(em: pasta))
                } else {
                    capturas
                }
            }
        }
    }

    /// Juntar mais PDFs do professor e tirar os que já cá estão.
    private var menuPDFs: some View {
        Menu("PDFs do professor", systemImage: "doc.badge.plus") {
            Button("Juntar PDF…", action: aoJuntarPDF)
            if !pdfs.isEmpty {
                Divider()
                ForEach(pdfs) { pdf in
                    Button("Remover \"\(pdf.titulo)\"", role: .destructive) { aoRemoverPDF(pdf) }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var capturas: some View {
        if let slides, !slides.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("\(slides.count) slides").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    if pdfs.isEmpty { menuPDFs }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
                     ? "Os slides são extraídos do vídeo depois da transcrição. Se o professor publicou os slides em PDF, junta-os aqui."
                     : "Parece não haver partilha de ecrã, ou a deteção falhou. Experimenta outra câmara do professor na cadeira, ou outra sensibilidade em Definições → Slides. Se o professor publicou os slides em PDF, junta-os aqui.")
            } actions: {
                Button("Juntar PDF do professor…", action: aoJuntarPDF).buttonStyle(.borderedProminent)
                Button(slides == nil ? "Extrair slides do vídeo" : "Extrair de novo", action: aoExtrair).disabled(!podeExtrair)
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

    /// Lê já reduzida (480 px): a imagem completa ocuparia ~3,7 MB de RAM por slide. Fica em cache: a grelha
    /// redesenha-se a cada hover e a descodificação custa 5–15 ms por slide.
    static func miniatura(_ url: URL) -> CGImage? {
        let chave = url.path as NSString
        if let feita = cache.object(forKey: chave) { return feita }
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let imagem = CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
        if let imagem { cache.setObject(imagem, forKey: chave) }
        return imagem
    }

    private static let cache: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 200
        return c
    }()
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
