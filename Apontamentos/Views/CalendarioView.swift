#if os(macOS)
import SwiftUI

/// O calendário das aulas, um mês de cada vez, como no design: as semanas de segunda a domingo, e em cada dia as
/// aulas com a cor da cadeira e o ponto azul das que estão por rever. Clicar numa aula abre-a.
struct CalendarioView: View {
    @Environment(Library.self) private var library
    var aoTranscrever: () -> Void
    var aoAbrir: (URL) -> Void

    @State private var mes = Date.now
    private let calendario = Calendar.grelhaAulas

    /// Todas as aulas, de todos os semestres: cada mês só mostra as suas.
    private var aulas: [Aula] { library.cadeiras.flatMap(\.aulas) }

    var body: some View {
        let porDia = CalendarioAulas.porDia(aulas, calendario: calendario)
        VStack(spacing: 10) {
            GrelhaMes(mes: mes, calendario: calendario, nomesADireita: true) { data, doMes in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Spacer(minLength: 0)
                        NumeroDia(data: data, doMes: doMes, calendario: calendario)
                    }
                    ForEach(porDia[data] ?? []) { aula in
                        Button { aoAbrir(aula.pasta) } label: { ChipAula(aula: aula) }
                            .buttonStyle(.plain)
                            .help("\(aula.cadeira) · Aula \(library.numeroDaAula(aula)) — \(aula.meta.titulo)")
                    }
                }
                // Os dias dos meses ao lado ficam esbatidos.
                .opacity(doMes ? 1 : 0.45)
                .padding(6)
            }
            LegendaCalendario().padding(.horizontal, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .navigationTitle(CalendarioAulas.titulo(mes, calendario: calendario))
        .navigationSubtitle(CalendarioAulas.resumo(aulas, mes: mes, calendario: calendario))
        .toolbar {
            ToolbarItem { BotaoTranscrever(aoTranscrever: aoTranscrever) }
            ToolbarSpacer(.flexible)
            ToolbarItem {
                ControlGroup {
                    Button("Mês anterior", systemImage: "chevron.left") { mudar(-1) }
                        .keyboardShortcut(.leftArrow, modifiers: .command)
                    Button("Hoje") { mes = .now }
                        .keyboardShortcut("t", modifiers: .command)
                    Button("Mês seguinte", systemImage: "chevron.right") { mudar(1) }
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                }
                .help("Mês anterior (⌘←) · Hoje (⌘T) · Mês seguinte (⌘→)")
            }
        }
    }

    private func mudar(_ meses: Int) {
        if let novo = calendario.date(byAdding: .month, value: meses, to: mes) { mes = novo }
    }
}
#endif
