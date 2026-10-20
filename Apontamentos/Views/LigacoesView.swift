import SwiftUI

/// Ligações da aula com as outras da cadeira: linha do tempo com arcos e cartões por aula.
struct LigacoesView: View {
    @Environment(Estudo.self) private var estudo
    @Environment(Definicoes.self) private var definicoes
    @Environment(Library.self) private var library
    let aula: Aula
    var aoClicarTimestamp: (Double) -> Void
    var aoAbrirAula: (URL) -> Void

    @State private var dados: LigacoesAula?

    private var emCurso: Bool { estudo.emCurso(aula, .ligacoes) != nil }
    private var aulas: [Aula] { (library.cadeira(nome: aula.cadeira)?.aulas ?? []).sorted { $0.meta.data < $1.meta.data } }

    private func outra(_ caminho: String) -> Aula? {
        library.aula(em: library.raiz.appending(path: caminho, directoryHint: .isDirectory))
    }

    var body: some View {
        VStack(spacing: 0) {
            if dados != nil || emCurso {
                barra
                Divider()
            }
            if emCurso {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("A procurar ligações com as outras aulas…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let dados {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(spacing: 4) {
                            LinhaDoTempo(aulas: aulas, atual: aula, ligacoes: dados.ligacoes, aoAbrir: aoAbrirAula)
                            HStack(spacing: 14) {
                                legenda(.blue, "vem dessa aula")
                                legenda(.purple, "continua nessa aula")
                                legenda(.secondary, "sem ligação")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        seccao("Vem de aulas anteriores", cor: .blue, ligacoes: dados.ligacoes.filter { $0.direcao == .anterior })
                        seccao("Continua em aulas seguintes", cor: .purple, ligacoes: dados.ligacoes.filter { $0.direcao == .seguinte })
                        temas(dados.temas)
                        if dados.ligacoes.isEmpty && dados.temas.isEmpty {
                            Text("Não foram encontradas ligações com as outras aulas da cadeira.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                }
            } else {
                vazio
            }
        }
        .task(id: estudo.versao) { dados = Disco.lerLigacoes(aula.pasta) }
    }

    // MARK: Partes

    private func legenda(_ cor: Color, _ texto: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(cor).frame(width: 7, height: 7)
            Text(texto)
        }
    }

    private var barra: some View {
        HStack {
            if let erro = estudo.erro(aula, .ligacoes) {
                Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if !emCurso, estudo.ligacoesDesatualizadas(aula) {
                Label("Há aulas novas ou apontamentos alterados desde estas ligações.", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if emCurso {
                Button("Parar", systemImage: "stop.circle") { estudo.cancelar(aula, .ligacoes) }
            } else {
                Button("Gerar de novo", systemImage: "arrow.clockwise") { estudo.gerarLigacoes(aula) }
                    .disabled(definicoes.faltaParaGerar != nil)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var vazio: some View {
        ContentUnavailableView {
            Label("Ligações com outras aulas", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            if let erro = estudo.erro(aula, .ligacoes) {
                Text(erro)
            } else if !aula.temApontamentos {
                Text("As ligações precisam dos apontamentos desta aula.")
            } else {
                Text("O que esta aula usa de aulas anteriores, o que vai ser usado mais à frente e os temas em comum, numa linha do tempo da cadeira.")
            }
        } actions: {
            if definicoes.faltaParaGerar != nil {
                SettingsLink { Text("Abrir Definições…") }
            } else {
                Button("Gerar ligações") { estudo.gerarLigacoes(aula) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!aula.temApontamentos)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func seccao(_ titulo: String, cor: Color, ligacoes: [LigacoesAula.Ligacao]) -> some View {
        if !ligacoes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(titulo, systemImage: cor == .blue ? "arrow.down.forward.circle.fill" : "arrow.up.forward.circle.fill")
                    .font(.headline)
                    .foregroundStyle(cor)
                ForEach(ligacoes, id: \.self) { cartao($0, cor: cor) }
            }
        }
    }

    private func cartao(_ l: LigacoesAula.Ligacao, cor: Color) -> some View {
        let destino = outra(l.aula)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    if let destino { aoAbrirAula(destino.pasta) }
                } label: {
                    Text(destino?.meta.titulo ?? "Aula apagada").font(.headline).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(destino == nil ? Color.secondary : Color.primary)
                .disabled(destino == nil)
                Spacer(minLength: 8)
                if let destino {
                    Text(destino.meta.data.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !l.conceitos.isEmpty {
                Fluxo(espaco: 6) {
                    ForEach(l.conceitos, id: \.self) { c in
                        Text(c)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(cor.opacity(0.16), in: .capsule)
                            .foregroundStyle(cor)
                    }
                }
            }
            Text(l.explicacao)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let m = l.momento, let t = Timestamp.parse(m) {
                Button { aoClicarTimestamp(t) } label: {
                    Label("Nesta aula aos \(m)", systemImage: "play.circle").font(.caption)
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12).fill(cor).frame(width: 4)
        }
    }

    @ViewBuilder
    private func temas(_ temas: [LigacoesAula.Tema]) -> some View {
        if !temas.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Temas em comum", systemImage: "circle.hexagongrid.fill").font(.headline).foregroundStyle(.teal)
                ForEach(temas, id: \.self) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(t.tema).font(.subheadline.weight(.semibold))
                            Fluxo(espaco: 6) {
                                ForEach(t.aulas, id: \.self) { caminho in
                                    if let o = outra(caminho) {
                                        Button(o.meta.titulo) { aoAbrirAula(o.pasta) }
                                            .buttonStyle(.plain)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.teal.opacity(0.16), in: .capsule)
                                            .foregroundStyle(.teal)
                                    }
                                }
                            }
                        }
                        Text(t.explicacao).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
                }
            }
        }
    }
}

/// As aulas da cadeira por ordem, com arcos da aula atual para as aulas ligadas
/// (azul: vem de lá; roxo: continua lá; mais grosso com mais conceitos).
private struct LinhaDoTempo: View {
    let aulas: [Aula]
    let atual: Aula
    let ligacoes: [LigacoesAula.Ligacao]
    var aoAbrir: (URL) -> Void

    private let largura: CGFloat = 132
    private let alturaArcos: CGFloat = 64

    private func ligacao(_ a: Aula) -> LigacoesAula.Ligacao? {
        ligacoes.first { a.pasta.standardizedFileURL.path.hasSuffix("/" + $0.aula) }
    }

    var body: some View {
        // Centrada quando cabe; com muitas aulas desliza na horizontal e abre centrada na aula atual.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                conteudo
                    .containerRelativeFrame(.horizontal, alignment: .center) { visivel, _ in
                        max(visivel, largura * CGFloat(aulas.count) + 8)
                    }
            }
            .onAppear { proxy.scrollTo(atual.id, anchor: .center) }
        }
        .frame(height: alturaArcos + 70)
    }

    private var conteudo: some View {
        let iAtual = aulas.firstIndex { $0.pasta.mesmoCaminho(atual.pasta) } ?? 0
        return ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let y = alturaArcos + 9
                    var base = Path()
                    base.move(to: CGPoint(x: largura / 2, y: y))
                    base.addLine(to: CGPoint(x: largura * (CGFloat(aulas.count) - 0.5), y: y))
                    ctx.stroke(base, with: .color(.secondary.opacity(0.35)), lineWidth: 2)
                    let xa = largura * (CGFloat(iAtual) + 0.5)
                    for (j, a) in aulas.enumerated() {
                        guard let l = ligacao(a) else { continue }
                        let xb = largura * (CGFloat(j) + 0.5)
                        let altura = min(alturaArcos - 4, 22 + 14 * CGFloat(abs(j - iAtual)))
                        var arco = Path()
                        arco.move(to: CGPoint(x: xa, y: y))
                        arco.addQuadCurve(to: CGPoint(x: xb, y: y), control: CGPoint(x: (xa + xb) / 2, y: y - altura * 2))
                        ctx.stroke(arco, with: .color(l.direcao == .anterior ? .blue : .purple),
                                   style: StrokeStyle(lineWidth: 1.5 + CGFloat(min(l.conceitos.count, 5)) * 0.6, lineCap: .round))
                    }
                }
                .frame(width: largura * CGFloat(aulas.count), height: alturaArcos + 20)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(aulas.enumerated()), id: \.element.id) { j, a in
                        no(a, atual: j == iAtual, ligacao: ligacao(a))
                    }
                }
                .padding(.top, alturaArcos)
            }
            .padding(.horizontal, 4)
    }

    private func no(_ a: Aula, atual: Bool, ligacao: LigacoesAula.Ligacao?) -> some View {
        let cor: Color = atual ? .accentColor : (ligacao?.direcao == .anterior ? .blue : (ligacao != nil ? .purple : .secondary))
        return VStack(spacing: 5) {
            ZStack {
                Circle().fill(ligacao == nil && !atual ? Color.clear : cor).frame(width: 18, height: 18)
                Circle().strokeBorder(cor, lineWidth: 2).frame(width: 18, height: 18)
                if atual { Circle().strokeBorder(cor.opacity(0.35), lineWidth: 4).frame(width: 28, height: 28) }
            }
            .frame(height: 18)
            Text(a.meta.titulo)
                .font(.caption.weight(atual ? .semibold : .regular))
                .foregroundStyle(atual || ligacao != nil ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(a.meta.data.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: largura)
        .contentShape(.rect)
        .onTapGesture { if !atual { aoAbrir(a.pasta) } }
    }
}

/// Dispõe os elementos em linhas, passando à seguinte quando não cabem (etiquetas).
struct Fluxo: Layout {
    var espaco: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alturaLinha: CGFloat = 0, maiorX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0, x + t.width > largura { x = 0; y += alturaLinha + espaco; alturaLinha = 0 }
            x += t.width + espaco
            maiorX = max(maiorX, x - espaco)
            alturaLinha = max(alturaLinha, t.height)
        }
        return CGSize(width: maiorX, height: y + alturaLinha)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alturaLinha: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { x = bounds.minX; y += alturaLinha + espaco; alturaLinha = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espaco
            alturaLinha = max(alturaLinha, t.height)
        }
    }
}
