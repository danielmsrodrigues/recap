import Foundation
import Testing
@testable import Apontamentos

/// A pasta Recap no iCloud Drive: o iPhone e o iPad encontram-na sozinhos, e o Mac muda para lá as aulas de ~/Aulas.
struct PastaICloudTests {
    private let fm = FileManager.default

    private func temporaria() throws -> URL {
        let url = fm.temporaryDirectory.appending(path: "icloud-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Uma cadeira com uma aula, como o Recap a grava.
    private func cadeira(_ nome: String, em raiz: URL, aula: String = "2026-10-19_Aula 1") throws {
        let pasta = raiz.appending(path: nome)
        try fm.createDirectory(at: pasta.appending(path: aula), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pasta.appending(path: Disco.cadeiraJSON))
        try Data("# Aula".utf8).write(to: pasta.appending(path: aula).appending(path: Disco.apontamentosMD))
    }

    @Test func noMacAPastaFicaNosDocumentosDoICloudDoContentor() {
        let casa = URL(fileURLWithPath: "/Users/teste", isDirectory: true)
        #expect(PastaICloud.documentosMac(casa: casa).path
                == "/Users/teste/Library/Mobile Documents/iCloud~pt~danielrodrigues~Recap/Documents")
    }

    @Test func semContentorNoICloudOMacUsaAulas() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        #expect(PastaICloud.raizMac(casa: casa).lastPathComponent == "Aulas")
    }

    @Test func comContentorESemAulasAntigasOMacUsaOICloud() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        try fm.createDirectory(at: PastaICloud.documentosMac(casa: casa), withIntermediateDirectories: true)
        #expect(PastaICloud.raizMac(casa: casa) == PastaICloud.documentosMac(casa: casa))
    }

    /// Com aulas em ~/Aulas ainda não mudadas, continua lá: nunca troca para uma pasta vazia sem perguntar.
    @Test func comAulasAntigasOMacContinuaEmAulasAteMudar() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        try fm.createDirectory(at: PastaICloud.documentosMac(casa: casa), withIntermediateDirectories: true)
        try cadeira("Cálculo", em: casa.appending(path: "Aulas"))
        #expect(PastaICloud.raizMac(casa: casa).lastPathComponent == "Aulas")
        #expect(PastaICloud.deveOferecerMudanca(pastaEscolhida: "", casa: casa))
    }

    @Test func naoOfereceMudarSemContentorOuComPastaEscolhidaAMao() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        try cadeira("Cálculo", em: casa.appending(path: "Aulas"))
        #expect(!PastaICloud.deveOferecerMudanca(pastaEscolhida: "", casa: casa))
        try fm.createDirectory(at: PastaICloud.documentosMac(casa: casa), withIntermediateDirectories: true)
        #expect(!PastaICloud.deveOferecerMudanca(pastaEscolhida: "/Volumes/Disco/Aulas", casa: casa))
    }

    @Test func mudarLevaTudoEDeixaAulasVazia() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        let origem = casa.appending(path: "Aulas"), destino = PastaICloud.documentosMac(casa: casa)
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)
        try cadeira("Cálculo", em: origem)
        try cadeira("Álgebra Lineal", em: origem)
        try fm.createDirectory(at: origem.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)

        let ficaram = try PastaICloud.mudar(de: origem, para: destino)
        #expect(ficaram.isEmpty)
        #expect(fm.fileExists(atPath: destino.appending(path: "Álgebra Lineal").path))
        #expect(fm.fileExists(atPath: destino.appending(path: Disco.pastaSistema).path))
        #expect(fm.fileExists(atPath: destino.appending(path: "Cálculo/2026-10-19_Aula 1/\(Disco.apontamentosMD)").path))
        #expect(!fm.fileExists(atPath: origem.path))
    }

    /// Pastas com o mesmo nome juntam-se (o iPhone já criou `_recap` no iCloud, por exemplo); um ficheiro que já
    /// existe no iCloud não é substituído e o de ~/Aulas fica onde está.
    @Test func pastasIguaisJuntamSeEFicheirosRepetidosFicam() throws {
        let casa = try temporaria()
        defer { try? fm.removeItem(at: casa) }
        let origem = casa.appending(path: "Aulas"), destino = PastaICloud.documentosMac(casa: casa)
        try cadeira("Cálculo", em: origem)
        try cadeira("Física", em: origem)
        try cadeira("Cálculo", em: destino, aula: "2026-10-26_Aula 2")
        try fm.createDirectory(at: origem.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)
        try Data("pt".utf8).write(to: origem.appending(path: "\(Disco.pastaSistema)/definicoes.json"))
        try PastaICloud.preparar(destino)

        let ficaram = try PastaICloud.mudar(de: origem, para: destino)
        #expect(ficaram == ["Cálculo/\(Disco.cadeiraJSON)"])
        #expect(fm.fileExists(atPath: destino.appending(path: "Cálculo/2026-10-19_Aula 1").path))
        #expect(fm.fileExists(atPath: destino.appending(path: "Cálculo/2026-10-26_Aula 2").path))
        #expect(fm.fileExists(atPath: destino.appending(path: "Física").path))
        #expect(fm.fileExists(atPath: destino.appending(path: "\(Disco.pastaSistema)/definicoes.json").path))
        // Só fica o que não foi mudado.
        #expect(fm.fileExists(atPath: origem.appending(path: "Cálculo/\(Disco.cadeiraJSON)").path))
        #expect(!fm.fileExists(atPath: origem.appending(path: "Física").path))
        #expect(!fm.fileExists(atPath: origem.appending(path: Disco.pastaSistema).path))
    }

    /// No iPhone e no iPad: a pasta do contentor ganha `_recap`, para ser reconhecida como a pasta das aulas.
    @Test func prepararAPastaDoContentorMarcaAComoDoRecap() throws {
        let documentos = try temporaria().appending(path: "Documents")
        defer { try? fm.removeItem(at: documentos.deletingLastPathComponent()) }
        try PastaICloud.preparar(documentos)
        #expect(Disco.problemaPastaAulas(documentos) == nil)
    }
}
