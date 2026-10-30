import Foundation
import Testing
@testable import Apontamentos

/// A vista de calendário do Mac: a grelha do mês, as aulas de cada dia e o resumo do mês.
struct CalendarioTests {
    private let cal = Calendar.grelhaAulas

    private func dia(_ ano: Int, _ mes: Int, _ dia: Int, _ hora: Int = 12) -> Date {
        cal.date(from: DateComponents(year: ano, month: mes, day: dia, hour: hora))!
    }

    private func aula(_ titulo: String, _ data: Date, criadaEm: Date? = nil, revista: Bool = false, apontamentos: Bool = true) -> Aula {
        var meta = AulaMeta(titulo: titulo, data: data, video: nil)
        meta.revista = revista
        if let criadaEm { meta.criadaEm = criadaEm }
        return Aula(pasta: URL(filePath: "/aulas/C/\(titulo)"), cadeira: "C", meta: meta,
                    temTranscricao: true, temApontamentos: apontamentos, temSlides: false)
    }

    @Test func aGrelhaComecaNaSegundaEAcabaNoDomingoComSemanasInteiras() {
        // Outubro de 2026 começa numa quinta e acaba num sábado: de 28 de setembro a 1 de novembro.
        let dias = CalendarioAulas.dias(do: dia(2026, 10, 15), calendario: cal)
        #expect(dias.count == 35)
        #expect(cal.dateComponents([.month, .day], from: dias.first!) == DateComponents(month: 9, day: 28))
        #expect(cal.dateComponents([.month, .day], from: dias.last!) == DateComponents(month: 11, day: 1))
        #expect(cal.component(.weekday, from: dias.first!) == 2)
    }

    @Test func umMesQuePrecisaDeSeisSemanas() {
        // Agosto de 2026 começa num sábado: 6 linhas.
        #expect(CalendarioAulas.dias(do: dia(2026, 8, 1), calendario: cal).count == 42)
    }

    @Test func asAulasFicamNoSeuDiaPelaOrdemEmQueForamCriadas() {
        let a = aula("Tarde", dia(2026, 10, 29, 18), criadaEm: dia(2026, 10, 29, 20))
        let b = aula("Manhã", dia(2026, 10, 29, 9), criadaEm: dia(2026, 10, 29, 10))
        let c = aula("Outra", dia(2026, 10, 28))
        let porDia = CalendarioAulas.porDia([a, b, c], calendario: cal)
        #expect(porDia[cal.startOfDay(for: dia(2026, 10, 29))]?.map(\.meta.titulo) == ["Manhã", "Tarde"])
        #expect(porDia[cal.startOfDay(for: dia(2026, 10, 28))]?.map(\.meta.titulo) == ["Outra"])
    }

    @Test func oResumoContaAsAulasDoMesEAsPorRever() {
        let aulas = [aula("A", dia(2026, 10, 1), revista: true), aula("B", dia(2026, 10, 2)),
                     aula("C", dia(2026, 10, 3), apontamentos: false), aula("Setembro", dia(2026, 9, 30))]
        #expect(CalendarioAulas.resumo(aulas, mes: dia(2026, 10, 15), calendario: cal) == "3 aulas · 1 por rever")
        #expect(CalendarioAulas.resumo([aula("A", dia(2026, 10, 1), revista: true)], mes: dia(2026, 10, 15), calendario: cal) == "1 aula")
        #expect(CalendarioAulas.resumo(aulas, mes: dia(2026, 12, 1), calendario: cal) == "Sem aulas neste mês")
    }

    @Test func oTituloDoMesComMaiuscula() {
        #expect(CalendarioAulas.titulo(dia(2026, 10, 15)) == "Outubro 2026")
    }
}
