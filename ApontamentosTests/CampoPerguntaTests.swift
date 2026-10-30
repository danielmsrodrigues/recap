import AppKit
import Foundation
import Testing
@testable import Apontamentos

/// O campo das perguntas no Mac: cresce com o texto, ↩ envia, ⇧↩ muda de linha, e cola ficheiros e imagens.
@MainActor
struct CampoPerguntaTests {
    private func tecla(_ shift: Bool = false, codigo: UInt16 = 36) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: codigo)!
    }

    private func campo(_ texto: String) -> TextoPergunta {
        let t = TextoPergunta(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        t.string = texto
        t.setSelectedRange(NSRange(location: (texto as NSString).length, length: 0))
        return t
    }

    @Test func enterEnvia() {
        let t = campo("Porquê?")
        var enviados = 0
        t.aoEnviar = { enviados += 1 }
        t.keyDown(with: tecla())
        t.keyDown(with: tecla(codigo: 76)) // o Enter do teclado numérico
        #expect(enviados == 2)
        #expect(t.string == "Porquê?")
    }

    @Test func shiftEnterMudaDeLinhaOndeEstaOCursor() {
        let t = campo("primeira segunda")
        var enviados = 0
        t.aoEnviar = { enviados += 1 }
        t.setSelectedRange(NSRange(location: 8, length: 1))
        t.keyDown(with: tecla(true))
        #expect(enviados == 0)
        #expect(t.string == "primeira\nsegunda")
    }

    @Test func alturaCresceAteAoMaximoDeLinhas() {
        let t = campo("uma")
        let umaLinha = t.alturaDoTexto(largura: 300)
        t.string = "uma\nduas\ntrês"
        let tresLinhas = t.alturaDoTexto(largura: 300)
        #expect(tresLinhas > umaLinha * 2.5)
        t.string = Array(repeating: "linha", count: 30).joined(separator: "\n")
        #expect(CampoPergunta.altura(texto: t, largura: 300, linhasMaximas: 6) <= umaLinha * 6 + 1)
        #expect(CampoPergunta.altura(texto: campo(""), largura: 300, linhasMaximas: 6) == umaLinha)
    }

    @Test func colaFicheirosCopiadosNoFinder() throws {
        let pb = NSPasteboard(name: .init("teste-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appending(path: "notas.xlsx")
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        #expect(TextoPergunta.ficheirosParaColar(pb) == [url])
    }

    @Test func colaUmaImagemComoFicheiro() throws {
        let pb = NSPasteboard(name: .init("teste-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let imagem = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true
        }
        pb.clearContents()
        pb.writeObjects([imagem])
        let urls = try #require(TextoPergunta.ficheirosParaColar(pb))
        #expect(urls.count == 1)
        #expect(urls.first?.pathExtension == "png")
        #expect(NSImage(contentsOf: try #require(urls.first)) != nil)
    }

    /// O ⌘V só chega ao `paste` se o campo disser que sabe ler o que está copiado: um campo de texto simples
    /// não lê imagens, e o "Colar" ficava desligado com uma captura de ecrã copiada.
    @Test func oColarFicaLigadoComUmaImagemCopiada() {
        let pb = NSPasteboard(name: .init("teste-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let imagem = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true
        }
        pb.clearContents()
        pb.writeObjects([imagem])
        #expect(pb.availableType(from: campo("").readablePasteboardTypes) != nil)
    }

    @Test func textoColaComoTexto() {
        let pb = NSPasteboard(name: .init("teste-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("só texto", forType: .string)
        #expect(TextoPergunta.ficheirosParaColar(pb) == nil)
    }
}
