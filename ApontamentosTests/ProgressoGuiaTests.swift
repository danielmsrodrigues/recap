import Foundation
import Testing
@testable import Apontamentos

/// O progresso do programa: que temas da guia já foram dados nas aulas, quais ficaram a meio e quais faltam.
struct ProgressoGuiaTests {
    private let indice = IndiceGuia(hash: "h", desvio: 0, seccoes: [
        SeccaoGuia(id: "1", titulo: "N´umeros reales", paginaInicio: 1, paginaFim: 4),
        SeccaoGuia(id: "1.1", titulo: "Racionales", paginaInicio: 1, paginaFim: 2),
        SeccaoGuia(id: "1.2", titulo: "Irracionales", paginaInicio: 3, paginaFim: 4),
        SeccaoGuia(id: "2", titulo: "Funciones", paginaInicio: 5, paginaFim: 8),
        SeccaoGuia(id: "3", titulo: "L´ımites", paginaInicio: 9, paginaFim: 12),
    ])

    private func aula(_ titulo: String, dia: Int) -> Aula {
        Aula(pasta: URL(filePath: "/aulas/Cálculo/\(titulo)"), cadeira: "Cálculo",
             meta: AulaMeta(titulo: titulo, data: Date(timeIntervalSince1970: Double(dia) * 86_400), video: nil),
             temTranscricao: true, temApontamentos: true, temSlides: false)
    }

    @Test func explicadaEVistaRemetidaOuMencionadaFicaEmCursoORestoPorVer() {
        let a1 = aula("Aula 1", dia: 1), a2 = aula("Aula 2", dia: 8)
        let temas = ProgressoGuia.calcular(indice, aulas: [
            (a1, SeccoesGuardadas(explicadas: ["1.1"], remetidas: [], mencionadas: ["2"])),
            (a2, SeccoesGuardadas(explicadas: ["2"], remetidas: ["1.2"], mencionadas: [])),
        ])
        let estado = Dictionary(uniqueKeysWithValues: temas.map { ($0.seccao.id, $0.estado) })
        #expect(estado["1.1"] == .vista)
        #expect(estado["1.2"] == .emCurso)
        // Mencionada numa aula e explicada noutra: vista.
        #expect(estado["2"] == .vista)
        #expect(estado["3"] == .porVer)
        #expect(temas.first { $0.seccao.id == "2" }?.aulas.map(\.meta.titulo) == ["Aula 1", "Aula 2"])
    }

    @Test func umTemaComSubtemasContaPelosSubtemas() {
        let temas = ProgressoGuia.calcular(indice, aulas: [
            (aula("Aula 1", dia: 1), SeccoesGuardadas(explicadas: ["1.1", "1.2"], remetidas: [], mencionadas: [])),
        ])
        #expect(temas.first { $0.seccao.id == "1" }?.estado == .vista)
        let parcial = ProgressoGuia.calcular(indice, aulas: [
            (aula("Aula 1", dia: 1), SeccoesGuardadas(explicadas: ["1.1"], remetidas: [], mencionadas: [])),
        ])
        #expect(parcial.first { $0.seccao.id == "1" }?.estado == .emCurso)
    }

    @Test func oResumoContaOsTemasPrincipais() {
        let temas = ProgressoGuia.calcular(indice, aulas: [
            (aula("Aula 1", dia: 1), SeccoesGuardadas(explicadas: ["1.1", "1.2", "2"], remetidas: [], mencionadas: [])),
        ])
        #expect(ProgressoGuia.resumo(temas) == "Vistos 2 de 3 temas")
    }

    @Test func osAcentosPartidosDoPDFFicamCertos() {
        #expect(ProgressoGuia.titulo("N´umeros reales") == "Números reales")
        #expect(ProgressoGuia.titulo("L´ımites, continuidad y c´alculo diferencial") == "Límites, continuidad y cálculo diferencial")
        #expect(ProgressoGuia.titulo("Sucesi´on") == "Sucesión")
    }

    @Test func guardaASelecaoDaAulaPelosIdsDasSeccoes() throws {
        let selecao = SelecaoGuia(explicadas: [1], remetidas: [4], mencionadas: [])
        let guardadas = SeccoesGuardadas(selecao, indice: indice)
        #expect(guardadas == SeccoesGuardadas(explicadas: ["1.1"], remetidas: ["3"], mencionadas: []))

        let pasta = FileManager.default.temporaryDirectory.appending(path: "guia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        #expect(Disco.lerSeccoesGuia(pasta) == nil)
        try Disco.escreverSeccoesGuia(guardadas, em: pasta)
        #expect(Disco.lerSeccoesGuia(pasta) == guardadas)
    }
}
