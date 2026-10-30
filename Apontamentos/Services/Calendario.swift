import Foundation

extension Calendar {
    /// O calendário das grelhas: gregoriano, a semana começa à segunda, nomes em português.
    static var grelhaAulas: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "pt_PT")
        c.timeZone = .current
        return c
    }
}

/// A vista de calendário: as semanas do mês, as aulas de cada dia e o resumo do mês.
enum CalendarioAulas {
    /// Os dias da grelha do mês de `mes`: de segunda a domingo, da semana do dia 1 à semana do último dia.
    static func dias(do mes: Date, calendario: Calendar = .grelhaAulas) -> [Date] {
        guard let intervalo = calendario.dateInterval(of: .month, for: mes),
              let primeira = calendario.dateInterval(of: .weekOfYear, for: intervalo.start),
              let ultima = calendario.dateInterval(of: .weekOfYear, for: intervalo.end.addingTimeInterval(-1))
        else { return [] }
        var dias: [Date] = []
        var dia = primeira.start
        while dia < ultima.end {
            dias.append(dia)
            guard let seguinte = calendario.date(byAdding: .day, value: 1, to: dia) else { break }
            dia = seguinte
        }
        return dias
    }

    /// As aulas de cada dia (o início do dia), pela ordem em que foram criadas.
    static func porDia(_ aulas: [Aula], calendario: Calendar = .grelhaAulas) -> [Date: [Aula]] {
        Dictionary(grouping: aulas) { calendario.startOfDay(for: $0.meta.data) }
            .mapValues { $0.sorted { $0.meta.criadaEm < $1.meta.criadaEm } }
    }

    /// "13 aulas · 8 por rever", só com as aulas do mês de `mes`.
    static func resumo(_ aulas: [Aula], mes: Date, calendario: Calendar = .grelhaAulas) -> String {
        let doMes = aulas.filter { calendario.isDate($0.meta.data, equalTo: mes, toGranularity: .month) }
        guard !doMes.isEmpty else { return "Sem aulas neste mês" }
        let porRever = doMes.filter { $0.temApontamentos && !$0.meta.revista }.count
        let total = doMes.count == 1 ? "1 aula" : "\(doMes.count) aulas"
        return porRever > 0 ? "\(total) · \(porRever) por rever" : total
    }

    /// "Outubro 2026".
    static func titulo(_ mes: Date, calendario: Calendar = .grelhaAulas) -> String {
        let nome = calendario.monthSymbols[calendario.component(.month, from: mes) - 1]
        return nome.prefix(1).uppercased() + nome.dropFirst() + " \(calendario.component(.year, from: mes))"
    }
}
