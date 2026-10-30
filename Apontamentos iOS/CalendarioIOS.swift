import SwiftUI

/// O calendário das aulas no iPad e no iPhone. No iPad, o mês inteiro com as aulas por extenso, como no Mac. No
/// iPhone não cabem: cada dia tem um ponto por aula, e por baixo aparecem as aulas do dia escolhido.
struct CalendarioIOS: View {
    @Environment(Library.self) private var library
    @Environment(\.horizontalSizeClass) private var largura
    /// No iPad, a aula abre na coluna da direita; no iPhone (nil), entra na pilha do separador.
    var aoAbrir: ((URL) -> Void)?

    private let calendario = Calendar.grelhaAulas
    @State private var mes = Date.now
    @State private var escolhido = Calendar.grelhaAulas.startOfDay(for: .now)

    /// Todas as aulas, de todos os semestres: cada mês só mostra as suas.
    private var aulas: [Aula] { library.cadeiras.flatMap(\.aulas) }

    var body: some View {
        let porDia = CalendarioAulas.porDia(aulas, calendario: calendario)
        Group {
            if largura == .regular {
                grande(porDia)
            } else {
                telefone(porDia)
            }
        }
        .navigationTitle(CalendarioAulas.titulo(mes, calendario: calendario))
        .navigationSubtitle(CalendarioAulas.resumo(aulas, mes: mes, calendario: calendario))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Mês anterior", systemImage: "chevron.left") { mudar(-1) }
                Button("Hoje") {
                    mes = .now
                    escolhido = calendario.startOfDay(for: .now)
                }
                Button("Mês seguinte", systemImage: "chevron.right") { mudar(1) }
            }
        }
        .refreshable { library.recarregar(forcar: true) }
    }

    private func mudar(_ meses: Int) {
        guard let novo = calendario.date(byAdding: .month, value: meses, to: mes) else { return }
        mes = novo
        // No iPhone, o dia escolhido passa para o mês novo: o dia 1, ou hoje se for o mês de hoje.
        escolhido = calendario.isDate(novo, equalTo: .now, toGranularity: .month)
            ? calendario.startOfDay(for: .now)
            : calendario.dateInterval(of: .month, for: novo)?.start ?? escolhido
    }

    // MARK: iPad

    private func grande(_ porDia: [Date: [Aula]]) -> some View {
        VStack(spacing: 10) {
            GrelhaMes(mes: mes, calendario: calendario, nomesADireita: true) { data, doMes in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Spacer(minLength: 0)
                        NumeroDia(data: data, doMes: doMes, calendario: calendario)
                    }
                    ForEach(porDia[data] ?? []) { aula in
                        ligacao(aula) { ChipAula(aula: aula) }
                    }
                }
                .opacity(doMes ? 1 : 0.45)
                .padding(6)
            }
            LegendaCalendario().padding(.horizontal, 4)
        }
        .padding(16)
    }

    // MARK: iPhone

    private func telefone(_ porDia: [Date: [Aula]]) -> some View {
        List {
            Section {
                GrelhaMes(mes: mes, calendario: calendario) { data, doMes in
                    Button { escolhido = data } label: {
                        VStack(spacing: 4) {
                            NumeroDia(data: data, doMes: doMes, escolhido: data == escolhido, comMes: false, calendario: calendario)
                            pontos(porDia[data] ?? [])
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.vertical, 4)
                        .opacity(doMes ? 1 : 0.4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rotuloDoDia(data, aulas: porDia[data] ?? []))
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            }
            Section(nomeDoDia(escolhido)) {
                let doDia = porDia[escolhido] ?? []
                if doDia.isEmpty {
                    Text("Sem aulas neste dia").foregroundStyle(.secondary)
                }
                ForEach(doDia) { aula in
                    ligacao(aula) {
                        LinhaAulaIOS(aula: aula, detalhe: "\(Revisao.sigla(aula.cadeira)) · Aula \(library.numeroDaAula(aula))",
                                     mostrarRevista: true)
                    }
                }
            }
        }
    }

    /// Até três pontos com a cor da cadeira de cada aula do dia; com mais, um "+".
    private func pontos(_ aulas: [Aula]) -> some View {
        HStack(spacing: 3) {
            ForEach(aulas.prefix(3)) { aula in
                Circle().fill(library.cor(aula.cadeira)).frame(width: 6, height: 6)
            }
            if aulas.count > 3 {
                Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .frame(height: 6)
    }

    private func nomeDoDia(_ dia: Date) -> String {
        let texto = dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_PT")))
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    private func rotuloDoDia(_ dia: Date, aulas: [Aula]) -> String {
        aulas.isEmpty ? nomeDoDia(dia) : "\(nomeDoDia(dia)), \(aulas.count == 1 ? "1 aula" : "\(aulas.count) aulas")"
    }

    /// No iPad, um botão que abre a aula na coluna da direita; no iPhone, uma ligação na pilha do separador.
    @ViewBuilder private func ligacao<Rotulo: View>(_ aula: Aula, @ViewBuilder rotulo: () -> Rotulo) -> some View {
        if let aoAbrir {
            Button { aoAbrir(aula.pasta) } label: { rotulo() }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: DestinoIOS.aula(aula.pasta)) { rotulo() }
        }
    }
}
