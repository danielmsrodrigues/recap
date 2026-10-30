import ImageIO
import PDFKit
import QuickLook
import SwiftUI

/// O separador Materiais: os PDFs do professor, as capturas dos slides e os outros materiais (Excel, Word…),
/// cada um escolhido no seletor de cima.
struct SlidesView: View {
    let pasta: URL
    /// nil = ainda não extraídos.
    let slides: [Slide]?
    /// PDFs dos slides publicados pelo professor juntados à aula.
    let pdfs: [PDFProfessor]
    /// Outros materiais do professor (Excel, Word…; ver `Materiais`). Não são slides: veem-se em "Outros".
    var materiais: [String] = []
    // Extrair e juntar faz-se no Mac; no iOS os materiais só se veem.
    var podeExtrair = false
    var aoExtrair: () -> Void = {}
    /// Juntar PDFs dos slides ou outros materiais do professor, e tirar um já junto (vai para o Lixo).
    var aoJuntarMateriais: () -> Void = {}
    var aoRemoverPDF: (PDFProfessor) -> Void = { _ in }
    var aoRemoverMaterial: (String) -> Void = { _ in }
    @Environment(Navegacao.self) private var navegacao
    @State private var aberto: Slide?
    /// Um material que não é imagem, aberto no Quick Look (as imagens abrem em `ImagemEmGrande`).
    @State private var materialAberto: URL?
    /// O que se escolheu ver; começa no primeiro PDF.
    @State private var escolha: Origem?

    /// Um PDF (pelo número), as capturas ou os outros materiais.
    private enum Origem: Hashable { case pdf(Int), capturas, outros }

    /// O que há para ver, pela ordem do seletor.
    private var origens: [Origem] {
        pdfs.map { .pdf($0.numero) } + (slides?.isEmpty == false ? [.capturas] : []) + (materiais.isEmpty ? [] : [.outros])
    }

    /// A escolha, se ainda existe (o PDF ou o último material podem ter sido removidos).
    private var origem: Origem? {
        if let escolha, origens.contains(escolha) { return escolha }
        return origens.first
    }

    var body: some View {
        conteudo.quickLookPreview($materialAberto)
    }

    @ViewBuilder private var conteudo: some View {
        if let origem {
            VStack(spacing: 0) {
                HStack {
                    seletor
                    Spacer()
                    #if os(macOS)
                    menuJuntar
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                switch origem {
                case .pdf(let n):
                    if let pdf = pdfs.first(where: { $0.numero == n }) { VistaPDF(url: pdf.url(em: pasta)) }
                case .capturas:
                    grelhaCapturas
                case .outros:
                    grelhaOutros
                }
            }
        } else {
            vazio
        }
    }

    private func nome(_ origem: Origem) -> String {
        switch origem {
        case .pdf(let n): pdfs.count == 1 ? "PDF do professor" : pdfs.first { $0.numero == n }?.titulo ?? "PDF \(n)"
        case .capturas: "Capturas (\(slides?.count ?? 0))"
        case .outros: "Outros (\(materiais.count))"
        }
    }

    @ViewBuilder private var seletor: some View {
        if origens.count > 1 {
            let picker = Picker("Origem", selection: Binding(get: { origem ?? origens[0] }, set: { escolha = $0 })) {
                ForEach(origens, id: \.self) { Text(nome($0)).tag($0) }
            }
            .labelsHidden()
            // Vários PDFs, com nomes compridos, não cabem lado a lado: um menu com o escolhido.
            if pdfs.count <= 1 {
                picker.pickerStyle(.segmented).fixedSize()
            } else {
                picker.pickerStyle(.menu).frame(maxWidth: 360)
            }
        } else if let origem {
            let texto = switch origem {
            case .pdf: "PDF do professor"
            case .capturas: "\(slides?.count ?? 0) slides"
            case .outros: materiais.count == 1 ? "1 material do professor" : "\(materiais.count) materiais do professor"
            }
            Text(texto).font(.callout).foregroundStyle(.secondary)
        }
    }

    #if os(macOS)
    /// Clicar junta; a seta abre o que se pode tirar.
    private var menuJuntar: some View {
        Menu {
            ForEach(pdfs) { pdf in
                Button("Remover \"\(pdf.titulo)\"", role: .destructive) { aoRemoverPDF(pdf) }
            }
            ForEach(materiais, id: \.self) { nome in
                Button("Remover \"\(nome)\"", role: .destructive) { aoRemoverMaterial(nome) }
            }
        } label: {
            Label("Juntar…", systemImage: "doc.badge.plus")
        } primaryAction: {
            aoJuntarMateriais()
        }
        .menuIndicator(pdfs.isEmpty && materiais.isEmpty ? .hidden : .visible)
        .help("Juntar os slides do professor em PDF, ou outros materiais (Excel, Word, PowerPoint, imagens, texto)")
        .fixedSize()
    }
    #endif

    private func abrir(_ nome: String) {
        let url = Materiais.url(nome, em: pasta)
        if Anexos.tipo(nome) == .imagem {
            withAnimation(.easeOut(duration: 0.15)) { navegacao.imagemAberta = url }
        } else {
            materialAberto = url
        }
    }

    @ViewBuilder private var grelhaCapturas: some View {
        if let slides {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { i, s in
                        Button { aberto = s } label: { Miniatura(url: Disco.urlSlide(s, em: pasta), legenda: legenda(s, numero: i + 1)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .sheet(item: $aberto) { s in
                SlideAmpliado(url: Disco.urlSlide(s, em: pasta), legenda: legenda(s, numero: (slides.firstIndex(of: s) ?? 0) + 1))
            }
        }
    }

    private var grelhaOutros: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                ForEach(materiais, id: \.self) { nome in
                    Button { abrir(nome) } label: { CartaoMaterial(url: Materiais.url(nome, em: pasta), nome: nome) }
                        .buttonStyle(.plain)
                        .help(nome)
                        #if os(macOS)
                        .contextMenu {
                            Button("Abrir") { abrir(nome) }
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([Materiais.url(nome, em: pasta)]) }
                            Divider()
                            Button("Remover", role: .destructive) { aoRemoverMaterial(nome) }
                        }
                        #endif
                }
            }
            .padding(16)
        }
    }

    private var vazio: some View {
        ContentUnavailableView {
            Label(slides == nil ? "Slides ainda não extraídos" : "Nenhum slide encontrado", systemImage: "rectangle.on.rectangle")
        } description: {
            #if os(macOS)
            Text(slides == nil
                 ? "Os slides são extraídos do vídeo depois da transcrição. Se o professor publicou os slides em PDF, ou outros materiais (Excel, Word, PowerPoint…), junta-os aqui."
                 : "Parece não haver partilha de ecrã, ou a deteção falhou. Experimenta outra câmara do professor na cadeira, ou outra sensibilidade em Definições → Slides. Se o professor publicou os slides em PDF, ou outros materiais (Excel, Word, PowerPoint…), junta-os aqui.")
            #else
            Text("Os slides extraem-se no Mac, e os PDFs e outros materiais do professor juntam-se lá.")
            #endif
        } actions: {
            #if os(macOS)
            Button("Juntar materiais do professor…", action: aoJuntarMateriais).buttonStyle(.borderedProminent)
            Button(slides == nil ? "Extrair slides do vídeo" : "Extrair de novo", action: aoExtrair).disabled(!podeExtrair)
            #endif
        }
    }

    private func legenda(_ s: Slide, numero: Int) -> String {
        var t = "\(Timestamp.format(s.inicio)) · Slide \(numero)"
        if !s.reaparicoes.isEmpty { t += " · volta em " + s.reaparicoes.map { Timestamp.format($0) }.joined(separator: ", ") }
        return t
    }
}

/// Um material na grelha "Outros": a imagem em miniatura, ou o ícone do tipo, com o nome por baixo.
private struct CartaoMaterial: View {
    let url: URL
    let nome: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6))
                if Anexos.tipo(nome) == .imagem, let imagem = Miniatura.miniatura(url) {
                    Image(decorative: imagem, scale: 2).resizable().scaledToFill()
                } else {
                    Image(systemName: Anexos.icone(nome)).font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text(nome).font(.caption).lineLimit(2).truncationMode(.middle)
        }
        .contentShape(.rect)
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
            if let fonte = CGImageSourceCreateWithURL(url as CFURL, nil), let imagem = CGImageSourceCreateImageAtIndex(fonte, 0, nil) {
                Image(decorative: imagem, scale: 1).resizable().aspectRatio(contentMode: .fit)
            }
            HStack {
                Text(legenda).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                #if os(macOS)
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                #else
                ShareLink(item: url)
                #endif
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 500)
        #endif
    }
}

/// O PDF do professor, com scroll contínuo.
@MainActor
private struct VistaPDF {
    let url: URL

    func criar() -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .clear
        v.document = PDFDocument(url: url)
        return v
    }

    func atualizar(_ v: PDFView) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

#if os(macOS)
extension VistaPDF: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { criar() }
    func updateNSView(_ v: PDFView, context: Context) { atualizar(v) }
}
#else
extension VistaPDF: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { criar() }
    func updateUIView(_ v: PDFView, context: Context) { atualizar(v) }
}
#endif
