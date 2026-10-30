import SwiftUI

// Peças do Mac, do iPhone e do iPad: a cor e a sigla de cada cadeira, as datas curtas das listas, e o aviso
// depois de marcar uma aula como revista.

extension Library {
    /// A cor de uma cadeira, diferente da das outras do mesmo semestre (ver `Revisao.matizes`): um semestre a
    /// mais não muda as cores deste. Clara no modo escuro e mais carregada no modo claro, para o texto nessa cor
    /// se ler nos dois.
    func cor(_ cadeira: String) -> Color {
        let semestre = cadeiras.first { $0.nome == cadeira }?.semestre
        let doSemestre = cadeiras.filter { $0.semestre == semestre }.map { (nome: $0.nome, escolhida: $0.meta.cor) }
        return Self.cor(matiz: Revisao.matizes(doSemestre)[cadeira] ?? 0.6)
    }

    /// Uma cor da paleta das cadeiras, para o modo claro e o escuro.
    static func cor(matiz h: Double) -> Color {
        #if os(macOS)
        return Color(NSColor(name: nil) { aparencia in
            aparencia.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hue: h, saturation: 0.5, brightness: 0.9, alpha: 1)
                : NSColor(hue: h, saturation: 0.75, brightness: 0.72, alpha: 1)
        })
        #else
        return Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hue: h, saturation: 0.5, brightness: 0.9, alpha: 1)
                : UIColor(hue: h, saturation: 0.75, brightness: 0.72, alpha: 1)
        })
        #endif
    }

    /// As cadeiras de um semestre (nil = o mais recente), como a barra lateral do Mac.
    func cadeiras(no semestre: Semestre?) -> [Cadeira] {
        guard let s = semestre.flatMap({ semestres.contains($0) ? $0 : nil }) ?? semestres.first else { return [] }
        return cadeiras.filter { $0.semestre == s }
    }
}

/// O quadrado com a cor e a sigla da cadeira.
struct SiglaCadeira: View {
    @Environment(Library.self) private var library
    let nome: String
    var lado: CGFloat = 34

    var body: some View {
        Text(Revisao.sigla(nome))
            .font(.system(size: lado * 0.36, weight: .bold))
            .foregroundStyle(.black.opacity(0.72))
            .frame(width: lado, height: lado)
            .background(library.cor(nome), in: .rect(cornerRadius: lado * 0.29))
            .accessibilityHidden(true)
    }
}

enum DataAula {
    private static let pt = Locale(identifier: "pt_PT")
    private static let formatoCurto: DateFormatter = {
        let f = DateFormatter()
        f.locale = pt
        f.dateFormat = "d MMM"
        return f
    }()
    /// "23 out" (o formato do sistema em português dá "23/10").
    static func curta(_ data: Date) -> String { formatoCurto.string(from: data).replacingOccurrences(of: ".", with: "") }
    /// "23 de outubro"
    static func longa(_ data: Date) -> String { data.formatted(.dateTime.day().month(.wide).locale(pt)) }
}


/// Marcar uma aula como revista e o aviso com "Próxima" e "Desfazer" durante 5 segundos (no iPhone e no Mac).
@MainActor @Observable
final class AvisoRevista {
    struct Aviso: Equatable {
        var aula: Aula
        var proxima: Aula?
    }

    private(set) var atual: Aviso?
    private var fecho: Task<Void, Never>?
    /// O último erro ao gravar (o iPhone mostra-o num alerta): o iCloud pode recusar a escrita.
    var erro: String?

    /// `mostrar`: com o aviso (por exemplo, não ao desmarcar). Se não se conseguir gravar, lança e não há aviso.
    func marcar(_ aula: Aula, revista: Bool, library: Library, mostrar: Bool) throws {
        try library.definirRevista(revista, em: aula.pasta)
        fecho?.cancel()
        guard revista, mostrar else {
            atual = nil
            return
        }
        withAnimation(.snappy) { atual = Aviso(aula: aula, proxima: Revisao.proxima(depoisDe: aula, em: library.cadeiras)) }
        fecho = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.atual = nil }
        }
    }

    func desfazer(_ library: Library) throws {
        guard let atual else { return }
        fechar()
        try library.definirRevista(false, em: atual.aula.pasta)
    }

    func fechar() {
        fecho?.cancel()
        withAnimation(.snappy) { atual = nil }
    }
}

/// O aviso depois de marcar uma aula como revista (por cima da barra de separadores no iPhone, ao fundo da janela no Mac).
struct VistaAvisoRevista: View {
    let aviso: AvisoRevista.Aviso
    var aoProxima: (Aula) -> Void
    var aoDesfazer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Revista").font(.subheadline.weight(.semibold))
                Text(aviso.proxima.map { "Próxima: \($0.meta.titulo)" } ?? "Não há mais aulas por rever")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let proxima = aviso.proxima {
                Button("Próxima") { aoProxima(proxima) }.buttonStyle(.glassProminent)
            }
            Button("Desfazer", action: aoDesfazer).buttonStyle(.glass)
        }
        .controlSize(.small)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}


/// A barra de capítulos por baixo dos separadores da aula, como no design: um bloco por capítulo, da largura do seu
/// tempo, com o nome e uma marca por slide. Por baixo, o início, o capítulo onde está o rato (ou o escolhido) e o
/// fim. Clicar leva a esse momento da transcrição.
struct LinhaCapitulos: View {
    let capitulos: [Capitulos.Capitulo]
    var aoEscolher: (Capitulos.Capitulo) -> Void
    @State private var escolhido: Double?
    @State private var sobRato: Double?

    private var inicio: Double { capitulos.first?.inicio ?? 0 }
    private var fim: Double { capitulos.last?.fim ?? 1 }

    private var emFoco: Capitulos.Capitulo? {
        capitulos.first { $0.inicio == (sobRato ?? escolhido) }
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { g in
                let espaco: CGFloat = 3
                let util = max(0, g.size.width - espaco * CGFloat(capitulos.count - 1))
                HStack(spacing: espaco) {
                    ForEach(capitulos) { c in
                        let largura = util * CGFloat((c.fim - c.inicio) / max(1, fim - inicio))
                        Button {
                            escolhido = c.inicio
                            aoEscolher(c)
                        } label: {
                            bloco(c, comNome: largura > 44).frame(width: largura)
                        }
                        .buttonStyle(.plain)
                        .onHover { dentro in
                            if dentro { sobRato = c.inicio } else if sobRato == c.inicio { sobRato = nil }
                        }
                        .help(c.seccoes.count > 1 ? c.seccoes.joined(separator: "\n") : c.titulo)
                    }
                }
            }
            .frame(height: 30)
            HStack(spacing: 8) {
                Text(Self.relogio(inicio))
                Spacer(minLength: 0)
                if let c = emFoco {
                    Text("\(c.titulo) · \(Self.relogio(c.inicio))–\(Self.relogio(c.fim))"
                         + (c.slides > 0 ? " · \(c.slides) \(c.slides == 1 ? "slide" : "slides")" : ""))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(Self.relogio(fim))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    /// "1:54:12" (o `Timestamp.format` dá minutos:segundos, como os apontamentos).
    static func relogio(_ segundos: Double) -> String {
        let t = max(0, Int(segundos))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }

    private func bloco(_ c: Capitulos.Capitulo, comNome: Bool) -> some View {
        let ativo = escolhido == c.inicio
        let sob = sobRato == c.inicio
        return RoundedRectangle(cornerRadius: 6)
            .fill(ativo ? AnyShapeStyle(Color.accentColor.opacity(0.4))
                  : AnyShapeStyle(Color.primary.opacity(sob ? 0.13 : 0.07)))
            .overlay(alignment: .leading) {
                if comNome {
                    Text(c.titulo)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ativo ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            }
            .overlay(alignment: .bottom) {
                // Uma marca por slide que apareceu neste capítulo.
                HStack(spacing: 0) {
                    ForEach(0..<min(c.slides, 30), id: \.self) { _ in
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.4)).frame(width: 2, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 3)
            }
            .contentShape(.rect)
    }
}
