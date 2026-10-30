import SwiftUI

/// Um aviso de exame: o que sai, as palavras do professor e a aula, com o minuto.
struct LinhaPistaExame: View {
    @Environment(Library.self) private var library
    let aula: Aula
    let pista: PistasExame.Pista

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pista.descricao.isEmpty ? pista.citacao : pista.descricao)
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
            if !pista.citacao.isEmpty, !pista.descricao.isEmpty {
                Text("«\(pista.citacao)»")
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Aula \(library.numeroDaAula(aula)) · \(Timestamp.format(pista.tempo))", systemImage: "play.circle")
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre a aula neste minuto")
    }
}

/// "Sai no exame": os avisos de todas as cadeiras do semestre, por cadeira e pela ordem das aulas. Tocar num aviso
/// abre a aula na transcrição, nesse minuto.
struct ListaPistasExame: View {
    @Environment(Library.self) private var library
    @Environment(Estudo.self) private var estudo
    @Environment(Navegacao.self) private var navegacao
    let cadeiras: [Cadeira]
    /// Lidos do disco fora do fio principal, e não a cada redesenho (eram dois `exame.json` por aula de cada vez).
    @State private var grupos: [PistasExame.Grupo] = []
    @State private var porVer: [Aula] = []
    @State private var lido = false

    var body: some View {
        List {
            ForEach(grupos) { grupo in
                Section {
                    ForEach(Array(grupo.pistas.enumerated()), id: \.offset) { _, item in
                        Button { abrir(item.aula, item.pista) } label: {
                            LinhaPistaExame(aula: item.aula, pista: item.pista)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack(spacing: 8) {
                        SiglaCadeira(nome: grupo.cadeira.nome, lado: 18)
                        Text(grupo.cadeira.nome)
                    }
                }
            }
        }
        .overlay {
            if lido, grupos.isEmpty {
                ContentUnavailableView("Ainda nada", systemImage: "star",
                                       description: Text("Quando um professor disser que uma matéria sai no exame, aparece aqui, com o minuto da aula."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { procura }
        // `estudo.versao` muda quando a procura nas aulas anteriores grava pistas novas; `library.versao`, quando chegam
        // aulas (do iCloud, por exemplo): volta a ler-se do disco.
        .task(id: "\(estudo.versao)·\(library.versao)·\(cadeiras.map(\.pasta.path))") {
            let cadeiras = cadeiras
            let lidos = await Task.detached {
                (PistasExame.porCadeira(cadeiras),
                 cadeiras.flatMap(\.aulas).filter { $0.temTranscricao && Disco.lerPistasExame($0.pasta) == nil })
            }.value
            grupos = lidos.0
            porVer = lidos.1
            lido = true
        }
    }

    private func abrir(_ aula: Aula, _ pista: PistasExame.Pista) {
        navegacao.destino = DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: pista.tempo)
    }

    /// As aulas gravadas antes desta funcionalidade ainda não foram vistas: no Mac, procura-se nelas.
    @ViewBuilder private var procura: some View {
        if let p = estudo.procuraExame {
            HStack(spacing: 10) {
                ProgressView(value: Double(p.feitas), total: Double(max(p.total, 1)))
                Text("A procurar nas aulas anteriores: \(p.feitas) de \(p.total)").font(.caption).monospacedDigit()
                Button("Parar") { estudo.cancelarPistasExame() }
            }
            .padding(12)
            .background(.bar)
        } else if !porVer.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(porVer.count == 1 ? "Há 1 aula onde ainda não se procurou." : "Há \(porVer.count) aulas onde ainda não se procurou.")
                    .font(.callout)
                #if os(macOS)
                Button("Procurar nas aulas anteriores") { estudo.procurarPistasExame(porVer) }
                    .buttonStyle(.borderedProminent)
                #else
                Text("Faz-se no Mac: em \"Sai no exame\", \"Procurar nas aulas anteriores\".")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
                if let erro = estudo.erroExame {
                    Text(erro).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.bar)
        }
    }
}
