import SwiftUI

/// Para onde se vai a partir das listas do iPhone (e do que abre do painel Estudo ou da pesquisa).
enum DestinoIOS: Hashable {
    /// A aula para ler (`AulaLeitura`).
    case aula(URL)
    /// A aula com tudo: transcrição, slides, materiais (`AulaDetailView`), para um momento ou um texto a realçar.
    case completa(URL)
    case cadeira(URL)
    /// "Sobre a cadeira" (a ficha), pela pasta da cadeira.
    case sobre(URL)
}

extension Library {
    /// A cor de uma cadeira, diferente da das outras do mesmo semestre (ver `Revisao.matizes`): um semestre a
    /// mais não muda as cores deste. Clara no modo escuro e mais carregada no modo claro, para o texto nessa cor
    /// se ler nos dois.
    func cor(_ cadeira: String) -> Color {
        let semestre = cadeiras.first { $0.nome == cadeira }?.semestre
        let h = Revisao.matizes(cadeiras.filter { $0.semestre == semestre }.map(\.nome))[cadeira] ?? 0.6
        return Color(UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hue: h, saturation: 0.5, brightness: 0.9, alpha: 1)
                : UIColor(hue: h, saturation: 0.75, brightness: 0.72, alpha: 1)
        })
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

/// Uma aula numa lista: o ponto da cor da cadeira, o título e uma linha por baixo.
struct LinhaAulaIOS: View {
    @Environment(Library.self) private var library
    let aula: Aula
    let detalhe: String
    var mostrarRevista = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(library.cor(aula.cadeira)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(aula.meta.titulo).lineLimit(2)
                Text(detalhe).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if mostrarRevista && aula.meta.revista {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.green)
                    .accessibilityLabel("Revista")
            }
        }
    }
}

/// O círculo para marcar uma aula como revista sem a abrir (Por rever, lista da cadeira).
struct BotaoRevista: View {
    let aula: Aula
    var acao: () -> Void

    var body: some View {
        Button(aula.meta.revista ? "Marcar como por rever" : "Marcar como revista",
               systemImage: aula.meta.revista ? "checkmark.circle.fill" : "circle", action: acao)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(aula.meta.revista ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            .buttonStyle(.borderless)
    }
}

/// "1.º sem." na barra, com os semestres todos no menu.
struct SeletorSemestre: View {
    @Environment(Library.self) private var library
    @Binding var semestre: Semestre?

    private var atual: Semestre? {
        semestre.flatMap { library.semestres.contains($0) ? $0 : nil } ?? library.semestres.first
    }

    var body: some View {
        if library.organizacao != .nenhuma, library.semestres.count > 1, let atual {
            Menu {
                Picker("Semestre", selection: Binding(get: { atual }, set: { semestre = $0 })) {
                    ForEach(library.semestres, id: \.self) { Text(library.nome($0)).tag($0) }
                }
            } label: {
                Text(curto(atual))
            }
        }
    }

    private func curto(_ s: Semestre) -> String {
        s.numero == 0 ? "\(s.ano).º ano" : "\(s.numero).º \(library.nomePeriodo.prefix(3))."
    }
}

/// Marcar uma aula como revista e, no iPhone, o aviso com "Próxima" e "Desfazer" durante 5 segundos.
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

/// O aviso por cima da barra de separadores depois de marcar uma aula como revista.
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

/// Texto dos apontamentos (Markdown com fórmulas e slides) dentro de uma vista nativa, à altura do texto.
struct TextoApontamentos: View {
    let markdown: String
    let pastaAula: URL
    /// Guardada por quem a mostra: ao voltar a abrir uma secção, a vista já nasce com a altura certa.
    @Binding var altura: CGFloat
    var aoClicarTimestamp: ((Double) -> Void)?
    var aoClicarSeccao: ((LigacaoSeccao) -> Void)?
    var aoPerguntar: ((String) -> Void)?

    var body: some View {
        NotesWebView(markdown: markdown, aoClicarTimestamp: aoClicarTimestamp, modo: "embutida", pastaAula: pastaAula,
                     aoPerguntar: aoPerguntar, aoClicarSeccao: aoClicarSeccao, aoMudarAltura: { altura = $0 })
            .frame(height: max(altura, 24))
    }
}
