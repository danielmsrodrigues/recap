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
