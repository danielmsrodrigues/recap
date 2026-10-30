import SwiftUI

/// A grelha de um mês, de segunda a domingo, com uma linha fina entre os dias. O conteúdo de cada dia vem de quem a
/// usa: as aulas por extenso no Mac e no iPad, pontos no iPhone.
struct GrelhaMes<Dia: View>: View {
    let mes: Date
    var calendario: Calendar = .grelhaAulas
    /// Os nomes dos dias por cima do número (à direita no Mac e no iPad, como no design; ao centro no iPhone).
    var nomesADireita = false
    @ViewBuilder var dia: (_ data: Date, _ doMes: Bool) -> Dia

    /// "Seg", "Ter"… a começar na segunda.
    private var diasDaSemana: [String] {
        let nomes = calendario.weekdaySymbols.map { $0.prefix(1).uppercased() + $0.dropFirst().prefix(2) }
        return Array(nomes[1...] + nomes[..<1])
    }

    var body: some View {
        let dias = CalendarioAulas.dias(do: mes, calendario: calendario)
        let semanas = stride(from: 0, to: dias.count, by: 7).map { Array(dias[$0..<min($0 + 7, dias.count)]) }
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(diasDaSemana, id: \.self) { nome in
                    Text(nome)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, nomesADireita ? 10 : 0)
                        .frame(maxWidth: .infinity, alignment: nomesADireita ? .trailing : .center)
                }
            }
            // O espaço de um ponto entre os dias deixa ver o fundo: são as linhas da grelha.
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(semanas, id: \.first) { semana in
                    GridRow {
                        ForEach(semana, id: \.self) { data in
                            dia(data, calendario.isDate(data, equalTo: mes, toGranularity: .month))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background(calendario.isDateInWeekend(data) ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.background))
                        }
                    }
                }
            }
            .background(.separator)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        }
    }
}

/// O número do dia: o de hoje num círculo vermelho; o dia 1 leva o mês ("1 nov"), para se ver onde começa o seguinte.
struct NumeroDia: View {
    let data: Date
    var doMes = true
    var escolhido = false
    /// No iPhone não cabe "1 nov": só o número.
    var comMes = true
    var calendario: Calendar = .grelhaAulas

    var body: some View {
        let hoje = calendario.isDateInToday(data)
        let numero = calendario.component(.day, from: data)
        let mes = calendario.shortMonthSymbols[calendario.component(.month, from: data) - 1].replacingOccurrences(of: ".", with: "")
        // Hoje a vermelho; o dia escolhido (no iPhone) na cor do texto, com o número na cor do fundo.
        let cor: AnyShapeStyle = hoje ? AnyShapeStyle(Color.white)
            : escolhido ? AnyShapeStyle(.background)
            : doMes ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        let fundo: AnyShapeStyle = hoje ? AnyShapeStyle(Color.red) : escolhido ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.clear)
        Text(numero == 1 && comMes ? "1 \(mes)" : "\(numero)")
            .font(.callout.weight(hoje || escolhido ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(cor)
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: 26)
            .background(fundo, in: .capsule)
    }
}

/// Uma aula num dia do calendário: o quadrado da cor da cadeira, o tema e o ponto azul se estiver por rever.
struct ChipAula: View {
    @Environment(Library.self) private var library
    let aula: Aula

    var body: some View {
        let cor = library.cor(aula.cadeira)
        let porRever = aula.temApontamentos && !aula.meta.revista
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(cor).frame(width: 7, height: 7)
            Text(TituloAula.separar(aula.meta.titulo)?.tema ?? aula.meta.titulo)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            if porRever {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 22)
        .background(cor.opacity(0.22), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(aula.cadeira), \(aula.meta.titulo)\(porRever ? ", por rever" : "")")
    }
}

/// "Aula transcrita" e "Por rever", por baixo da grelha.
struct LegendaCalendario: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(width: 14, height: 10)
                Text("Aula transcrita")
            }
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                Text("Por rever")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
