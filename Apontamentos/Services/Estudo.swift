import Foundation
import Observation

/// Uma pergunta feita sobre uma aula e a resposta do Claude (`perguntas.json`).
struct PerguntaAula: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var pergunta: String
    var resposta: String
    var data = Date.now
    /// O trecho selecionado sobre o qual se perguntou.
    var citacao: CitacaoPergunta?
    /// Ficheiros juntados à pergunta, em `anexos-chat/` (ver `Anexos`).
    var anexos: [String]?
}

extension PerguntaAula {
    /// Com isto o Claude começa uma resposta pedida em PDF (`Estudo.sistemaPerguntas`).
    static let marcaPDF = "<!-- pdf -->"

    /// O documento de uma resposta pedida em PDF, sem a marca; nil numa resposta normal.
    var documentoPDF: String? {
        let texto = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.hasPrefix(Self.marcaPDF) else { return nil }
        return texto.dropFirst(Self.marcaPDF.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Um trecho selecionado nos apontamentos ou na transcrição, para perguntar sobre ele.
struct CitacaoPergunta: Codable, Hashable, Sendable {
    enum Origem: String, Codable, Sendable { case apontamentos, transcricao }

    /// Nos apontamentos em Markdown (com o LaTeX); na transcrição tal como foi dito, em espanhol.
    var texto: String
    var origem: Origem
    /// Onde começa na aula, em segundos (só na transcrição).
    var inicio: Double?

    /// De onde vem, para mostrar com o trecho.
    var legenda: String {
        switch origem {
        case .apontamentos: "Apontamentos"
        case .transcricao: "Transcrição" + (inicio.map { " · [\(Timestamp.format($0))]" } ?? "")
        }
    }

    /// Um trecho maior não acrescenta nada (a aula toda já vai para o Claude) e repetia-se nas perguntas seguintes.
    static let limite = 1500

    /// O mesmo trecho com no máximo `maximo` caracteres (cortado numa palavra, com "…").
    func cortado(_ maximo: Int = limite) -> CitacaoPergunta {
        guard texto.count > maximo else { return self }
        var c = self
        let inicio = texto.prefix(maximo)
        c.texto = String(inicio.lastIndex(of: " ").map { inicio[..<$0] } ?? inicio) + "…"
        return c
    }

    /// O trecho para ler (sem marcadores de Markdown e com o LaTeX simplificado).
    var textoLimpo: String {
        texto.components(separatedBy: .newlines).map(Pesquisa.limparMarkdown)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
    }
}


/// Como uma aula se liga às outras da cadeira (`ligacoes.json`), para a vista visual.
struct LigacoesAula: Codable, Equatable, Sendable {
    enum Direcao: String, Codable, Sendable { case anterior, seguinte }

    struct Ligacao: Codable, Hashable, Sendable {
        /// Pasta da outra aula, relativa à raiz.
        var aula: String
        var direcao: Direcao
        var conceitos: [String]
        var explicacao: String
        /// `mm:ss` da aula atual onde a ligação aparece.
        var momento: String?
        /// A mesma ligação contada do lado da outra aula, para a mostrar lá (`Estudo.ligacoes`).
        var explicacaoInversa: String?
        /// Onde a ligação aparece nos apontamentos das duas aulas, com a nota a pôr em cada um (`NotasLigacoes`).
        var pontos: [Ponto]?
    }

    /// Uma secção desta aula ligada a uma secção da outra ("por alto aqui, aprofundado lá").
    struct Ponto: Codable, Hashable, Sendable {
        /// Âncora da secção nos apontamentos desta aula e na outra.
        var seccao: String?
        var seccaoOutra: String?
        /// A nota para os apontamentos desta aula, e a que vai para os da outra.
        var nota: String
        var notaOutra: String?
    }

    struct Tema: Codable, Hashable, Sendable {
        var tema: String
        /// Pastas das aulas onde o tema também aparece, relativas à raiz.
        var aulas: [String]
        var explicacao: String
    }

    var ligacoes: [Ligacao]
    var temas: [Tema]
    var geradoEm = Date.now
    /// Os apontamentos de cada aula (desta e das outras) quando as ligações se geraram (`NotasLigacoes.assinatura`).
    var assinaturas: [String: String]?
    /// Como foram pedidas as notas: ligações de um formato anterior refazem-se uma vez (`Estudo.ligacoesDesatualizadas`).
    var formato: Int?
    /// 2: as notas dizem onde resumir ("não resumas aqui, explica-se melhor na Aula 2").
    static let formatoAtual = 2

    /// O JSON que o Claude devolve, com as aulas identificadas por `A1`, `A2`…
    private struct Resposta: Decodable {
        struct L: Decodable {
            var aula: String; var direcao: String; var conceitos: [String]?; var explicacao: String; var momento: String?
            var explicacao_outra: String?
            var pontos: [P]?
        }
        struct P: Decodable { var seccao: String?; var seccao_outra: String?; var nota: String?; var nota_outra: String? }
        struct T: Decodable { var tema: String; var aulas: [String]?; var explicacao: String }
        var ligacoes: [L]?
        var temas_comuns: [T]?
    }

    /// Com os apontamentos noutra língua, o Claude às vezes traduz também os nomes dos campos ("explicacion",
    /// "conceptos"…): voltam aos do formato pedido, sem tirar o lugar a um campo certo que também venha.
    private static let chaves: [String: [String]] = [
        "aula": ["clase", "lecture", "class"],
        "direcao": ["direccion", "dirección", "direção", "direction"],
        "conceitos": ["conceptos", "concepts"],
        "explicacao": ["explicacion", "explicación", "explicação", "explanation"],
        "explicacao_outra": ["explicacion_otra", "explicación_otra", "explicação_outra", "explanation_other", "other_explanation"],
        "pontos": ["puntos", "points"],
        "seccao": ["seccion", "sección", "secção", "section"],
        "seccao_outra": ["seccion_otra", "sección_otra", "secção_outra", "section_other", "other_section"],
        "nota_outra": ["nota_otra", "note_other", "other_note"],
        "temas_comuns": ["temas_comunes", "common_themes", "common_topics"],
        "tema": ["theme", "topic"],
        "aulas": ["clases", "lectures", "classes"],
        "ligacoes": ["ligaciones", "conexiones", "enlaces", "links", "connections"],
    ]

    private static func normalizarChaves(_ json: Any) -> Any {
        if let lista = json as? [Any] { return lista.map(normalizarChaves) }
        guard var objeto = json as? [String: Any] else { return json }
        for (certa, variantes) in chaves where objeto[certa] == nil {
            if let v = variantes.first(where: { objeto[$0] != nil }) { objeto[certa] = objeto[v] }
        }
        return objeto.mapValues(normalizarChaves)
    }

    /// Lê a resposta do Claude (tolera texto ou ``` à volta do JSON) e troca os ids pelas pastas.
    static func daResposta(_ texto: String, aulas: [String: String]) throws -> LigacoesAula {
        guard let a = texto.firstIndex(of: "{"), let b = texto.lastIndex(of: "}"), a < b,
              let json = try? JSONSerialization.jsonObject(with: Data(texto[a...b].utf8)),
              let dados = try? JSONSerialization.data(withJSONObject: normalizarChaves(json)),
              let r = try? JSONDecoder().decode(Resposta.self, from: dados)
        else { throw ErroLigacoes.formato }
        var ligacoes: [Ligacao] = []
        for l in r.ligacoes ?? [] {
            guard let pasta = aulas[l.aula], let d = Direcao(rawValue: l.direcao) else { continue }
            let limpo = l.momento?.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            let momento = limpo.flatMap { Timestamp.parse($0) != nil ? $0 : nil }
            let pontos = (l.pontos ?? []).compactMap { p in
                p.nota.map { Ponto(seccao: p.seccao, seccaoOutra: p.seccao_outra, nota: $0, notaOutra: p.nota_outra) }
            }
            // Uma só entrada por aula e direção (o Claude às vezes divide-a em duas).
            if let i = ligacoes.firstIndex(where: { $0.aula == pasta && $0.direcao == d }) {
                ligacoes[i].conceitos += (l.conceitos ?? []).filter { !ligacoes[i].conceitos.contains($0) }
                ligacoes[i].explicacao += " " + l.explicacao
                ligacoes[i].momento = ligacoes[i].momento ?? momento
                if let outra = l.explicacao_outra { ligacoes[i].explicacaoInversa = [ligacoes[i].explicacaoInversa, outra].compactMap { $0 }.joined(separator: " ") }
                if !pontos.isEmpty { ligacoes[i].pontos = (ligacoes[i].pontos ?? []) + pontos }
            } else {
                ligacoes.append(Ligacao(aula: pasta, direcao: d, conceitos: l.conceitos ?? [], explicacao: l.explicacao, momento: momento,
                                        explicacaoInversa: l.explicacao_outra, pontos: pontos.isEmpty ? nil : pontos))
            }
        }
        let temas = (r.temas_comuns ?? []).map { Tema(tema: $0.tema, aulas: ($0.aulas ?? []).compactMap { aulas[$0] }, explicacao: $0.explicacao) }
        return LigacoesAula(ligacoes: ligacoes, temas: temas)
    }
}

enum ErroLigacoes: LocalizedError {
    case formato
    var errorDescription: String? { "O Claude não devolveu as ligações no formato esperado. Tenta outra vez." }
}

extension Disco {
    static let perguntasJSON = "perguntas.json"
    static let exerciciosMD = "exercicios.md"
    static let ligacoesJSON = "ligacoes.json"

    static func lerLigacoes(_ pasta: URL) -> LigacoesAula? {
        guard let dados = try? lerDados(pasta.appending(path: ligacoesJSON)) else { return nil }
        return try? decoder.decode(LigacoesAula.self, from: dados)
    }

    static func escreverLigacoes(_ l: LigacoesAula, em pasta: URL) throws {
        try gravar(encoder.encode(l), em: pasta.appending(path: ligacoesJSON))
    }

    static func lerPerguntas(_ pasta: URL) -> [PerguntaAula] {
        guard let dados = try? lerDados(pasta.appending(path: perguntasJSON)) else { return [] }
        return (try? decoder.decode([PerguntaAula].self, from: dados)) ?? []
    }

    static func escreverPerguntas(_ perguntas: [PerguntaAula], em pasta: URL) throws {
        let url = pasta.appending(path: perguntasJSON)
        if perguntas.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try gravar(encoder.encode(perguntas), em: url)
    }

    /// As perguntas da aula, ou nil se o ficheiro existe mas não se lê (ainda a chegar do iCloud, estragado).
    /// Sem ficheiro, não há perguntas: [].
    static func lerPerguntasSePossivel(_ pasta: URL) -> [PerguntaAula]? {
        lerListaPerguntas(pasta.appending(path: perguntasJSON))
    }

    /// Junta uma resposta às anteriores. Se o ficheiro existe mas não se lê, lança um erro em vez de o substituir
    /// só pela resposta nova (e o iCloud levar isso para os outros dispositivos).
    static func juntarPergunta(_ nova: PerguntaAula, em pasta: URL) throws {
        guard let anteriores = lerPerguntasSePossivel(pasta) else { throw ErroPerguntas.porLer }
        try escreverPerguntas(anteriores + [nova], em: pasta)
    }

    static func lerListaPerguntas(_ url: URL) -> [PerguntaAula]? {
        guard FileManager.default.fileExists(atPath: url.path) || porDescarregar(url) else { return [] }
        guard let dados = try? lerDados(url) else { return nil }
        return try? decoder.decode([PerguntaAula].self, from: dados)
    }

    enum ErroPerguntas: LocalizedError {
        case porLer
        var errorDescription: String? { "As perguntas anteriores ainda não se conseguem ler (talvez a chegar do iCloud). Tenta outra vez daqui a pouco." }
    }

    static func lerTexto(_ nome: String, em pasta: URL) -> String? {
        try? Disco.lerTexto(pasta.appending(path: nome))
    }

    static func escreverTexto(_ texto: String, _ nome: String, em pasta: URL) throws {
        try gravar(texto, em: pasta.appending(path: nome))
    }

    static func dataModificacao(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

extension ContextoAula {
    /// Tudo o que se sabe de uma aula, como no pedido dos apontamentos. Com PDFs do professor, as capturas
    /// só vão até onde cabem no pedido, para se saber que páginas foram dadas.
    /// Lê PDFs (até 24 MB) e dezenas de JPEG e passa-os a base64: fora do fio principal.
    @concurrent
    /// `anexos`, `anexosAnteriores`: ficheiros juntados a uma pergunta (ver `Anexos`). Lê-los e convertê-los (um Excel
    /// grande, um ficheiro ainda a descarregar do iCloud) também é aqui, fora do fio principal; as capturas dos slides
    /// encolhem para lhes dar espaço.
    static func carregar(_ aula: Aula, cadeira: Cadeira?, transcricao: Transcricao,
                         anexos: [String] = [], anexosAnteriores: [String] = []) async -> ContextoAula {
        let reservado = (anexos + anexosAnteriores).reduce(0) { $0 + Anexos.tamanho($1, em: aula.pasta) } + Materiais.tamanho(em: aula.pasta)
        let pdfs = Disco.pdfsProfessor(aula.pasta, nomes: aula.meta.nomesPDFs ?? [:]).compactMap { pdf in
            (try? Disco.lerDados(pdf.url(em: aula.pasta), esperar: true)).map { PDFComDados(pdf: pdf, dados: $0) }
        }
        var slides = (Disco.lerSlides(aula.pasta) ?? []).compactMap { s in
            (try? Disco.lerDados(Disco.urlSlide(s, em: aula.pasta), esperar: true)).map { SlideComImagem(slide: s, jpeg: $0) }
        }
        if !pdfs.isEmpty || reservado > 0 {
            slides = capturasQueCabem(slides, bytes: Disco.tamanhoMaximoPDF - pdfs.reduce(0) { $0 + $1.dados.count } - reservado,
                                      maximo: pdfs.isEmpty ? .max : 40)
        }
        var contexto = ContextoAula(cadeira: aula.cadeira, titulo: aula.meta.titulo, data: aula.meta.data,
                                    glossario: cadeira?.meta.glossario ?? "",
                                    transcricao: transcricao, slides: slides, pdfsProfessor: pdfs,
                                    fichaCadeira: cadeira.flatMap { FichaCadeira.lerFicha($0.pasta) })
        contexto.anexos = Anexos.blocos(anexos, em: aula.pasta)
        contexto.anexosAnteriores = Anexos.blocos(anexosAnteriores, em: aula.pasta)
        contexto.materiaisProfessor = Materiais.blocos(em: aula.pasta)
        contexto.naoPercebi = aula.meta.naoPercebi ?? []
        return contexto
    }

    /// Até `maximo` capturas espalhadas pela aula, sem passar de `bytes` (o que sobra do pedido depois dos PDFs).
    nonisolated static func capturasQueCabem(_ capturas: [SlideComImagem], bytes: Int, maximo: Int = 40) -> [SlideComImagem] {
        guard !capturas.isEmpty, bytes > 0 else { return [] }
        let media = max(1, capturas.reduce(0) { $0 + $1.jpeg.count } / capturas.count)
        let quantas = min(maximo, capturas.count, bytes / media)
        guard quantas < capturas.count else { return capturas }
        guard quantas > 1 else { return quantas == 1 ? [capturas[0]] : [] }
        return (0..<quantas).map { capturas[($0 * (capturas.count - 1) + (quantas - 1) / 2) / (quantas - 1)] }
    }
}

/// Perguntar à aula, exercícios extra e ligações entre aulas. Os pedidos vivem aqui (e não nas vistas)
/// para continuarem quando se muda de aula ou de separador.
@MainActor @Observable
final class Estudo {
    enum Tipo: String, Codable, Sendable { case pergunta, exercicios, ligacoes }

    struct Chave: Hashable { var pasta: String; var tipo: Tipo }

    struct EmCurso {
        var texto = ""
        /// A pergunta a que se está a responder.
        var pergunta: String?
        var citacao: CitacaoPergunta?
        var anexos: [String] = []
        var tarefa: Task<Void, Never>?
        /// Pedido entregue ao Recap do Mac (motor "Mac", no iOS).
        var pedidoMac: PedidoMac?
        /// O Mac ainda não pegou no pedido ao fim de algum tempo (fechado, a dormir, sem iCloud).
        var aEsperarMac = false
    }

    private(set) var emCurso: [Chave: EmCurso] = [:]
    private(set) var erros: [Chave: String] = [:]
    /// Trecho escolhido para a próxima pergunta de cada aula (fica até se perguntar ou o tirar).
    private(set) var citacoes: [Chave: CitacaoPergunta] = [:]
    /// Ficheiros juntados para a próxima pergunta de cada aula (já em `anexos-chat/`). Voltam aqui se a pergunta falhar.
    private(set) var anexosPorEnviar: [Chave: [String]] = [:]
    /// Muda a cada trecho escolhido, para o painel das perguntas pôr o cursor no campo.
    private(set) var pedidosCitacao = 0
    /// O último trecho escolhido ainda não levou o cursor ao campo (só uma vez: voltar à aula ou abrir o painel não o rouba).
    @ObservationIgnored private var focoPendente = false
    /// Muda quando um ficheiro de estudo é gravado (as vistas voltam a ler do disco).
    private(set) var versao = 0
    /// A procura do que sai no exame nas aulas anteriores (ver `procurarPistasExame`): quantas já foram vistas, de quantas.
    private(set) var procuraExame: (feitas: Int, total: Int)?
    private(set) var erroExame: String?
    @ObservationIgnored private var tarefaExame: Task<Void, Never>?
    /// A procura das secções da guia nas aulas anteriores (ver `procurarSeccoesGuia`), por cadeira.
    private(set) var procuraGuia: [URL: (feitas: Int, total: Int)] = [:]
    private(set) var erroGuia: [URL: String] = [:]
    @ObservationIgnored private var tarefasGuia: [URL: Task<Void, Never>] = [:]

    private let library: Library
    private let definicoes: Definicoes

    init(library: Library, definicoes: Definicoes) {
        self.library = library
        self.definicoes = definicoes
    }

    static func chave(_ aula: Aula, _ tipo: Tipo) -> Chave { Chave(pasta: aula.pasta.standardizedFileURL.path, tipo: tipo) }

    func emCurso(_ aula: Aula, _ tipo: Tipo) -> EmCurso? { emCurso[Self.chave(aula, tipo)] }
    func erro(_ aula: Aula, _ tipo: Tipo) -> String? { erros[Self.chave(aula, tipo)] }

    func cancelar(_ aula: Aula, _ tipo: Tipo) {
        emCurso[Self.chave(aula, tipo)]?.tarefa?.cancel()
    }

    func citacao(_ aula: Aula) -> CitacaoPergunta? { citacoes[Self.chave(aula, .pergunta)] }
    func tirarCitacao(_ aula: Aula) { citacoes[Self.chave(aula, .pergunta)] = nil }

    func anexosPorEnviar(_ aula: Aula) -> [String] { anexosPorEnviar[Self.chave(aula, .pergunta)] ?? [] }
    func juntarAnexo(_ nome: String, a aula: Aula) { anexosPorEnviar[Self.chave(aula, .pergunta), default: []].append(nome) }
    func tirarAnexo(_ nome: String, de aula: Aula) {
        anexosPorEnviar[Self.chave(aula, .pergunta)]?.removeAll { $0 == nome }
        Anexos.remover(nome, em: aula.pasta)
    }
    func tirarAnexosPorEnviar(_ aula: Aula) { anexosPorEnviar[Self.chave(aula, .pergunta)] = nil }

    /// Perguntar sobre um trecho: fica à espera da pergunta no painel.
    func citar(_ citacao: CitacaoPergunta, em aula: Aula) {
        citacoes[Self.chave(aula, .pergunta)] = citacao.cortado()
        pedidosCitacao += 1
        focoPendente = true
    }

    /// O painel deve pôr o cursor no campo (uma vez por trecho escolhido).
    func consumirFoco() -> Bool {
        defer { focoPendente = false }
        return focoPendente
    }

    // MARK: Sai no exame

    /// As aulas transcritas onde ainda não se procurou o que sai no exame (as novas já vêm com isso).
    func aulasSemPistasExame(_ aulas: [Aula]) -> [Aula] {
        aulas.filter { $0.temTranscricao && Disco.lerPistasExame($0.pasta) == nil }
    }

    /// Procura, aula a aula, o que sai no exame nas aulas anteriores. Continua quando se muda de vista; uma aula que
    /// falhe fica por procurar e as outras seguem.
    func procurarPistasExame(_ aulas: [Aula]) {
        guard tarefaExame == nil else { return }
        let porVer = aulasSemPistasExame(aulas)
        guard !porVer.isEmpty else { return }
        erroExame = nil
        procuraExame = (0, porVer.count)
        tarefaExame = Task { [weak self] in
            guard let self else { return }
            defer { procuraExame = nil; tarefaExame = nil }
            let gerador: NotesGenerator
            do { gerador = try definicoes.gerador(esforco: .medium) } catch {
                erroExame = error.localizedDescription
                return
            }
            var falhas = 0
            for (i, aula) in porVer.enumerated() {
                if Task.isCancelled { return }
                if let t = Disco.lerTranscricao(aula.pasta) {
                    do {
                        let r = try await PistasExame.procurar(t, lingua: definicoes.linguaApontamentos, gerador: gerador)
                        try Disco.escreverPistasExame(r.pistas, em: aula.pasta)
                        versao += 1
                    } catch is CancellationError {
                        return
                    } catch {
                        falhas += 1
                    }
                }
                procuraExame = (i + 1, porVer.count)
            }
            if falhas > 0 { erroExame = "\(falhas) \(falhas == 1 ? "aula ficou" : "aulas ficaram") por ver: tenta outra vez mais tarde." }
        }
    }

    func cancelarPistasExame() { tarefaExame?.cancel() }

    // MARK: Progresso do programa

    /// As aulas transcritas onde ainda não se sabe que secções da guia foram dadas (as novas já o guardam).
    func aulasSemSeccoesGuia(_ cadeira: Cadeira) -> [Aula] {
        cadeira.aulas.filter { $0.temTranscricao && Disco.lerSeccoesGuia($0.pasta) == nil }
    }

    /// Vê, aula a aula, que secções da guia foram dadas nas aulas anteriores (um pedido curto por aula). Continua
    /// quando se muda de vista; uma aula que falhe fica por ver e as outras seguem.
    func procurarSeccoesGuia(_ cadeira: Cadeira) {
        let chave = cadeira.pasta
        guard procuraGuia[chave] == nil else { return }
        let porVer = aulasSemSeccoesGuia(cadeira)
        guard !porVer.isEmpty else { return }
        erroGuia[chave] = nil
        procuraGuia[chave] = (0, porVer.count)
        tarefasGuia[chave] = Task { [weak self] in
            guard let self else { return }
            defer { procuraGuia[chave] = nil; tarefasGuia[chave] = nil }
            guard let (indice, _) = await Task.detached(operation: { GuiaEstudo.carregar(cadeira: chave) }).value else {
                erroGuia[chave] = "Não consegui ler o índice da guia."
                return
            }
            let gerador: NotesGenerator
            do { gerador = try definicoes.gerador() } catch {
                erroGuia[chave] = error.localizedDescription
                return
            }
            var falhas = 0
            for (i, aula) in porVer.enumerated() {
                if Task.isCancelled { return }
                if let t = Disco.lerTranscricao(aula.pasta) {
                    do {
                        let r = try await SeccoesDaAula.escolher(indice, transcricao: t, gerador: gerador)
                        try Disco.escreverSeccoesGuia(SeccoesGuardadas(r.selecao, indice: indice), em: aula.pasta)
                        versao += 1
                    } catch is CancellationError {
                        return
                    } catch {
                        falhas += 1
                    }
                }
                procuraGuia[chave] = (i + 1, porVer.count)
            }
            if falhas > 0 { erroGuia[chave] = "\(falhas) \(falhas == 1 ? "aula ficou" : "aulas ficaram") por ver: tenta outra vez mais tarde." }
        }
    }

    func cancelarSeccoesGuia(_ cadeira: Cadeira) { tarefasGuia[cadeira.pasta]?.cancel() }

    // MARK: Pedidos

    /// `motor`: em vez do das Definições (o iOS usa a API quando o Mac não responde).
    func perguntar(_ pergunta: String, sobre aula: Aula, citacao: CitacaoPergunta? = nil, anexos: [String] = [], motor: MotorTipo? = nil) {
        let anteriores = Disco.lerPerguntas(aula.pasta)
        let chave = Self.chave(aula, .pergunta)
        defer {
            if let citacao, emCurso[chave]?.citacao == citacao { citacoes[chave] = nil }
            // Ficam no campo enquanto a pergunta não sai; se nem chegou a sair, voltam para lá.
            if emCurso[chave] != nil { anexosPorEnviar[chave] = nil } else if !anexos.isEmpty { anexosPorEnviar[chave] = anexos }
        }
        #if !os(macOS)
        if (motor ?? definicoes.motor) == .mac {
            return pedirAoMac(.pergunta, aula, pergunta: pergunta, citacao: citacao, anexos: anexos)
        }
        #endif
        // O Claude não se lembra das perguntas anteriores: os ficheiros delas voltam a ir, os mais recentes primeiro,
        // enquanto couberem ao lado dos PDFs e dos materiais do professor (o pedido todo não pode passar de ~32 MB).
        let doProfessor = Disco.tamanhoPDFsProfessor(em: aula.pasta) + Materiais.tamanho(em: aula.pasta)
        let tamanhos = { (nomes: [String]) in nomes.map { ($0, Anexos.tamanho($0, em: aula.pasta)) } }
        guard let escolhidos = Anexos.paraOPedido(
            atuais: tamanhos(anexos),
            anteriores: tamanhos(anteriores.suffix(8).reversed().flatMap { $0.anexos ?? [] }.filter { !anexos.contains($0) }),
            espaco: Disco.tamanhoMaximoPDF - doProfessor)
        else {
            erros[chave] = "Os PDFs e os materiais do professor desta aula já ocupam quase todo o pedido: estes ficheiros não cabem. Tira algum, ou junta-os mais pequenos."
            return
        }
        let anexosAnteriores = escolhidos.anteriores
        executar(aula, .pergunta, pergunta: pergunta, citacao: citacao, anexos: anexos, anexosAnteriores: anexosAnteriores,
                 esforco: .medium, motor: motor,
                 sistema: definicoes.prompt(Self.sistemaPerguntas, idioma: definicoes.idioma(da: library.cadeira(nome: aula.cadeira)))) { contexto in
            var blocos = contexto.map(NotesGenerator.materiais) ?? []
            if let notas = Disco.lerApontamentos(aula.pasta) {
                blocos.append(.texto("Apontamentos já feitos desta aula:\n\n<apontamentos>\n\(notas)\n</apontamentos>"))
                let seccoes = Seccoes.lista(notas)
                if !seccoes.isEmpty {
                    blocos.append(.texto("Secções dos apontamentos, já como links para usar nas respostas:\n\n<seccoes>\n\(Seccoes.indice(seccoes))\n</seccoes>"))
                }
            }
            if let outras = self.outrasAulasParaPerguntas(aula) {
                blocos.append(.texto(outras))
            }
            if !anteriores.isEmpty {
                let conversa = anteriores.suffix(8).map {
                    "Pergunta: \(Self.pedido($0.pergunta, citacao: $0.citacao?.cortado(300)))\(Self.juntou($0.anexos ?? []))\n\nResposta: \($0.resposta)"
                }.joined(separator: "\n\n---\n\n")
                blocos.append(.texto("Perguntas anteriores sobre esta aula:\n\n<conversa>\n\(conversa)\n</conversa>"))
            }
            if let anteriores = contexto?.anexosAnteriores, !anteriores.isEmpty {
                blocos.append(.texto("Ficheiros que o estudante juntou às perguntas anteriores (voltam aqui para os poderes consultar):"))
                blocos += anteriores
            }
            if let atuais = contexto?.anexos, !atuais.isEmpty {
                blocos.append(.texto("Ficheiros que o estudante juntou a esta pergunta:"))
                blocos += atuais
            }
            blocos.append(.texto("Pergunta do estudante:\n\n\(Self.pedido(pergunta, citacao: citacao))"))
            return blocos
        } concluir: { texto in
            let nova = PerguntaAula(pergunta: pergunta, resposta: texto, citacao: citacao, anexos: anexos.isEmpty ? nil : anexos)
            try Disco.juntarPergunta(nova, em: aula.pasta)
        }
    }

    /// Enviar sem escrever nada com um trecho escolhido pede para o explicar.
    nonisolated static let perguntaSobreTrecho = "Explica este trecho"

    /// Enviar sem escrever nada só com ficheiros juntados pede para os explicar.
    nonisolated static let perguntaSobreFicheiros = "Explica o que está nestes ficheiros"

    /// A pergunta a enviar a partir do que foi escrito no campo, ou nil se não houver nada para perguntar.
    nonisolated static func pergunta(_ escrito: String, citacao: CitacaoPergunta?, anexos: [String] = []) -> String? {
        let p = escrito.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { return p }
        if citacao != nil { return perguntaSobreTrecho }
        return anexos.isEmpty ? nil : perguntaSobreFicheiros
    }

    /// A pergunta como vai para o Claude: o trecho selecionado (e de onde vem) antes da pergunta.
    /// Na conversa enviada ao Claude: que ficheiros acompanharam uma pergunta anterior.
    nonisolated static func juntou(_ anexos: [String]) -> String {
        anexos.isEmpty ? "" : "\n(Juntou: " + anexos.map { "\"\($0)\"" }.joined(separator: ", ") + ")"
    }

    nonisolated static func pedido(_ pergunta: String, citacao: CitacaoPergunta?) -> String {
        guard let citacao else { return pergunta }
        let onde = switch citacao.origem {
        case .apontamentos: "dos apontamentos"
        case .transcricao: "da transcrição" + (citacao.inicio.map { ", dito aos [\(Timestamp.format($0))]" } ?? "")
        }
        return "Sobre este trecho \(onde):\n\n<trecho>\n\(citacao.texto)\n</trecho>\n\n\(pergunta)"
    }

    func gerarExercicios(_ aula: Aula, motor: MotorTipo? = nil) {
        #if !os(macOS)
        if (motor ?? definicoes.motor) == .mac { return pedirAoMac(.exercicios, aula) }
        #endif
        executar(aula, .exercicios, motor: motor, sistema: definicoes.prompt(Self.sistemaExercicios, idioma: definicoes.idioma(da: library.cadeira(nome: aula.cadeira)))) { contexto in
            var blocos = contexto.map(NotesGenerator.materiais) ?? []
            if let notas = Disco.lerApontamentos(aula.pasta) {
                blocos.append(.texto("Apontamentos desta aula:\n\n<apontamentos>\n\(notas)\n</apontamentos>"))
            }
            blocos.append(.texto("Cria os exercícios desta aula seguindo as instruções."))
            return blocos
        } concluir: { texto in
            try Disco.escreverTexto(texto, Disco.exerciciosMD, em: aula.pasta)
        }
    }

    /// Gera as ligações sem se pedir: quando a aula ainda não as tem ou os apontamentos mudaram desde então.
    /// Chamado ao acabar os apontamentos e ao abrir a aula; não repete depois de um erro (fica o botão).
    func gerarLigacoesSePreciso(_ aula: Aula) {
        guard aula.temApontamentos, definicoes.faltaParaGerar == nil, emCurso(aula, .ligacoes) == nil, erro(aula, .ligacoes) == nil,
              !outrasAulas(de: aula).isEmpty,
              Disco.lerLigacoes(aula.pasta) == nil || ligacoesDesatualizadas(aula)
        else { return }
        gerarLigacoes(aula)
    }

    func gerarLigacoes(_ aula: Aula, motor: MotorTipo? = nil) {
        #if !os(macOS)
        if (motor ?? definicoes.motor) == .mac { return pedirAoMac(.ligacoes, aula) }
        #endif
        let outras = outrasAulas(de: aula)
        guard let notas = Disco.lerApontamentos(aula.pasta).map(NotasLigacoes.tirar) else { return }
        guard !outras.isEmpty else {
            erros[Self.chave(aula, .ligacoes)] = "Ainda não há outras aulas com apontamentos em \(aula.cadeira)."
            return
        }
        let raiz = library.raiz
        executar(aula, .ligacoes, comTranscricao: false, motor: motor, sistema: definicoes.prompt(Self.sistemaLigacoes)) { _ in
            let lista = outras.enumerated().map { i, o in
                let data = o.meta.data.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_PT")))
                let md = NotasLigacoes.tirar(Disco.lerApontamentos(o.pasta) ?? "")
                return "<aula id=\"A\(i + 1)\" titulo=\"\(o.meta.titulo)\" data=\"\(data)\"\(o.meta.data < aula.meta.data ? " anterior" : " seguinte")>\n\(Self.esqueleto(md))\n<seccoes>\n\(Seccoes.indice(Seccoes.lista(md)))\n</seccoes>\n</aula>"
            }.joined(separator: "\n\n")
            return [
                .texto("Cadeira: \(aula.cadeira)\nAula atual: \(aula.meta.titulo) (\(aula.meta.data.formatted(date: .long, time: .omitted)))\n\nApontamentos da aula atual:\n\n<apontamentos>\n\(notas)\n</apontamentos>\n\nSecções da aula atual:\n\n<seccoes>\n\(Seccoes.indice(Seccoes.lista(notas)))\n</seccoes>"),
                .texto("Outras aulas da cadeira (resumo, temas e secções de cada uma):\n\n\(lista)"),
                .texto("Devolve as ligações da aula atual com as outras em JSON, seguindo as instruções."),
            ]
        } concluir: { texto in
            let ids = Dictionary(uniqueKeysWithValues: outras.enumerated().map { ("A\($0 + 1)", Self.caminhoRelativo($1.pasta, raiz: raiz)) })
            var ligacoes = try LigacoesAula.daResposta(texto, aulas: ids)
            ligacoes.formato = LigacoesAula.formatoAtual
            ligacoes.assinaturas = Dictionary(uniqueKeysWithValues: ([aula] + outras).compactMap { a in
                Disco.lerApontamentos(a.pasta).map { (Self.caminhoRelativo(a.pasta, raiz: raiz), NotasLigacoes.assinatura($0)) }
            })
            try Disco.escreverLigacoes(ligacoes, em: aula.pasta)
            self.aplicarNotas(aula.cadeira)
        }
    }

    /// Apontamentos acabados de gerar: as notas das ligações voltam para eles e as ligações refazem-se se for preciso.
    func aposApontamentos(_ aula: Aula) {
        aplicarNotas(aula.cadeira)
        gerarLigacoesSePreciso(aula)
    }

    /// Aula cujos apontamentos estão a ser editados: as notas das ligações não lhe mexem até acabar.
    var pastaEmEdicao: URL?
    /// Muda quando a app escreve nos apontamentos (as notas das ligações), para a aula aberta os voltar a ler.
    private(set) var versaoApontamentos = 0

    /// Põe nos apontamentos de cada aula da cadeira as notas das suas ligações ("🔗 Aprofundado na Aula 2 → …"):
    /// as que a aula fez com as outras e, para as aulas com que ela não fez nenhuma, as que essas fizeram com ela.
    /// Só escreve os apontamentos que mudam.
    func aplicarNotas(_ nomeCadeira: String) {
        let raiz = library.raiz
        let aulas = (library.cadeira(nome: nomeCadeira)?.aulas ?? []).filter(\.temApontamentos).sorted { $0.meta.data < $1.meta.data }
        let caminhos = aulas.map { Self.caminhoRelativo($0.pasta, raiz: raiz) }
        var apontamentos: [String: String] = [:], ligacoes: [String: LigacoesAula] = [:]
        for (a, c) in zip(aulas, caminhos) {
            apontamentos[c] = Disco.lerApontamentos(a.pasta)
            ligacoes[c] = Disco.lerLigacoes(a.pasta)
        }
        func nota(_ seccao: String?, _ texto: String, destino: String, seccaoDestino: String?) -> NotasLigacoes.Nota? {
            guard let seccao, let md = apontamentos[destino], let alvo = aulas.first(where: { Self.caminhoRelativo($0.pasta, raiz: raiz) == destino })
            else { return nil }
            let s = seccaoDestino.flatMap { Seccoes.resolver(LigacaoSeccao(ancora: $0, texto: ""), em: Seccoes.lista(md)) }
            return NotasLigacoes.Nota(seccao: seccao, texto: texto, link: "#\(Self.prefixoLink(alvo.pasta))/\(s?.ancora ?? "")",
                                      tituloLink: s?.titulo ?? alvo.meta.titulo)
        }
        var mudou = false
        for (aula, caminho) in zip(aulas, caminhos) where !(pastaEmEdicao.map(aula.pasta.mesmoCaminho) ?? false) {
            guard let md = apontamentos[caminho] else { continue }
            var notas: [NotasLigacoes.Nota] = []
            var feitas: Set<String> = []
            for l in ligacoes[caminho]?.ligacoes ?? [] where !(l.pontos ?? []).isEmpty {
                feitas.insert(l.aula)
                notas += (l.pontos ?? []).compactMap { nota($0.seccao, $0.nota, destino: l.aula, seccaoDestino: $0.seccaoOutra) }
            }
            for outra in caminhos where outra != caminho && !feitas.contains(outra) {
                for l in ligacoes[outra]?.ligacoes ?? [] where l.aula == caminho {
                    notas += (l.pontos ?? []).compactMap { p in
                        p.notaOutra.flatMap { nota(p.seccaoOutra, $0, destino: outra, seccaoDestino: p.seccao) }
                    }
                }
            }
            let novo = NotasLigacoes.por(notas, em: md)
            if novo != md, (try? Disco.escreverApontamentos(novo, em: aula.pasta)) != nil { mudou = true }
        }
        if mudou { versaoApontamentos += 1 }
    }

    /// As ligações da aula para mostrar: as que se geraram nela e as que as outras aulas fizeram com ela, vistas
    /// do outro lado (a aula 2 diz que aprofunda a aula 1, e a aula 1 mostra que continua na aula 2).
    /// Quando as duas falam da mesma ligação, fica a desta aula, com os conceitos das duas.
    func ligacoes(_ aula: Aula) -> LigacoesAula? {
        let raiz = library.raiz
        let esta = Self.caminhoRelativo(aula.pasta, raiz: raiz)
        let propria = Disco.lerLigacoes(aula.pasta)
        var ligacoes = propria?.ligacoes ?? []
        for outra in outrasAulas(de: aula) {
            guard let delas = Disco.lerLigacoes(outra.pasta) else { continue }
            let caminho = Self.caminhoRelativo(outra.pasta, raiz: raiz)
            for l in delas.ligacoes where l.aula == esta {
                let direcao: LigacoesAula.Direcao = l.direcao == .anterior ? .seguinte : .anterior
                if let i = ligacoes.firstIndex(where: { $0.aula == caminho && $0.direcao == direcao }) {
                    ligacoes[i].conceitos += l.conceitos.filter { !ligacoes[i].conceitos.contains($0) }
                } else {
                    ligacoes.append(.init(aula: caminho, direcao: direcao, conceitos: l.conceitos,
                                          explicacao: l.explicacaoInversa ?? l.explicacao, momento: nil))
                }
            }
        }
        guard propria != nil || !ligacoes.isEmpty else { return nil }
        let ordem = Dictionary(uniqueKeysWithValues: outrasAulas(de: aula).enumerated().map { (Self.caminhoRelativo($1.pasta, raiz: raiz), $0) })
        ligacoes.sort { (ordem[$0.aula] ?? .max) < (ordem[$1.aula] ?? .max) }
        return LigacoesAula(ligacoes: ligacoes, temas: propria?.temas ?? [], geradoEm: propria?.geradoEm ?? .distantPast)
    }

    /// Quanto dos apontamentos das outras aulas vai com cada pergunta (~25 mil tokens). Passando disto,
    /// as aulas mais afastadas e sem ligação vão só com o resumo e os títulos.
    nonisolated static let limiteOutrasAulas = 90_000

    /// As outras aulas da cadeira para o chat: primeiro as ligadas a esta, depois as mais próximas no tempo.
    /// Cada uma com as suas secções já como links (`#<aula>/<secção>`), para a resposta levar à outra aula.
    private func outrasAulasParaPerguntas(_ aula: Aula) -> String? {
        let raiz = library.raiz
        let outras = outrasAulas(de: aula)
        guard !outras.isEmpty else { return nil }
        let ligadas = Set((ligacoes(aula)?.ligacoes ?? []).map(\.aula))
        let distancia = { (o: Aula) in abs(o.meta.data.timeIntervalSince(aula.meta.data)) }
        let prioridade = outras.sorted {
            let (a, b) = (ligadas.contains(Self.caminhoRelativo($0.pasta, raiz: raiz)), ligadas.contains(Self.caminhoRelativo($1.pasta, raiz: raiz)))
            return a != b ? a : distancia($0) < distancia($1)
        }
        var sobra = Self.limiteOutrasAulas
        var completas: Set<URL> = []
        for o in prioridade {
            let tamanho = Disco.lerApontamentos(o.pasta)?.count ?? 0
            if tamanho <= sobra { completas.insert(o.pasta); sobra -= tamanho }
        }
        let lista = outras.map { o in
            let notas = Disco.lerApontamentos(o.pasta) ?? ""
            return Self.aulaParaPerguntas(titulo: o.meta.titulo, data: o.meta.data, anterior: o.meta.data < aula.meta.data,
                                          prefixo: Self.prefixoLink(o.pasta), apontamentos: notas, completa: completas.contains(o.pasta))
        }.joined(separator: "\n\n")
        return "Outras aulas desta cadeira, por ordem (\(completas.count == outras.count ? "com os apontamentos completos" : "as ligadas a esta e as mais próximas com os apontamentos completos, as outras só com o resumo e os títulos")):\n\n\(lista)"
    }

    /// Uma outra aula no pedido das perguntas. Sem os [mm:ss] (na conversa levariam ao vídeo desta aula) nem as imagens dos slides.
    nonisolated static func aulaParaPerguntas(titulo: String, data: Date, anterior: Bool, prefixo: String, apontamentos: String, completa: Bool) -> String {
        let quando = data.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_PT")))
        let seccoes = Seccoes.lista(apontamentos).map { s in
            Seccoes.Seccao(indice: s.indice, nivel: s.nivel, titulo: s.titulo, ancora: "\(prefixo)/\(s.ancora)")
        }
        let corpo = (completa ? apontamentos : esqueleto(apontamentos))
            .components(separatedBy: .newlines).filter { !$0.hasPrefix("![") }.joined(separator: "\n")
            .replacing(/[ ]?\[(?:\d{1,2}:)?\d{1,3}:\d{2}\]/, with: "")
        return """
        <aula titulo="\(titulo)" data="\(quando)" \(anterior ? "anterior" : "seguinte")>
        <seccoes>
        \(Seccoes.indice(seccoes))
        </seccoes>
        <\(completa ? "apontamentos" : "resumo")>
        \(corpo.trimmingCharacters(in: .whitespacesAndNewlines))
        </\(completa ? "apontamentos" : "resumo")>
        </aula>
        """
    }

    /// O início dos links para as secções de outra aula: `[Fiscalidade](#2026-10-21-aula-2/fiscalidade)`.
    nonisolated static func prefixoLink(_ pasta: URL) -> String { Seccoes.ancora(pasta.lastPathComponent) }

    /// Para onde leva um link numa resposta: uma secção desta aula ou, com `<aula>/`, de outra aula da cadeira.
    func destino(_ ligacao: LigacaoSeccao, aPartirDe aula: Aula) -> DestinoAula {
        var ancora = ligacao.ancora.removingPercentEncoding ?? ligacao.ancora
        if ancora.hasPrefix("#") { ancora.removeFirst() }
        if let barra = ancora.firstIndex(of: "/") {
            let prefixo = String(ancora[..<barra])
            let seccao = LigacaoSeccao(ancora: String(ancora[ancora.index(after: barra)...]), texto: ligacao.texto)
            let alvo = (library.cadeira(nome: aula.cadeira)?.aulas ?? []).first { Self.prefixoLink($0.pasta) == prefixo }
            return DestinoAula(pasta: alvo?.pasta ?? aula.pasta, separador: .apontamentos, seccao: seccao)
        }
        return DestinoAula(pasta: aula.pasta, separador: .apontamentos, seccao: ligacao)
    }

    /// As outras aulas da cadeira com apontamentos, por data.
    func outrasAulas(de aula: Aula) -> [Aula] {
        (library.cadeira(nome: aula.cadeira)?.aulas ?? [])
            .filter { $0.temApontamentos && !$0.pasta.mesmoCaminho(aula.pasta) }
            .sorted { $0.meta.data < $1.meta.data }
    }

    /// As ligações já não refletem os apontamentos: os desta aula ou os de uma aula ligada mudaram (ou ela foi apagada).
    /// Uma aula nova não conta: ao gerar as suas ligações, elas aparecem também nesta. Ligações de um formato
    /// anterior contam como desatualizadas (as notas eram outras, ou não havia).
    func ligacoesDesatualizadas(_ aula: Aula) -> Bool {
        Self.ligacoesDesatualizadas(aula, outras: outrasAulas(de: aula), raiz: library.raiz)
    }

    /// Lê os apontamentos de todas as aulas ligadas: fora do fio principal na interface (`LigacoesView`).
    nonisolated static func ligacoesDesatualizadas(_ aula: Aula, outras: [Aula], raiz: URL) -> Bool {
        guard let l = Disco.lerLigacoes(aula.pasta) else { return false }
        guard let assinaturas = l.assinaturas, l.formato == LigacoesAula.formatoAtual else { return true }
        let aulas = Dictionary(([aula] + outras).map { (Self.caminhoRelativo($0.pasta, raiz: raiz), $0) }) { a, _ in a }
        return Set(l.ligacoes.map(\.aula) + [Self.caminhoRelativo(aula.pasta, raiz: raiz)]).contains { caminho in
            guard let md = aulas[caminho].flatMap({ Disco.lerApontamentos($0.pasta) }) else { return true }
            return assinaturas[caminho] != NotasLigacoes.assinatura(md)
        }
    }

    func apagarPerguntas(_ aula: Aula) {
        try? Disco.escreverPerguntas([], em: aula.pasta)
        Anexos.limparOrfaos(em: aula.pasta, usados: Set(anexosPorEnviar(aula)), idade: 0)
        versao += 1
    }

    // MARK: Execução

    private func executar(
        _ aula: Aula, _ tipo: Tipo, pergunta: String? = nil, citacao: CitacaoPergunta? = nil, anexos: [String] = [], anexosAnteriores: [String] = [],
        comTranscricao: Bool = true, esforco: Esforco? = nil,
        motor: MotorTipo? = nil, sistema: String,
        conteudo: @escaping @MainActor (ContextoAula?) -> [BlocoConteudo],
        concluir: @escaping @MainActor (String) throws -> Void
    ) {
        let chave = Self.chave(aula, tipo)
        guard emCurso[chave] == nil else { return }
        erros[chave] = nil
        let gerador: NotesGenerator
        do { gerador = try definicoes.gerador(esforco: esforco, motor: motor) } catch {
            erros[chave] = error.localizedDescription
            return
        }
        let transcricao = comTranscricao ? Disco.lerTranscricao(aula.pasta) : nil
        if comTranscricao && transcricao == nil {
            erros[chave] = "Esta aula ainda não tem transcrição."
            return
        }
        let cadeira = library.cadeira(nome: aula.cadeira)
        emCurso[chave] = EmCurso(pergunta: pergunta, citacao: citacao, anexos: anexos)
        emCurso[chave]?.tarefa = Task {
            do {
                // Só se leem os slides e os PDFs quando o pedido precisa deles, e fora do fio principal.
                let contexto: ContextoAula? = if let transcricao { await ContextoAula.carregar(aula, cadeira: cadeira, transcricao: transcricao, anexos: anexos, anexosAnteriores: anexosAnteriores) } else { nil }
                let blocos = conteudo(contexto)
                let r = try await gerador.gerar(
                    sistema: sistema, conteudo: blocos,
                    aoRecomecar: { [weak self] in self?.emCurso[chave]?.texto = "" },
                    aoReceber: { [weak self] pedaco in self?.emCurso[chave]?.texto += pedaco },
                    aoRepetir: { _, _, _ in }
                )
                try concluir(r.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    erros[chave] = error.localizedDescription
                    // O trecho volta para o campo, para tentar outra vez sem o selecionar de novo.
                    if let c = emCurso[chave]?.citacao, citacoes[chave] == nil { citacoes[chave] = c }
                    if let a = emCurso[chave]?.anexos, !a.isEmpty, anexosPorEnviar[chave] == nil { anexosPorEnviar[chave] = a }
                }
            }
            emCurso[chave] = nil
            versao += 1
        }
    }

    #if !os(macOS)
    // MARK: Pelo Mac

    /// Entrega o pedido ao Recap do Mac (`CaixaPedidos`) e vai lendo o estado que ele escreve. O resultado chega
    /// pelo iCloud no ficheiro de sempre (`perguntas.json`, `exercicios.md`, `ligacoes.json`): espera-se por ele.
    private func pedirAoMac(_ tipo: Tipo, _ aula: Aula, pergunta: String? = nil, citacao: CitacaoPergunta? = nil, anexos: [String] = []) {
        let chave = Self.chave(aula, tipo)
        guard emCurso[chave] == nil else { return }
        erros[chave] = nil
        let raiz = library.raiz
        let pedido = PedidoMac(tipo: tipo, aula: Self.caminhoRelativo(aula.pasta, raiz: raiz), pergunta: pergunta, citacao: citacao,
                               anexos: anexos.isEmpty ? nil : anexos)
        // Um URL novo de cada vez: o `URL` guarda em cache a data de modificação.
        let resultado = { aula.pasta.appending(path: Self.ficheiro(tipo)) }
        let antes = Disco.dataModificacao(resultado())
        do { try CaixaPedidos.enviar(pedido, raiz: raiz) } catch {
            erros[chave] = "Não foi possível enviar o pedido ao Mac: \(error.localizedDescription)"
            return
        }
        emCurso[chave] = EmCurso(pergunta: pergunta, citacao: citacao, anexos: anexos, pedidoMac: pedido)
        emCurso[chave]?.tarefa = Task {
            let inicio = Date.now
            var recebido = false
            ciclo: while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let e = CaixaPedidos.estado(pedido.id, raiz: raiz) else {
                    if !recebido, Date.now.timeIntervalSince(inicio) > 30, emCurso[chave]?.aEsperarMac == false { emCurso[chave]?.aEsperarMac = true }
                    continue
                }
                recebido = true
                if emCurso[chave]?.aEsperarMac == true { emCurso[chave]?.aEsperarMac = false }
                if let t = e.texto, !t.isEmpty, t != emCurso[chave]?.texto { emCurso[chave]?.texto = t }
                switch e.fase {
                case .recebido, .aGerar:
                    if Date.now.timeIntervalSince(e.atualizadoEm) > 180 {
                        erros[chave] = "O Recap no Mac deixou de responder (fechou-se ou adormeceu)."
                        break ciclo
                    }
                case .erro:
                    erros[chave] = e.erro ?? "O Mac não conseguiu responder."
                    break ciclo
                case .feito:
                    // O estado pode chegar antes do ficheiro: até um minuto à espera de o ver mudar e descarregado.
                    let fim = Date.now.addingTimeInterval(60)
                    while !Task.isCancelled, Date.now < fim,
                          Disco.dataModificacao(resultado()) == antes || Disco.porDescarregar(resultado()) {
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                    break ciclo
                }
            }
            if Task.isCancelled { CaixaPedidos.apagar(pedido.id, raiz: raiz) }
            if erros[chave] != nil, !anexos.isEmpty, anexosPorEnviar[chave] == nil { anexosPorEnviar[chave] = anexos }
            // "Usar a API" já pôs outro pedido no lugar deste: não o apagar.
            if emCurso[chave]?.pedidoMac?.id == pedido.id { emCurso[chave] = nil }
            versao += 1
        }
    }

    /// O Mac não está a responder: faz o mesmo pedido pela API (se houver chave).
    func usarAPI(_ aula: Aula, _ tipo: Tipo) {
        let chave = Self.chave(aula, tipo)
        guard let pedido = emCurso[chave]?.pedidoMac else { return }
        emCurso[chave]?.tarefa?.cancel()
        emCurso[chave] = nil
        switch tipo {
        case .pergunta: perguntar(pedido.pergunta ?? "", sobre: aula, citacao: pedido.citacao, anexos: pedido.anexos ?? [], motor: .api)
        case .exercicios: gerarExercicios(aula, motor: .api)
        case .ligacoes: gerarLigacoes(aula, motor: .api)
        }
    }

    /// Onde o Mac grava o resultado de cada tipo de pedido.
    private static func ficheiro(_ tipo: Tipo) -> String {
        switch tipo {
        case .pergunta: Disco.perguntasJSON
        case .exercicios: Disco.exerciciosMD
        case .ligacoes: Disco.ligacoesJSON
        }
    }
    #endif

    // MARK: Ajudas

    /// O resumo e os títulos dos apontamentos de uma aula (o suficiente para as ligações, sem gastar tokens).
    nonisolated static func esqueleto(_ md: String) -> String {
        var linhas: [String] = []
        var noResumo = false
        for linha in md.components(separatedBy: .newlines) {
            if linha.hasPrefix("#") {
                noResumo = RotulosApontamentos.todas("Resumo").contains { linha.lowercased().hasPrefix("## " + $0.lowercased()) }
                if !linha.hasPrefix("# ") { linhas.append(linha) }
            } else if noResumo, !linha.trimmingCharacters(in: .whitespaces).isEmpty {
                linhas.append(linha)
            }
        }
        return linhas.joined(separator: "\n")
    }

    nonisolated static func caminhoRelativo(_ pasta: URL, raiz: URL) -> String {
        pasta.standardizedFileURL.path.replacingOccurrences(of: raiz.standardizedFileURL.path + "/", with: "")
    }

    // MARK: Prompts

    private static let comum = """
    ## Língua e formato
    {{regras_lingua}}
    - Markdown. Matemática em LaTeX: `$...$` inline e `$$...$$` em bloco, numa linha própria.
    - Momentos da aula como [mm:ss], só com timestamps que existam na transcrição.
    """

    /// Com `{{contexto}}` e `{{idioma}}` por substituir (`Definicoes.prompt`).
    static let sistemaPerguntas = """
    Respondes às perguntas de um estudante sobre uma aula universitária que ele assistiu. {{contexto}} Recebes a transcrição automática (em {{idioma}}, com erros do reconhecimento de voz), os slides ou o PDF do professor, e os apontamentos já feitos. Recebes também os apontamentos das outras aulas da mesma cadeira (completos, ou só o resumo e os títulos).

    ## Como responder
    - Responde diretamente à pergunta, de forma clara e curta, para quem está a ver a matéria pela primeira vez.
    - Baseia-te no que foi dito e mostrado na aula, e indica o momento com o seu [mm:ss].
    - A matéria é só a do professor: responde com o que ele disse e o que está nos slides. O que os alunos disseram não é matéria, mesmo que o professor concorde; só o refiras se a pergunta for sobre isso, e então diz que foi um aluno. Nunca escrevas nomes de alunos: "um aluno", "uma aluna".
    - Quando referires uma secção ou tópico dos apontamentos (por exemplo, "em que parte se fala de X"), põe o link dessa secção tal como vem na lista de secções, ex.: [Cadeia de valor](#cadeia-de-valor). O estudante clica e vai para lá. Só links da lista, nunca âncoras inventadas.
    - Se a pergunta vier com um trecho selecionado (dos apontamentos ou da transcrição), responde sobre esse trecho e situa-o na aula. Num trecho da transcrição, usa o momento indicado para encontrar o contexto.
    - Se a pergunta for sobre um trecho confuso, diz o que o professor disse (podes citar a frase na língua original e traduzi-la) e explica-o.
    - Podes acrescentar explicações que o professor não deu, se forem conhecimento padrão e estiverem certas; põe-nas num bloco `> 💡 **Explicação extra:** ...`.
    - A matéria é muitas vezes dada aos bocados: falada por alto numa aula e aprofundada noutra. Se a pergunta tocar num assunto que outra aula da cadeira também trata, junta o que essa aula diz e diz de que aula vem ("na Aula 2, a professora aprofundou…"), com o link da secção tal como vem na lista dessa aula, ex.: [Fiscalidade](#2026-10-21-aula-2/fiscalidade). Começa pelo que foi dito na aula aberta, se ela falar do assunto.
    - Se o estudante estiver a fazer um resumo, diz-lhe que partes desta aula são explicadas melhor noutra (e deve resumi-las lá) e o que vale a pena guardar desta.
    - Os [mm:ss] são só da aula aberta: para outras aulas usa o link da secção, nunca um [mm:ss].
    - Se nenhuma aula falar do assunto, diz isso claramente antes de responder com conhecimento geral.
    - Nunca inventes o que o professor disse.
    - Sem cabeçalho com a pergunta: começa logo pela resposta.
    - Quando um esquema ajudar a perceber (uma classificação, um processo, as partes de um conceito) ou o estudante o pedir, desenha-o num bloco ```mermaid. Um esquema serve para ver a estrutura de relance, por isso tem de ser simples:
      - No máximo 8 caixas e um nível abaixo do ponto de partida; mais do que isso, faz vários esquemas pequenos ou uma tabela.
      - Os exemplos e os pormenores vão dentro da caixa, numa segunda linha, e não em caixas próprias: `P["<b>Primário</b><br/>extração: minas, pesca"]`.
      - Classificações e hierarquias com `flowchart LR` (da esquerda para a direita, para caber na largura); processos por passos com `flowchart TD`.
      - O ponto de partida é o tema em poucas palavras, sem repetir o título da resposta. O texto de cada caixa vai sempre entre aspas.
      - Cores com lógica: cada ramo tem a sua cor, e a caixa da categoria e tudo o que dela sai levam a mesma classe, de `:::c1` a `:::c6` (`P["<b>Primário</b>"]:::c1`). O ponto de partida fica sem cor. Num processo, a mesma cor marca a mesma fase. Não definas cores tuas (`classDef`, `style`).
    - Se o estudante pedir um PDF (um resumo, uma ficha, um esquema para imprimir…), começa a resposta exatamente com a linha `\(PerguntaAula.marcaPDF)` e escreve a seguir o documento completo, a começar por um título `# …`, sem nada antes nem depois: a app mostra um botão para o guardar em PDF. Num PDF não ponhas [mm:ss] nem links para secções.

    \(comum)
    """

    /// Com `{{contexto}}` por substituir (`Definicoes.prompt`).
    static let sistemaExercicios = """
    Crias exercícios de treino sobre uma aula universitária. {{contexto}} Recebes a transcrição, os slides ou o PDF do professor, e os apontamentos.

    ## Exercícios
    - 6 a 8 exercícios parecidos com os exemplos e exercícios da aula, com os mesmos métodos e notação, por ordem crescente de dificuldade.
    - Só matéria dada nesta aula: nada de métodos, teoremas ou conceitos que não apareceram.
    - O que está nos blocos `👀` dos apontamentos foi só mencionado, não dado: nada de exercícios sobre isso.
    - Números diferentes dos da aula, escolhidos para as contas darem resultados limpos. Confirma cada resultado antes de o escrever.
    - Alíneas a), b)… numa lista, uma por linha.
    - Se a aula não tiver matéria que dê para exercícios de cálculo (por exemplo, uma aula só de apresentação), faz perguntas de compreensão sobre o que foi dado.

    ## Formato
    Começa diretamente pelo título, sem introdução:

    # Exercícios: <título da aula>

    Para cada exercício:

    ## Exercício <n> · <Fácil|Médio|Difícil>
    <enunciado completo>

    *Matéria da aula:* <tema> [mm:ss]

    > **Resolução**
    >
    > <resolução passo a passo, cada passo com uma frase a dizer porquê>
    >
    > **Resultado:** <resultado final>

    A resolução tem de ficar toda dentro da citação (todas as linhas começam por `>`), porque a app esconde-a até o estudante a abrir.

    \(comum)
    """

    /// Com `{{lingua_apontamentos}}` por substituir (`Definicoes.prompt`).
    static let sistemaLigacoes = """
    Mostras a um estudante como uma aula se liga às outras aulas da mesma cadeira. Interessa sobretudo a matéria dada aos bocados: um assunto falado por alto numa aula e aprofundado noutra, ou usado mais à frente. Recebes os apontamentos completos da aula atual e, de cada outra aula, o resumo e os temas, com um id (A1, A2…) e a indicação "anterior" ou "seguinte".

    ## O que procurar
    - Só ligações reais entre conteúdos: conceitos que a aula atual usa e que vieram de aulas anteriores, e conceitos da aula atual que são usados ou aprofundados em aulas seguintes.
    - Temas que aparecem em várias aulas.
    - Não inventes conteúdos que não estejam nos resumos ou nos temas.

    ## Resposta
    Devolve só JSON válido, sem texto antes nem depois e sem ```, neste formato:

    {
      "ligacoes": [
        {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio", "polinómio característico"],
         "explicacao": "Uma ou duas frases: o que vem de onde e para que serve aqui.",
         "explicacao_outra": "A mesma ligação contada a quem está a estudar a outra aula.", "momento": "00:17",
         "pontos": [{"seccao": "#valores-proprios", "seccao_outra": "#polinomio-caracteristico",
                     "nota": "Não resumas o cálculo aqui: está explicado melhor na Aula 1, com o exemplo 2×2.",
                     "nota_outra": "Resume-o aqui: a Aula 3 usa-o para encontrar os valores próprios e não o volta a explicar."}]}
      ],
      "temas_comuns": [
        {"tema": "Descida do gradiente", "aulas": ["A1"], "explicacao": "Uma frase sobre como o tema aparece nas aulas."}
      ]
    }

    - `direcao`: "anterior" se o conteúdo vem dessa aula para a atual; "seguinte" se a aula atual prepara essa aula.
    - Uma entrada por aula e direção, com todos os conceitos dessa ligação (2 a 5 palavras cada).
    - `explicacao_outra`: a mesma ligação contada do lado da outra aula, para a mostrar lá (ex.: "Aqui a fiscalidade foi vista por alto; na aula de Formas jurídicas é aprofundada: IVA, IRPF e tabelas."). Refere a aula atual pelo título.
    - `momento`: o mm:ss da aula atual onde a ligação aparece, tirado dos apontamentos, ou null.
    - `pontos`: as secções onde a ligação se vê, para a app pôr uma nota curta nos apontamentos das duas aulas, por baixo do título da secção. `seccao` é a âncora da secção da aula atual e `seccao_outra` a da outra aula, tal como vêm nas listas de secções; nunca âncoras inventadas. Um ponto por par de secções, só os que interessam a quem estuda (no máximo 3 por ligação): sobretudo um assunto falado por alto numa aula e aprofundado na outra.
    - `nota` vai para os apontamentos da aula atual e `nota_outra` para os da outra aula. O estudante faz resumos em papel a partir dos apontamentos de cada aula, e a nota diz-lhe onde resumir este assunto, para não o resumir duas vezes nem resumir a versão mais fraca:
      - Na aula que o explica pior (só por alto, ou sem os exemplos): "Não resumas isto aqui: está explicado melhor na Aula 2 (IVA, IRPF e tabelas)." Se esta aula disser alguma coisa que a outra não diz, diz o que vale a pena guardar daqui.
      - Na aula que o explica melhor: "Resume-o aqui: inclui o que a Aula 1 viu por alto (os três tributos)."
      - Se cada aula acrescentar coisas diferentes, diz o que fica em cada uma: "Complementa a Aula 1: aqui os tipos de sociedade, lá a definição de empresa."
    - Uma ou duas frases curtas por nota. A outra aula nomeia-se como no início do seu título ("Clase 2", "Lecture 2"…), sem link (a app junta-o). Toda na língua dos apontamentos: nos exemplos acima só conta a ideia, não as palavras.
    - Listas vazias se não houver ligações.
    - Nas explicações, refere as outras aulas pelo título ("na aula de Autovalores…"), nunca pelo id (A1).
    - Explicações, conceitos e notas em {{lingua_apontamentos}}, mas os nomes dos campos do JSON ficam exatamente como no exemplo, em português ("explicacao", não "explicacion"). Dentro dos textos, usa « » em vez de aspas. Sem LaTeX nem Markdown: símbolos em Unicode (λ, Σ, ∇, A⁻¹, x²).
    """
}

// MARK: - Perguntar à cadeira

/// O painel de perguntas, mas sobre a cadeira inteira: a ficha e os apontamentos de todas as aulas. As respostas
/// levam ao momento de uma aula com `[Aula 3 · 12:34](#<aula>@12:34)` ou a uma secção com `[Título](#<aula>/<secção>)`.
/// A conversa fica em `<cadeira>/perguntas-cadeira.json`.
extension Estudo {
    /// Uma aula no pedido das perguntas à cadeira.
    struct AulaNaCadeira: Sendable {
        var numero: Int
        var titulo: String
        var data: Date
        var prefixo: String
        var apontamentos: String
    }

    /// Quanto dos apontamentos das aulas vai com cada pergunta (~100 mil tokens). Passando disto, as aulas mais
    /// antigas vão só com o resumo e os títulos.
    nonisolated static let limiteCadeira = 360_000

    /// A mesma chave das perguntas de uma aula, mas com a pasta da cadeira (nunca coincidem).
    static func chave(_ cadeira: Cadeira) -> Chave { Chave(pasta: cadeira.pasta.standardizedFileURL.path, tipo: .pergunta) }

    func emCurso(_ cadeira: Cadeira) -> EmCurso? { emCurso[Self.chave(cadeira)] }
    func erro(_ cadeira: Cadeira) -> String? { erros[Self.chave(cadeira)] }
    func cancelar(_ cadeira: Cadeira) { emCurso[Self.chave(cadeira)]?.tarefa?.cancel() }

    func apagarPerguntas(_ cadeira: Cadeira) {
        try? Disco.escreverPerguntasCadeira([], em: cadeira.pasta)
        versao += 1
    }

    func perguntar(_ pergunta: String, aCadeira cadeira: Cadeira) {
        let chave = Self.chave(cadeira)
        guard emCurso[chave] == nil else { return }
        erros[chave] = nil
        let gerador: NotesGenerator
        do { gerador = try definicoes.gerador(esforco: .medium) } catch {
            erros[chave] = error.localizedDescription
            return
        }
        let anteriores = Disco.lerPerguntasCadeira(cadeira.pasta)
        let aulas = cadeira.aulas.filter(\.temApontamentos).sorted { $0.meta.data < $1.meta.data }.map {
            AulaNaCadeira(numero: library.numeroDaAula($0), titulo: $0.meta.titulo, data: $0.meta.data,
                          prefixo: Self.prefixoLink($0.pasta), apontamentos: Disco.lerApontamentos($0.pasta) ?? "")
        }
        guard !aulas.isEmpty else {
            erros[chave] = "Esta cadeira ainda não tem aulas com apontamentos."
            return
        }
        var blocos: [BlocoConteudo] = []
        if let ficha = FichaCadeira.lerFicha(cadeira.pasta) {
            blocos.append(.texto("Ficha da cadeira:\n\n<ficha>\n\(ficha)\n</ficha>"))
        }
        blocos.append(.texto(Self.aulasParaCadeira(aulas, limite: Self.limiteCadeira)))
        if !anteriores.isEmpty {
            let conversa = anteriores.suffix(8).map { "Pergunta: \($0.pergunta)\n\nResposta: \($0.resposta)" }.joined(separator: "\n\n---\n\n")
            blocos.append(.texto("Perguntas anteriores sobre esta cadeira:\n\n<conversa>\n\(conversa)\n</conversa>"))
        }
        blocos.append(.texto("Pergunta do estudante:\n\n\(pergunta)"))
        let sistema = definicoes.prompt(Self.sistemaCadeira, idioma: definicoes.idioma(da: cadeira))
        emCurso[chave] = EmCurso(pergunta: pergunta)
        emCurso[chave]?.tarefa = Task {
            do {
                let r = try await gerador.gerar(
                    sistema: sistema, conteudo: blocos,
                    aoRecomecar: { [weak self] in self?.emCurso[chave]?.texto = "" },
                    aoReceber: { [weak self] pedaco in self?.emCurso[chave]?.texto += pedaco },
                    aoRepetir: { _, _, _ in })
                let nova = PerguntaAula(pergunta: pergunta, resposta: r.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
                try Disco.juntarPerguntaCadeira(nova, em: cadeira.pasta)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { erros[chave] = error.localizedDescription }
            }
            emCurso[chave] = nil
            versao += 1
        }
    }

    /// As aulas por ordem. As mais recentes vão completas enquanto couberem em `limite`; as outras só com o resumo e os títulos.
    nonisolated static func aulasParaCadeira(_ aulas: [AulaNaCadeira], limite: Int) -> String {
        var sobra = limite
        var completas: Set<String> = []
        for a in aulas.reversed() where a.apontamentos.count <= sobra {
            completas.insert(a.prefixo)
            sobra -= a.apontamentos.count
        }
        let lista = aulas.map { aulaParaCadeira($0, completa: completas.contains($0.prefixo)) }.joined(separator: "\n\n")
        let como = completas.count == aulas.count ? "com os apontamentos completos" : "as mais recentes com os apontamentos completos, as mais antigas só com o resumo e os títulos"
        return "Aulas da cadeira, por ordem (\(como)):\n\n\(lista)"
    }

    /// Uma aula no pedido: o número, o prefixo dos links, as secções já como links e os apontamentos com os [mm:ss]
    /// (são eles que dão os links para o momento da aula). Sem as imagens dos slides.
    nonisolated static func aulaParaCadeira(_ a: AulaNaCadeira, completa: Bool) -> String {
        let quando = a.data.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_PT")))
        let seccoes = Seccoes.lista(a.apontamentos).map { s in
            Seccoes.Seccao(indice: s.indice, nivel: s.nivel, titulo: s.titulo, ancora: "\(a.prefixo)/\(s.ancora)")
        }
        let corpo = (completa ? a.apontamentos : esqueleto(a.apontamentos))
            .components(separatedBy: .newlines).filter { !$0.hasPrefix("![") }.joined(separator: "\n")
        return """
        <aula numero="\(a.numero)" titulo="\(a.titulo)" data="\(quando)" prefixo="\(a.prefixo)">
        <seccoes>
        \(Seccoes.indice(seccoes))
        </seccoes>
        <\(completa ? "apontamentos" : "resumo")>
        \(corpo.trimmingCharacters(in: .whitespacesAndNewlines))
        </\(completa ? "apontamentos" : "resumo")>
        </aula>
        """
    }

    /// Para onde leva um link de uma resposta sobre a cadeira: `#<aula>@mm:ss` ao momento da transcrição,
    /// `#<aula>/<secção>` à secção dos apontamentos. nil se a aula não for desta cadeira.
    nonisolated static func destino(_ ligacao: LigacaoSeccao, aulas: [Aula]) -> DestinoAula? {
        var ancora = ligacao.ancora.removingPercentEncoding ?? ligacao.ancora
        if ancora.hasPrefix("#") { ancora.removeFirst() }
        let separador = ancora.firstIndex { $0 == "@" || $0 == "/" }
        guard let separador else { return nil }
        let prefixo = String(ancora[..<separador])
        let resto = String(ancora[ancora.index(after: separador)...])
        guard let aula = aulas.first(where: { prefixoLink($0.pasta) == prefixo }) else { return nil }
        if ancora[separador] == "@" {
            guard let tempo = Timestamp.parse(resto) else { return nil }
            return DestinoAula(pasta: aula.pasta, separador: .transcricao, tempo: tempo)
        }
        return DestinoAula(pasta: aula.pasta, separador: .apontamentos, seccao: LigacaoSeccao(ancora: resto, texto: ligacao.texto))
    }

    /// Com `{{contexto}}`, `{{idioma}}` e `{{regras_lingua}}` por substituir (`Definicoes.prompt`).
    static let sistemaCadeira = """
    Respondes às perguntas de um estudante sobre uma cadeira universitária inteira. {{contexto}} Recebes a ficha da cadeira e os apontamentos de cada aula (feitos a partir das aulas, em {{idioma}}; das mais antigas, às vezes, só o resumo e os títulos).

    ## Como responder
    - Responde diretamente à pergunta, de forma clara e curta, para quem está a estudar para o exame.
    - Baseia-te no que foi dado nas aulas e diz sempre de que aula vem ("na Aula 3, a professora…").
    - A matéria é muitas vezes dada aos bocados: se um assunto aparece em várias aulas, junta-as por ordem e diz o que cada uma acrescenta.
    - Para levar o estudante a um momento de uma aula, põe um link assim: [Aula 3 · 12:34](#<prefixo>@12:34), com o prefixo da aula e um minuto [mm:ss] que esteja nos apontamentos dessa aula. Para uma secção, usa o link tal como vem na lista de secções da aula, ex.: [Límites](#<prefixo>/limites). Só links destas listas e minutos que existam: nunca inventes.
    - Nunca escrevas um [mm:ss] sozinho, sem o link: aqui não se sabe de que aula é.
    - Podes acrescentar explicações que o professor não deu, se forem conhecimento padrão e estiverem certas; põe-nas num bloco `> 💡 **Explicação extra:** ...`.
    - Se nenhuma aula falar do assunto, diz isso claramente antes de responder com conhecimento geral. Nunca inventes o que o professor disse.
    - Sem cabeçalho com a pergunta: começa logo pela resposta.

    ## Língua e formato
    {{regras_lingua}}
    - Markdown. Matemática em LaTeX: `$...$` inline e `$$...$$` em bloco, numa linha própria.
    """
}

extension Disco {
    static let perguntasCadeiraJSON = "perguntas-cadeira.json"

    static func lerPerguntasCadeira(_ pasta: URL) -> [PerguntaAula] {
        guard let dados = try? lerDados(pasta.appending(path: perguntasCadeiraJSON)) else { return [] }
        return (try? decoder.decode([PerguntaAula].self, from: dados)) ?? []
    }

    static func escreverPerguntasCadeira(_ perguntas: [PerguntaAula], em pasta: URL) throws {
        let url = pasta.appending(path: perguntasCadeiraJSON)
        if perguntas.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try gravar(encoder.encode(perguntas), em: url)
    }

    /// Junta uma resposta às anteriores. Se o ficheiro existe mas não se lê (ainda no iCloud, estragado),
    /// lança um erro em vez de o substituir só pela resposta nova.
    static func juntarPerguntaCadeira(_ nova: PerguntaAula, em pasta: URL) throws {
        guard let anteriores = lerListaPerguntas(pasta.appending(path: perguntasCadeiraJSON)) else { throw ErroPerguntas.porLer }
        try escreverPerguntasCadeira(anteriores + [nova], em: pasta)
    }
}
