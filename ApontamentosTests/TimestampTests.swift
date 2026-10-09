import Foundation
import Testing
@testable import Apontamentos

struct TimestampTests {
    @Test func formataMinutosParaLaDeUmaHora() {
        #expect(Timestamp.format(0) == "00:00")
        #expect(Timestamp.format(65.9) == "01:05")
        #expect(Timestamp.format(5_399) == "89:59")
    }

    @Test func interpretaMmSsEHMmSs() {
        #expect(Timestamp.parse("01:05") == 65)
        #expect(Timestamp.parse("89:59") == 5_399)
        #expect(Timestamp.parse("1:02:03") == 3_723)
        #expect(Timestamp.parse("1:60") == nil)
        #expect(Timestamp.parse("abc") == nil)
        #expect(Timestamp.parse("12") == nil)
    }

    @Test func duracaoLegivel() {
        #expect(Timestamp.duracao(40) == "40 s")
        #expect(Timestamp.duracao(45 * 60) == "45 min")
        #expect(Timestamp.duracao(92 * 60) == "1 h 32 min")
    }

    @Test func transcricaoComTimestamps() {
        let t = Transcricao(idioma: "es", modelo: "m", duracao: 70, criadaEm: .now, segmentos: [
            Segmento(inicio: 0, fim: 4, texto: "Buenos días."),
            Segmento(inicio: 65, fim: 70, texto: "La matriz A."),
        ])
        #expect(t.textoComTimestamps == "[00:00] Buenos días.\n[01:05] La matriz A.")
    }
}
