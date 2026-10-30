import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import Apontamentos

/// Ficheiros juntados a uma pergunta no chat (`Anexos`): o que se aceita, como se guardam e como vão para o Claude.
@MainActor
struct AnexosTests {
    private func pastaTemporaria() throws -> URL {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "anexos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        return pasta
    }

    /// Um ficheiro Office (zip de XML) com estas entradas.
    private func zip(_ entradas: [String: String], em url: URL) throws {
        let arquivo = try Archive(url: url, accessMode: .create)
        for (caminho, xml) in entradas.sorted(by: { $0.key < $1.key }) {
            let dados = Data(xml.utf8)
            try arquivo.addEntry(with: caminho, type: .file, uncompressedSize: Int64(dados.count)) { posicao, tamanho in
                dados.subdata(in: Int(posicao)..<Int(posicao) + tamanho)
            }
        }
    }

    private func png(largura: Int, altura: Int, em url: URL) throws {
        let ctx = try #require(CGContext(data: nil, width: largura, height: altura, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: largura, height: altura))
        let destino = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destino, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destino))
    }

    @Test func imagensTemMiniaturaPequenaOsOutrosNao() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        try png(largura: 3000, altura: 1500, em: pasta.appending(path: "Quadro.png"))
        let nome = try Anexos.juntar(pasta.appending(path: "Quadro.png"), em: pasta)
        try "a;b".write(to: pasta.appending(path: "dados.csv"), atomically: true, encoding: .utf8)
        let csv = try Anexos.juntar(pasta.appending(path: "dados.csv"), em: pasta)

        let miniatura = try #require(Anexos.miniatura(nome, em: pasta, lado: 128))
        #expect(miniatura.width == 128 && miniatura.height == 64)
        #expect(Anexos.miniatura(csv, em: pasta, lado: 128) == nil)
        #expect(Anexos.miniatura("não existe.jpg", em: pasta, lado: 128) == nil)
    }

    @Test func aceitaOsTiposPelaExtensao() {
        #expect(Anexos.tipo("Notas.XLSX") == .folha)
        #expect(Anexos.tipo("foto.heic") == .imagem)
        #expect(Anexos.tipo("Captura de ecrã.png") == .imagem)
        #expect(Anexos.tipo("tema 3.pdf") == .pdf)
        #expect(Anexos.tipo("dados.csv") == .texto)
        #expect(Anexos.tipo("exercicio.py") == .texto)
        #expect(Anexos.tipo("relatorio.docx") == .documento)
        #expect(Anexos.tipo("aula.pptx") == .apresentacao)
        #expect(Anexos.tipo("programa.exe") == nil)
        #expect(Anexos.tipo("sem extensão") == nil)
    }

    @Test func imagemFicaEmJPEGComNoMaximo2000Pixeis() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appending(path: "Quadro.png")
        try png(largura: 3000, altura: 1500, em: origem)

        let nome = try Anexos.juntar(origem, em: pasta)
        #expect(nome == "Quadro.jpg")
        let fonte = try #require(CGImageSourceCreateWithURL(Anexos.url(nome, em: pasta) as CFURL, nil))
        #expect(CGImageSourceGetType(fonte) as String? == UTType.jpeg.identifier)
        let imagem = try #require(CGImageSourceCreateImageAtIndex(fonte, 0, nil))
        #expect(imagem.width == 2000 && imagem.height == 1000)
    }

    @Test func nomeRepetidoGanhaUmNumero() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appending(path: "dados.csv")
        try "a,b\n1,2\n".write(to: origem, atomically: true, encoding: .utf8)
        #expect(try Anexos.juntar(origem, em: pasta) == "dados.csv")
        #expect(try Anexos.juntar(origem, em: pasta) == "dados 2.csv")
        #expect(FileManager.default.fileExists(atPath: Anexos.url("dados 2.csv", em: pasta).path))
    }

    @Test func recusaUmTipoQueNaoSabeLer() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appending(path: "programa.exe")
        try Data([0, 1, 2]).write(to: origem)
        #expect(throws: (any Error).self) { try Anexos.juntar(origem, em: pasta) }
    }

    @Test func folhaDeExcelPassaACSVPorFolha() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let url = pasta.appending(path: "notas.xlsx")
        try zip([
            "xl/workbook.xml": """
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                <sheets><sheet name="Notas" sheetId="1" r:id="rId1"/><sheet name="Médias" sheetId="2" r:id="rId2"/></sheets></workbook>
                """,
            "xl/_rels/workbook.xml.rels": """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
                <Relationship Id="rId2" Type="worksheet" Target="/xl/worksheets/sheet2.xml"/></Relationships>
                """,
            "xl/sharedStrings.xml": """
                <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Nome</t></si><si><t>Nota</t></si>
                <si><r><t>Ana </t></r><r><t>Sousa</t></r></si><si><t>Rui, o "Ruizinho"</t></si></sst>
                """,
            "xl/worksheets/sheet1.xml": """
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
                <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
                <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>17.5</v></c></row>
                <row r="4"><c r="A4" t="s"><v>3</v></c><c r="C4" t="inlineStr"><is><t>falta</t></is></c></row>
                </sheetData></worksheet>
                """,
            "xl/worksheets/sheet2.xml": """
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
                <row r="1"><c r="A1" t="str"><f>AVERAGE(Notas!B2:B4)</f><v>17.5</v></c><c r="B1" t="b"><v>1</v></c></row>
                </sheetData></worksheet>
                """,
        ], em: url)

        #expect(try Anexos.texto(folha: Data(contentsOf: url)) == #"""
            ## Folha "Notas"
            Nome,Nota
            Ana Sousa,17.5
            "Rui, o ""Ruizinho""",,falta

            ## Folha "Médias"
            17.5,TRUE
            """#)
    }

    @Test func documentoDeWordPassaATexto() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let url = pasta.appending(path: "enunciado.docx")
        try zip(["word/document.xml": """
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
            <w:p><w:r><w:t>Exercício </w:t></w:r><w:r><w:t>1</w:t></w:r></w:p>
            <w:p><w:r><w:t>Calcula</w:t></w:r><w:r><w:tab/><w:t>a média.</w:t></w:r></w:p>
            </w:body></w:document>
            """], em: url)
        #expect(try Anexos.texto(documento: Data(contentsOf: url)) == "Exercício 1\nCalcula\ta média.")
    }

    @Test func apresentacaoPassaATextoPorOrdemDosSlides() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let url = pasta.appending(path: "tema.pptx")
        func slide(_ linhas: String...) -> String {
            #"<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree>"#
                + linhas.map { "<p:sp><p:txBody><a:p><a:r><a:t>\($0)</a:t></a:r></a:p></p:txBody></p:sp>" }.joined()
                + "</p:spTree></p:cSld></p:sld>"
        }
        try zip(["ppt/slides/slide1.xml": slide("Regressão"), "ppt/slides/slide2.xml": slide("Mínimos quadrados", "β = (XᵀX)⁻¹Xᵀy"),
                 "ppt/slides/slide10.xml": slide("Resumo")], em: url)
        #expect(try Anexos.texto(apresentacao: Data(contentsOf: url)) == """
            ## Slide 1
            Regressão

            ## Slide 2
            Mínimos quadrados
            β = (XᵀX)⁻¹Xᵀy

            ## Slide 10
            Resumo
            """)
    }

    @Test func cadaTipoVaiNoBlocoCerto() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let csv = pasta.appending(path: "dados.csv"), pdf = pasta.appending(path: "Tema 1.pdf"), imagem = pasta.appending(path: "quadro.png")
        try "x,y\n1,2".write(to: csv, atomically: true, encoding: .utf8)
        try Data("%PDF-1.4 falso".utf8).write(to: pdf)
        try png(largura: 40, altura: 20, em: imagem)
        let nomes = try [csv, pdf, imagem].map { try Anexos.juntar($0, em: pasta) }

        let blocos = Anexos.blocos(nomes, em: pasta)
        #expect(blocos.count == 5)
        #expect(blocos[0] == .texto("Ficheiro \"dados.csv\":\n\n<ficheiro>\nx,y\n1,2\n</ficheiro>"))
        #expect(blocos[1] == .texto("Ficheiro \"Tema 1.pdf\":"))
        #expect(blocos[2] == .documentoPDF(base64: Data("%PDF-1.4 falso".utf8).base64EncodedString()))
        #expect(blocos[3] == .texto("Ficheiro \"quadro.jpg\":"))
        guard case .imagem(let tipo, _) = blocos[4] else { Issue.record("Esperava uma imagem: \(blocos[4])"); return }
        #expect(tipo == "image/jpeg")
    }

    @Test func textoMuitoGrandeECortado() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appending(path: "log.txt")
        try String(repeating: "a", count: Anexos.maximoCaracteres + 50).write(to: origem, atomically: true, encoding: .utf8)
        let blocos = Anexos.blocos([try Anexos.juntar(origem, em: pasta)], em: pasta)
        guard case .texto(let t) = blocos.first else { Issue.record("Esperava texto"); return }
        #expect(t.contains("(cortado: o ficheiro tem mais"))
        #expect(t.count < Anexos.maximoCaracteres + 200)
    }

    @Test func dasPerguntasAnterioresVaoOsMaisRecentesQueCabem() {
        // Do mais recente para o mais antigo; um que não cabe fica de fora, mas os seguintes mais pequenos ainda entram.
        let escolhidos = Anexos.queCabem([("c.png", 600), ("b.pdf", 900), ("a.csv", 300)], bytes: 1000)
        #expect(escolhidos == ["c.png", "a.csv"])
        #expect(Anexos.queCabem([("a.csv", 10)], bytes: 0).isEmpty)
    }

    @Test func soComFicheirosPedeParaOsExplicar() {
        #expect(Estudo.pergunta(" ", citacao: nil, anexos: ["quadro.jpg"]) == Estudo.perguntaSobreFicheiros)
        #expect(Estudo.pergunta("E isto?", citacao: nil, anexos: ["quadro.jpg"]) == "E isto?")
        #expect(Estudo.pergunta(" ", citacao: nil, anexos: []) == nil)
    }

    @Test func osPDFsDaAulaTiramEspacoAosFicheiros() {
        // Os desta pergunta vão sempre; dos anteriores, os mais recentes que ainda cabem.
        let r = Anexos.paraOPedido(atuais: [("a.png", 300)], anteriores: [("b.pdf", 500), ("c.csv", 100)], espaco: 450)
        #expect(r?.atuais == ["a.png"])
        #expect(r?.anteriores == ["c.csv"])
        // Nunca mais do que o máximo de uma pergunta, mesmo com espaço no pedido.
        let grande = Anexos.tamanhoMaximo
        #expect(Anexos.paraOPedido(atuais: [("a.png", grande - 10)], anteriores: [("b.png", 20)], espaco: 3 * grande)?.anteriores == [])
        // Os desta pergunta já não cabem com os PDFs da aula: não se envia.
        #expect(Anexos.paraOPedido(atuais: [("a.png", 300)], anteriores: [], espaco: 200) == nil)
    }

    @Test func nomesComCaminhoNaoSaemDaPastaDaAula() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let pasta = raiz.appending(path: "aula")
        try FileManager.default.createDirectory(at: pasta.appending(path: Anexos.pasta), withIntermediateDirectories: true)
        try "segredo".write(to: raiz.appending(path: "fora.txt"), atomically: true, encoding: .utf8)
        #expect(Anexos.nomeSeguro("../../fora.txt") == nil)
        #expect(Anexos.nomeSeguro("sub/x.txt") == nil)
        #expect(Anexos.nomeSeguro("..") == nil)
        #expect(Anexos.nomeSeguro("notas 2.csv") == "notas 2.csv")
        #expect(Anexos.blocos(["../../fora.txt"], em: pasta) == [.texto("Ficheiro \"../../fora.txt\": não foi possível lê-lo.")])
    }

    @Test func ficheirosSemPerguntaSaoApagadosDepoisDeUmDia() throws {
        let pasta = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: pasta) }
        let origem = pasta.appending(path: "x.csv")
        try "1".write(to: origem, atomically: true, encoding: .utf8)
        let usado = try Anexos.juntar(origem, em: pasta), velho = try Anexos.juntar(origem, em: pasta), novo = try Anexos.juntar(origem, em: pasta)
        for nome in [usado, velho] {
            try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-2 * 86_400)],
                                                  ofItemAtPath: Anexos.url(nome, em: pasta).path)
        }
        Anexos.limparOrfaos(em: pasta, usados: [usado])
        let restam = try FileManager.default.contentsOfDirectory(atPath: pasta.appending(path: Anexos.pasta).path).sorted()
        // O novo pode estar à espera da pergunta.
        #expect(restam == [usado, novo].sorted())
    }

    @Test func seAPerguntaFalhaOsFicheirosVoltamAoCampo() throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "anexos-\(UUID().uuidString)")!)
        definicoes.motor = .claudeCode
        definicoes.caminhoClaude = raiz.appending(path: "nao-existe").path
        let library = Library(raiz: raiz)
        let pasta = try library.criarAula(cadeira: "Estatística", titulo: "Aula 3", data: .now, video: nil)
        try Disco.escreverTranscricao(Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                                                  segmentos: [Segmento(inicio: 5, fim: 9, texto: "La media.")]), em: pasta)
        library.recarregar()
        let aula = try #require(library.aula(em: pasta))
        let estudo = Estudo(library: library, definicoes: definicoes)

        estudo.perguntar("?", sobre: aula, anexos: ["quadro.jpg"])
        #expect(estudo.erro(aula, .pergunta) != nil)
        #expect(estudo.anexosPorEnviar(aula) == ["quadro.jpg"])
        estudo.tirarAnexosPorEnviar(aula)
        #expect(estudo.anexosPorEnviar(aula).isEmpty)
    }

    @Test func perguntasAntigasSemAnexosContinuamALer() throws {
        let json = #"[{"id":"7E1A0D7C-4B0B-4E6B-9E0B-8F1C2B3A4D5E","pergunta":"?","resposta":"!","data":"2026-10-20T10:00:00Z"}]"#
        let perguntas = try Disco.decoder.decode([PerguntaAula].self, from: Data(json.utf8))
        #expect(perguntas.first?.anexos == nil)
    }

    @Test func aPerguntaLevaOsFicheirosAoClaude() async throws {
        let raiz = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let definicoes = Definicoes(defaults: UserDefaults(suiteName: "anexos-\(UUID().uuidString)")!)
        definicoes.motor = .claudeCode
        let entrada = raiz.appending(path: "entrada.json")
        let script = raiz.appending(path: "claude")
        let linhas = [
            #"{"type":"stream_event","event":{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":10}}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Vi o ficheiro."}}}"#,
            #"{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}}"#,
            #"{"type":"result","is_error":false,"total_cost_usd":0.001}"#,
        ]
        try ("#!/bin/sh\ncat > '\(entrada.path)'\n" + linhas.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n") + "\n")
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        definicoes.caminhoClaude = script.path
        let library = Library(raiz: raiz)
        let pasta = try library.criarAula(cadeira: "Estatística", titulo: "Aula 2", data: .now, video: nil)
        try Disco.escreverTranscricao(Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                                                  segmentos: [Segmento(inicio: 5, fim: 9, texto: "La media.")]), em: pasta)
        library.recarregar()
        let aula = try #require(library.aula(em: pasta))
        let estudo = Estudo(library: library, definicoes: definicoes)
        let csv = raiz.appending(path: "notas.csv")
        try "aluno,nota\nAna,17".write(to: csv, atomically: true, encoding: .utf8)
        let nome = try Anexos.juntar(csv, em: pasta)

        estudo.perguntar("Qual é a média?", sobre: aula, anexos: [nome])
        for _ in 0..<40 where estudo.emCurso(aula, .pergunta) != nil { try await Task.sleep(for: .milliseconds(250)) }

        #expect(estudo.erro(aula, .pergunta) == nil)
        let pedido = try String(contentsOf: entrada, encoding: .utf8)
        #expect(pedido.contains(#"Ficheiro \"notas.csv\""#))
        #expect(pedido.contains("aluno,nota"))
        let guardada = try #require(Disco.lerPerguntas(pasta).last)
        #expect(guardada.anexos == ["notas.csv"])
        #expect(guardada.resposta == "Vi o ficheiro.")
    }

    @Test func pedidoDoIPhoneLevaOsFicheiros() throws {
        let pedido = PedidoMac(tipo: .pergunta, aula: "x", pergunta: "?", anexos: ["quadro.jpg"])
        let lido = try Disco.decoder.decode(PedidoMac.self, from: Disco.encoder.encode(pedido))
        #expect(lido.anexos == ["quadro.jpg"])
    }
}
