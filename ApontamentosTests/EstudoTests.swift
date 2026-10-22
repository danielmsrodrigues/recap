import Foundation
import Testing
@testable import Apontamentos

struct EstudoTests {
    @Test func pesquisaIgnoraMaiusculasEAcentos() {
        #expect(Pesquisa.contem("La diagonalización de matrices", ["DIAGONALIZACION", "matrices"]))
        #expect(!Pesquisa.contem("La diagonalización de matrices", ["diagonalizacion", "vectores"]))
        let texto = "Hoy vamos a ver la diagonalización de una matriz cuadrada"
        let r = Pesquisa.realces(texto, ["diagonalizacion"])
        #expect(r.map { String(texto[$0]) } == ["diagonalización"])
    }

    @Test func trechoCortaAVoltaDaPalavra() {
        let longo = String(repeating: "relleno ", count: 30) + "autovalor" + String(repeating: " más", count: 30)
        let t = Pesquisa.trecho(longo, ["autovalor"])
        #expect(t.contains("autovalor"))
        #expect(t.hasPrefix("…") && t.hasSuffix("…"))
        #expect(t.count <= 142)
        #expect(Pesquisa.limparMarkdown("> **Definição — valor próprio.** $Av = \\lambda_{1} v$") == "Definição — valor próprio. Av = λ1 v")
        #expect(Pesquisa.termosParaRealcar("o polinómio característico de A é det(A - λI)", ["polinomio"])
                == ["polinómio característico de A é det", "polinómio"])
    }

    @Test func pesquisaEncontraNosFicheiros() async throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "pesquisa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        try Disco.escreverApontamentos("# Aula\n\n## Resumo\nValores próprios e diagonalização.\n", em: pasta)
        let t = Transcricao(idioma: "es", modelo: "x", duracao: 60, criadaEm: .now,
                            segmentos: [Segmento(inicio: 42, fim: 50, texto: "Calculamos los autovalores de la matriz.")])
        try Disco.encoder.encode(t).write(to: pasta.appending(path: Disco.transcricaoJSON))
        let aula = Pesquisa.AulaRef(pasta: pasta, titulo: "Tema 3", cadeira: "Álgebra", data: .now)

        let notas = await Pesquisa.procurar("diagonalizacao", em: [aula])
        #expect(notas.map(\.onde) == [.apontamentos])
        let fala = await Pesquisa.procurar("autovalores matriz", em: [aula])
        #expect(fala.map(\.onde) == [.transcricao(42)])
        #expect(await Pesquisa.procurar("tema 3", em: [aula]).map(\.onde) == [.titulo])
    }

    @Test func esqueletoTemResumoETitulos() {
        let md = """
        # Tema 3

        ## Resumo
        Diagonalização de matrizes.

        ## Valores próprios [02:10]
        Texto longo que não interessa.

        ### Exemplo: matriz 2×2 [10:00]
        Mais texto.
        """
        #expect(Estudo.esqueleto(md) == "## Resumo\nDiagonalização de matrizes.\n## Valores próprios [02:10]\n### Exemplo: matriz 2×2 [10:00]")
    }

    @Test func ligacoesDaRespostaDoClaude() throws {
        let resposta = """
        ```json
        {"ligacoes": [
          {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio"], "explicacao": "Vem da aula 1.", "momento": "[00:17]"},
          {"aula": "A9", "direcao": "anterior", "conceitos": [], "explicacao": "Id que não existe.", "momento": null},
          {"aula": "A2", "direcao": "seguinte", "conceitos": ["PDP⁻¹"], "explicacao": "Continua.", "momento": "não sei"},
          {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio", "gradiente"], "explicacao": "E mais.", "momento": "01:26"}
        ],
         "temas_comuns": [{"tema": "Gradiente", "aulas": ["A1", "A7"], "explicacao": "Nas duas."}]}
        ```
        """
        let l = try LigacoesAula.daResposta(resposta, aulas: ["A1": "Álgebra/aula1", "A2": "Álgebra/aula2"])
        #expect(l.ligacoes.map(\.aula) == ["Álgebra/aula1", "Álgebra/aula2"])
        #expect(l.ligacoes.map(\.momento) == ["00:17", nil])
        #expect(l.ligacoes.last?.direcao == .seguinte)
        #expect(l.ligacoes.first?.conceitos == ["valor próprio", "gradiente"])
        #expect(l.ligacoes.first?.explicacao == "Vem da aula 1. E mais.")
        #expect(l.temas.first?.aulas == ["Álgebra/aula1"])
        #expect(throws: ErroLigacoes.self) { try LigacoesAula.daResposta("Não há ligações.", aulas: [:]) }
    }

    @Test func ligacaoTrazAExplicacaoDoOutroLado() throws {
        let resposta = #"{"ligacoes": [{"aula": "A1", "direcao": "anterior", "conceitos": ["IVA"], "explicacao": "Aqui aprofunda-se.", "explicacao_outra": "Vista por alto; aprofundada na Aula 2."}]}"#
        let l = try LigacoesAula.daResposta(resposta, aulas: ["A1": "Empresas/aula1"])
        #expect(l.ligacoes.first?.explicacaoInversa == "Vista por alto; aprofundada na Aula 2.")
        // `ligacoes.json` de antes, sem a explicação do outro lado.
        let antigo = #"{"geradoEm": "2026-10-22T07:35:43Z", "ligacoes": [{"aula": "x", "direcao": "anterior", "conceitos": [], "explicacao": "y"}], "temas": []}"#
        #expect(try Disco.decoder.decode(LigacoesAula.self, from: Data(antigo.utf8)).ligacoes.first?.explicacaoInversa == nil)
    }

    @Test func ligacoesComOsCamposTraduzidos() throws {
        // Com os apontamentos em espanhol, o Claude chegou a escrever "explicacion" (e as duas, numa ligação).
        let resposta = ##"{"ligacoes": [{"aula": "A1", "direcao": "seguinte", "conceptos": ["IVA"], "explicacion": "x", "explicacao": "Se profundiza.", "puntos": [{"seccion": "#fiscalidad-basica", "seccao_outra": "#fiscalidad", "nota": "Más en la Clase 2.", "nota_otra": "Visto por encima en la Clase 1."}]}], "temas_comuns": [{"tema": "Tributos", "aulas": ["A1"], "explicacion": "En las dos clases."}]}"##
        let l = try LigacoesAula.daResposta(resposta, aulas: ["A1": "Empresas/aula2"])
        #expect(l.ligacoes.first?.explicacao == "Se profundiza.")
        #expect(l.ligacoes.first?.conceitos == ["IVA"])
        #expect(l.ligacoes.first?.pontos == [.init(seccao: "#fiscalidad-basica", seccaoOutra: "#fiscalidad", nota: "Más en la Clase 2.",
                                                   notaOutra: "Visto por encima en la Clase 1.")])
        #expect(l.temas.first?.explicacao == "En las dos clases.")
    }

    @Test @MainActor func ligacoesDasOutrasAulasAparecemDoOutroLado() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "ligacoes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let library = Library(raiz: raiz)
        let estudo = Estudo(library: library, definicoes: Definicoes(defaults: UserDefaults(suiteName: "ligacoes-\(UUID().uuidString)")!))
        let dia: TimeInterval = 86_400
        let p1 = try library.criarAula(cadeira: "Empresas", titulo: "Aula 1", data: Date(timeIntervalSince1970: dia), video: nil)
        let p2 = try library.criarAula(cadeira: "Empresas", titulo: "Aula 2", data: Date(timeIntervalSince1970: 8 * dia), video: nil)
        try Disco.escreverApontamentos("# Aula 1\n\n## Resumo\nEmpresa e fiscalidade por alto.\n", em: p1)
        try Disco.escreverApontamentos("# Aula 2\n\n## Resumo\nIVA e IRPF.\n\n## Fiscalidade [27:26]\nIVA.\n", em: p2)
        library.recarregar()
        let aula1 = try #require(library.aula(em: p1))
        #expect(estudo.ligacoes(aula1) == nil)

        let caminho1 = Estudo.caminhoRelativo(p1, raiz: raiz)
        try Disco.escreverLigacoes(LigacoesAula(ligacoes: [
            .init(aula: caminho1, direcao: .anterior, conceitos: ["fiscalidade"], explicacao: "A Aula 1 apresentou-a; aqui aprofunda-se.",
                  momento: "27:26", explicacaoInversa: "Aqui vista por alto; a Aula 2 aprofunda-a."),
        ], temas: []), em: p2)
        let vistas = try #require(estudo.ligacoes(aula1)).ligacoes
        #expect(vistas.count == 1)
        #expect(vistas.first?.aula == Estudo.caminhoRelativo(p2, raiz: raiz))
        #expect(vistas.first?.direcao == .seguinte)
        #expect(vistas.first?.explicacao == "Aqui vista por alto; a Aula 2 aprofunda-a.")
        #expect(vistas.first?.momento == nil)

        // Um link de uma resposta para uma secção da outra aula leva a essa aula.
        let prefixo = Estudo.prefixoLink(p2)
        let d = estudo.destino(LigacaoSeccao(ancora: "#\(prefixo)/fiscalidade", texto: "Fiscalidade"), aPartirDe: aula1)
        #expect(d.pasta.mesmoCaminho(p2))
        #expect(d.seccao?.ancora == "fiscalidade")
        #expect(estudo.destino(LigacaoSeccao(ancora: "resumo", texto: ""), aPartirDe: aula1).pasta.mesmoCaminho(p1))
    }

    @Test func notasDasLigacoesPoemSeETiramSe() {
        let md = "# Clase 1\n\n## Resumen\nEmpresa.\n\n## Fiscalidad [12:00]\n![Slide 4](slides-pdf/pagina-04.jpg)\nSe habló por encima.\n\n## Áreas\nProducción.\n"
        let notas = [
            NotasLigacoes.Nota(seccao: "#fiscalidad", texto: "Se profundiza en la Clase 2: IVA e IRPF.", link: "#aula-2/fiscalidad", tituloLink: "Fiscalidad"),
            NotasLigacoes.Nota(seccao: "areas", texto: "Más en la Clase 2.", link: "#aula-2/areas", tituloLink: "Áreas"),
            NotasLigacoes.Nota(seccao: "nao-existe", texto: "Fica de fora.", link: "#x/y", tituloLink: "Y"),
        ]
        let com = NotasLigacoes.por(notas, em: md)
        #expect(com.contains("![Slide 4](slides-pdf/pagina-04.jpg)\n\n> 🔗 Se profundiza en la Clase 2: IVA e IRPF. → [Fiscalidad](#aula-2/fiscalidad)\n\nSe habló por encima."))
        #expect(com.contains("## Áreas\n\n> 🔗 Más en la Clase 2. → [Áreas](#aula-2/areas)\n\nProducción."))
        #expect(!com.contains("Fica de fora"))
        // Pôr de novo não acumula; tirar deixa só o que era dos apontamentos.
        #expect(NotasLigacoes.por(notas, em: com) == com)
        #expect(!NotasLigacoes.tirar(com).contains("🔗"))
        #expect(NotasLigacoes.por([], em: com) == NotasLigacoes.tirar(com))
        // As notas não mudam a assinatura (não fazem as ligações parecerem desatualizadas); o resto sim.
        #expect(NotasLigacoes.assinatura(com) == NotasLigacoes.assinatura(md))
        #expect(NotasLigacoes.assinatura(md + "\nMás.") != NotasLigacoes.assinatura(md))
    }

    @Test @MainActor func notasVaoParaOsApontamentosDasDuasAulas() throws {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "notas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: raiz) }
        let library = Library(raiz: raiz)
        let estudo = Estudo(library: library, definicoes: Definicoes(defaults: UserDefaults(suiteName: "notas-\(UUID().uuidString)")!))
        let dia: TimeInterval = 86_400
        let p1 = try library.criarAula(cadeira: "Empresas", titulo: "Aula 1", data: Date(timeIntervalSince1970: dia), video: nil)
        let p2 = try library.criarAula(cadeira: "Empresas", titulo: "Aula 2", data: Date(timeIntervalSince1970: 8 * dia), video: nil)
        let md1 = "# Aula 1\n\n## Resumo\nEmpresa.\n\n## Marco legal\nFiscalidade por alto.\n"
        let md2 = "# Aula 2\n\n## Resumo\nIVA.\n\n## Fiscalidade [27:26]\nIVA e IRPF.\n"
        try Disco.escreverApontamentos(md1, em: p1)
        try Disco.escreverApontamentos(md2, em: p2)
        library.recarregar()
        let (c1, c2) = (Estudo.caminhoRelativo(p1, raiz: raiz), Estudo.caminhoRelativo(p2, raiz: raiz))
        var ligacoes = LigacoesAula(ligacoes: [
            .init(aula: c1, direcao: .anterior, conceitos: ["fiscalidade"], explicacao: "x", momento: nil, explicacaoInversa: "y",
                  pontos: [.init(seccao: "#fiscalidade", seccaoOutra: "#marco-legal", nota: "Introduzida por alto na Aula 1.",
                                 notaOutra: "Aprofundada na Aula 2: IVA e IRPF.")]),
        ], temas: [])
        ligacoes.assinaturas = [c1: NotasLigacoes.assinatura(md1), c2: NotasLigacoes.assinatura(md2)]
        try Disco.escreverLigacoes(ligacoes, em: p2)
        // Ligações de antes das notas sobre onde resumir: refazem-se uma vez.
        #expect(estudo.ligacoesDesatualizadas(try #require(library.aula(em: p2))))
        ligacoes.formato = LigacoesAula.formatoAtual
        try Disco.escreverLigacoes(ligacoes, em: p2)

        estudo.aplicarNotas("Empresas")
        let novo1 = try #require(Disco.lerApontamentos(p1))
        let novo2 = try #require(Disco.lerApontamentos(p2))
        #expect(novo1.contains("## Marco legal\n\n> 🔗 Aprofundada na Aula 2: IVA e IRPF. → [Fiscalidade](#\(Estudo.prefixoLink(p2))/fiscalidade)"))
        #expect(novo2.contains("## Fiscalidade [27:26]\n\n> 🔗 Introduzida por alto na Aula 1. → [Marco legal](#\(Estudo.prefixoLink(p1))/marco-legal)"))
        #expect(estudo.versaoApontamentos == 1)
        // Pôr as notas não torna as ligações da Aula 2 desatualizadas, e aplicar de novo não escreve nada.
        #expect(!estudo.ligacoesDesatualizadas(try #require(library.aula(em: p2))))
        estudo.aplicarNotas("Empresas")
        #expect(estudo.versaoApontamentos == 1)
        // Apontamentos da Aula 1 refeitos: desatualizadas.
        try Disco.escreverApontamentos(md1 + "\n## Novo\nMais.\n", em: p1)
        #expect(estudo.ligacoesDesatualizadas(try #require(library.aula(em: p2))))
    }

    @Test func outraAulaNoChatSemTemposNemImagens() {
        let md = "# Aula 2\n\n## Resumo\nIVA e IRPF.\n\n## Fiscalidad [27:26]\n![Slide 4](slides-pdf/pagina-04.jpg)\nEl IVA [35:41] lo paga el consumidor.\n"
        let completa = Estudo.aulaParaPerguntas(titulo: "Aula 2", data: .now, anterior: false, prefixo: "2026-10-21-aula-2", apontamentos: md, completa: true)
        #expect(completa.contains("- [Fiscalidad](#2026-10-21-aula-2/fiscalidad)"))
        #expect(completa.contains("El IVA lo paga el consumidor."))
        #expect(!completa.contains("[27:26]") && !completa.contains("pagina-04"))
        #expect(completa.contains("seguinte>"))
        let resumo = Estudo.aulaParaPerguntas(titulo: "Aula 2", data: .now, anterior: true, prefixo: "x", apontamentos: md, completa: false)
        #expect(resumo.contains("<resumo>") && !resumo.contains("consumidor"))
    }

    @Test func perguntasGuardadas() throws {
        let pasta = FileManager.default.temporaryDirectory.appending(path: "perguntas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        #expect(Disco.lerPerguntas(pasta).isEmpty)
        try Disco.escreverPerguntas([PerguntaAula(pergunta: "O que é $\\lambda$?", resposta: "Um valor próprio.")], em: pasta)
        #expect(Disco.lerPerguntas(pasta).map(\.pergunta) == ["O que é $\\lambda$?"])
        try Disco.escreverPerguntas([], em: pasta)
        #expect(!FileManager.default.fileExists(atPath: pasta.appending(path: Disco.perguntasJSON).path))
    }
}

struct AtualizadorTests {
    @Test func comparaVersoesNumeroANumero() {
        #expect(Atualizador.maisRecente("1.10", que: "1.9"))
        #expect(Atualizador.maisRecente("2.0", que: "1.9.9"))
        #expect(Atualizador.maisRecente("1.2.1", que: "1.2"))
        #expect(!Atualizador.maisRecente("1.2", que: "1.2"))
        #expect(!Atualizador.maisRecente("1.2", que: "1.2.0"))
        #expect(!Atualizador.maisRecente("1.1", que: "1.2"))
    }

    /// Só aceita uma app assinada pelo mesmo autor desta (os testes correm dentro do Recap).
    @Test func soAceitaAMesmaAssinatura() throws {
        #expect(throws: Atualizador.Erro.self) { try Atualizador.verificarAssinatura(URL(fileURLWithPath: "/System/Applications/Calculator.app")) }
        let instalada = URL(fileURLWithPath: "/Applications/Recap.app")
        if FileManager.default.fileExists(atPath: instalada.path) {
            try Atualizador.verificarAssinatura(instalada)
        }
    }
}
