import Foundation
import Observation

/// Uma pergunta feita sobre uma aula e a resposta do Claude (`perguntas.json`).
struct PerguntaAula: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var pergunta: String
    var resposta: String
    var data = Date.now
}


/// Como uma aula se liga às outras da cadeira (`ligacoes.json`), para a vista visual.
struct LigacoesAula: Codable, Sendable {
    enum Direcao: String, Codable, Sendable { case anterior, seguinte }

    struct Ligacao: Codable, Hashable, Sendable {
        /// Pasta da outra aula, relativa à raiz.
        var aula: String
        var direcao: Direcao
        var conceitos: [String]
        var explicacao: String
        /// `mm:ss` da aula atual onde a ligação aparece.
        var momento: String?
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

    /// O JSON que o Claude devolve, com as aulas identificadas por `A1`, `A2`…
    private struct Resposta: Decodable {
        struct L: Decodable { var aula: String; var direcao: String; var conceitos: [String]?; var explicacao: String; var momento: String? }
        struct T: Decodable { var tema: String; var aulas: [String]?; var explicacao: String }
        var ligacoes: [L]?
        var temas_comuns: [T]?
    }

    /// Lê a resposta do Claude (tolera texto ou ``` à volta do JSON) e troca os ids pelas pastas.
    static func daResposta(_ texto: String, aulas: [String: String]) throws -> LigacoesAula {
        guard let a = texto.firstIndex(of: "{"), let b = texto.lastIndex(of: "}"), a < b,
              let r = try? JSONDecoder().decode(Resposta.self, from: Data(texto[a...b].utf8))
        else { throw ErroLigacoes.formato }
        var ligacoes: [Ligacao] = []
        for l in r.ligacoes ?? [] {
            guard let pasta = aulas[l.aula], let d = Direcao(rawValue: l.direcao) else { continue }
            let limpo = l.momento?.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            let momento = limpo.flatMap { Timestamp.parse($0) != nil ? $0 : nil }
            // Uma só entrada por aula e direção (o Claude às vezes divide-a em duas).
            if let i = ligacoes.firstIndex(where: { $0.aula == pasta && $0.direcao == d }) {
                ligacoes[i].conceitos += (l.conceitos ?? []).filter { !ligacoes[i].conceitos.contains($0) }
                ligacoes[i].explicacao += " " + l.explicacao
                ligacoes[i].momento = ligacoes[i].momento ?? momento
            } else {
                ligacoes.append(Ligacao(aula: pasta, direcao: d, conceitos: l.conceitos ?? [], explicacao: l.explicacao, momento: momento))
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
        guard let dados = try? Data(contentsOf: pasta.appending(path: ligacoesJSON)) else { return nil }
        return try? decoder.decode(LigacoesAula.self, from: dados)
    }

    static func escreverLigacoes(_ l: LigacoesAula, em pasta: URL) throws {
        try encoder.encode(l).write(to: pasta.appending(path: ligacoesJSON), options: .atomic)
    }

    static func lerPerguntas(_ pasta: URL) -> [PerguntaAula] {
        guard let dados = try? Data(contentsOf: pasta.appending(path: perguntasJSON)) else { return [] }
        return (try? decoder.decode([PerguntaAula].self, from: dados)) ?? []
    }

    static func escreverPerguntas(_ perguntas: [PerguntaAula], em pasta: URL) throws {
        let url = pasta.appending(path: perguntasJSON)
        if perguntas.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try encoder.encode(perguntas).write(to: url, options: .atomic)
    }

    static func lerTexto(_ nome: String, em pasta: URL) -> String? {
        try? String(contentsOf: pasta.appending(path: nome), encoding: .utf8)
    }

    static func escreverTexto(_ texto: String, _ nome: String, em pasta: URL) throws {
        try texto.write(to: pasta.appending(path: nome), atomically: true, encoding: .utf8)
    }

    static func dataModificacao(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

extension ContextoAula {
    /// Tudo o que se sabe de uma aula, como no pedido dos apontamentos (o PDF do professor substitui as capturas).
    @MainActor
    static func carregar(_ aula: Aula, library: Library, transcricao: Transcricao) -> ContextoAula {
        let pdf = Disco.urlPDFProfessor(aula.pasta)
        let slides = pdf != nil ? [] : (Disco.lerSlides(aula.pasta) ?? []).compactMap { s in
            (try? Data(contentsOf: Disco.urlSlide(s, em: aula.pasta))).map { SlideComImagem(slide: s, jpeg: $0) }
        }
        return ContextoAula(cadeira: aula.cadeira, titulo: aula.meta.titulo, data: aula.meta.data,
                            glossario: library.cadeira(nome: aula.cadeira)?.meta.glossario ?? "",
                            transcricao: transcricao, slides: slides,
                            pdfProfessor: pdf.flatMap { try? Data(contentsOf: $0) })
    }
}

/// Perguntar à aula, exercícios extra e ligações entre aulas. Os pedidos vivem aqui (e não nas vistas)
/// para continuarem quando se muda de aula ou de separador.
@MainActor @Observable
final class Estudo {
    enum Tipo: String, Sendable { case pergunta, exercicios, ligacoes }

    struct Chave: Hashable { var pasta: String; var tipo: Tipo }

    struct EmCurso {
        var texto = ""
        /// A pergunta a que se está a responder.
        var pergunta: String?
        var tarefa: Task<Void, Never>?
    }

    private(set) var emCurso: [Chave: EmCurso] = [:]
    private(set) var erros: [Chave: String] = [:]
    /// Muda quando um ficheiro de estudo é gravado (as vistas voltam a ler do disco).
    private(set) var versao = 0

    private let library: Library
    private let definicoes: Definicoes

    init(library: Library, definicoes: Definicoes) {
        self.library = library
        self.definicoes = definicoes
    }

    static func chave(_ aula: Aula, _ tipo: Tipo) -> Chave { Chave(pasta: aula.pasta.standardizedFileURL.path, tipo: tipo) }

    func emCurso(_ aula: Aula, _ tipo: Tipo) -> EmCurso? { emCurso[Self.chave(aula, tipo)] }
    func erro(_ aula: Aula, _ tipo: Tipo) -> String? { erros[Self.chave(aula, tipo)] }
    func limparErro(_ aula: Aula, _ tipo: Tipo) { erros[Self.chave(aula, tipo)] = nil }

    func cancelar(_ aula: Aula, _ tipo: Tipo) {
        emCurso[Self.chave(aula, tipo)]?.tarefa?.cancel()
    }

    // MARK: Pedidos

    func perguntar(_ pergunta: String, sobre aula: Aula) {
        let anteriores = Disco.lerPerguntas(aula.pasta)
        executar(aula, .pergunta, pergunta: pergunta, esforco: .medium,
                 sistema: Self.sistemaPerguntas) { contexto in
            var blocos = contexto.map(NotesGenerator.materiais) ?? []
            if let notas = Disco.lerApontamentos(aula.pasta) {
                blocos.append(.texto("Apontamentos já feitos desta aula (PT-PT):\n\n<apontamentos>\n\(notas)\n</apontamentos>"))
            }
            if !anteriores.isEmpty {
                let conversa = anteriores.suffix(8).map { "Pergunta: \($0.pergunta)\n\nResposta: \($0.resposta)" }
                    .joined(separator: "\n\n---\n\n")
                blocos.append(.texto("Perguntas anteriores sobre esta aula:\n\n<conversa>\n\(conversa)\n</conversa>"))
            }
            blocos.append(.texto("Pergunta do estudante:\n\n\(pergunta)"))
            return blocos
        } concluir: { texto in
            try Disco.escreverPerguntas(Disco.lerPerguntas(aula.pasta) + [PerguntaAula(pergunta: pergunta, resposta: texto)], em: aula.pasta)
        }
    }

    func gerarExercicios(_ aula: Aula) {
        executar(aula, .exercicios, sistema: Self.sistemaExercicios) { contexto in
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

    func gerarLigacoes(_ aula: Aula) {
        let outras = outrasAulas(de: aula)
        guard let notas = Disco.lerApontamentos(aula.pasta) else { return }
        guard !outras.isEmpty else {
            erros[Self.chave(aula, .ligacoes)] = "Ainda não há outras aulas com apontamentos em \(aula.cadeira)."
            return
        }
        let raiz = library.raiz
        executar(aula, .ligacoes, comTranscricao: false, sistema: Self.sistemaLigacoes) { _ in
            let lista = outras.enumerated().map { i, o in
                let data = o.meta.data.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_PT")))
                return "<aula id=\"A\(i + 1)\" titulo=\"\(o.meta.titulo)\" data=\"\(data)\"\(o.meta.data < aula.meta.data ? " anterior" : " seguinte")>\n\(Self.esqueleto(Disco.lerApontamentos(o.pasta) ?? ""))\n</aula>"
            }.joined(separator: "\n\n")
            return [
                .texto("Cadeira: \(aula.cadeira)\nAula atual: \(aula.meta.titulo) (\(aula.meta.data.formatted(date: .long, time: .omitted)))\n\nApontamentos da aula atual:\n\n<apontamentos>\n\(notas)\n</apontamentos>"),
                .texto("Outras aulas da cadeira (resumo e temas de cada uma):\n\n\(lista)"),
                .texto("Devolve as ligações da aula atual com as outras em JSON, seguindo as instruções."),
            ]
        } concluir: { texto in
            let ids = Dictionary(uniqueKeysWithValues: outras.enumerated().map { ("A\($0 + 1)", Self.caminhoRelativo($1.pasta, raiz: raiz)) })
            try Disco.escreverLigacoes(LigacoesAula.daResposta(texto, aulas: ids), em: aula.pasta)
        }
    }

    /// As outras aulas da cadeira com apontamentos, por data.
    func outrasAulas(de aula: Aula) -> [Aula] {
        (library.cadeira(nome: aula.cadeira)?.aulas ?? [])
            .filter { $0.temApontamentos && !$0.pasta.mesmoCaminho(aula.pasta) }
            .sorted { $0.meta.data < $1.meta.data }
    }

    /// As ligações já não refletem as aulas da cadeira (aulas novas ou apontamentos alterados depois).
    func ligacoesDesatualizadas(_ aula: Aula) -> Bool {
        guard let gerado = Disco.dataModificacao(aula.pasta.appending(path: Disco.ligacoesJSON)) else { return false }
        return ([aula] + outrasAulas(de: aula)).contains {
            (Disco.dataModificacao($0.pasta.appending(path: Disco.apontamentosMD)) ?? .distantPast) > gerado
        }
    }

    func apagarPerguntas(_ aula: Aula) {
        try? Disco.escreverPerguntas([], em: aula.pasta)
        versao += 1
    }

    // MARK: Execução

    private func executar(
        _ aula: Aula, _ tipo: Tipo, pergunta: String? = nil, comTranscricao: Bool = true, esforco: Esforco? = nil,
        sistema: String,
        conteudo: @MainActor (ContextoAula?) -> [BlocoConteudo],
        concluir: @escaping @MainActor (String) throws -> Void
    ) {
        let chave = Self.chave(aula, tipo)
        guard emCurso[chave] == nil else { return }
        erros[chave] = nil
        let gerador: NotesGenerator
        do { gerador = try definicoes.gerador(esforco: esforco) } catch {
            erros[chave] = error.localizedDescription
            return
        }
        let transcricao = comTranscricao ? Disco.lerTranscricao(aula.pasta) : nil
        if comTranscricao && transcricao == nil {
            erros[chave] = "Esta aula ainda não tem transcrição."
            return
        }
        // Só se lê a transcrição, os slides e o PDF quando o pedido precisa deles.
        let contexto = comTranscricao ? transcricao.map { ContextoAula.carregar(aula, library: library, transcricao: $0) } : nil
        let blocos = conteudo(contexto)
        emCurso[chave] = EmCurso(pergunta: pergunta)
        emCurso[chave]?.tarefa = Task {
            do {
                let r = try await gerador.gerar(
                    sistema: sistema, conteudo: blocos,
                    aoRecomecar: { [weak self] in self?.emCurso[chave]?.texto = "" },
                    aoReceber: { [weak self] pedaco in self?.emCurso[chave]?.texto += pedaco },
                    aoRepetir: { _, _, _ in }
                )
                try concluir(r.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { erros[chave] = error.localizedDescription }
            }
            emCurso[chave] = nil
            versao += 1
        }
    }

    // MARK: Ajudas

    /// O resumo e os títulos dos apontamentos de uma aula (o suficiente para as ligações, sem gastar tokens).
    nonisolated static func esqueleto(_ md: String) -> String {
        var linhas: [String] = []
        var noResumo = false
        for linha in md.components(separatedBy: .newlines) {
            if linha.hasPrefix("#") {
                noResumo = linha.lowercased().hasPrefix("## resumo")
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
    - Português europeu (PT-PT), nunca do Brasil ("ficheiro", "ecrã", "utilizador", "valor próprio", "vetor próprio").
    - Markdown. Matemática em LaTeX: `$...$` inline e `$$...$$` em bloco, numa linha própria.
    - Momentos da aula como [mm:ss], só com timestamps que existam na transcrição.
    """

    static let sistemaPerguntas = """
    Respondes às perguntas de um estudante sobre uma aula universitária que ele assistiu (Ciência de Dados e IA, numa universidade espanhola; muita matemática). Recebes a transcrição automática (espanhol, com erros do reconhecimento de voz), os slides ou o PDF do professor, e os apontamentos já feitos.

    ## Como responder
    - Responde diretamente à pergunta, de forma clara e curta, para quem está a ver a matéria pela primeira vez.
    - Baseia-te no que foi dito e mostrado na aula, e indica onde: "aos [12:34] o professor…".
    - Se a pergunta for sobre um trecho confuso, diz o que o professor disse (podes citar a frase em espanhol e traduzi-la) e explica-o.
    - Podes acrescentar explicações que o professor não deu, se forem conhecimento padrão e estiverem certas; põe-nas num bloco `> 💡 **Explicação extra:** ...`.
    - Se a aula não falar do assunto, diz isso claramente antes de responder com conhecimento geral.
    - Nunca inventes o que o professor disse.
    - Sem cabeçalho com a pergunta: começa logo pela resposta.

    \(comum)
    """

    static let sistemaExercicios = """
    Crias exercícios de treino sobre uma aula universitária (Ciência de Dados e IA, numa universidade espanhola; muita matemática). Recebes a transcrição, os slides ou o PDF do professor, e os apontamentos.

    ## Exercícios
    - 6 a 8 exercícios parecidos com os exemplos e exercícios da aula, com os mesmos métodos e notação, por ordem crescente de dificuldade.
    - Só matéria dada nesta aula: nada de métodos, teoremas ou conceitos que não apareceram.
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

    static let sistemaLigacoes = """
    Mostras a um estudante como uma aula se liga às outras aulas da mesma cadeira. Recebes os apontamentos completos da aula atual e, de cada outra aula, o resumo e os temas, com um id (A1, A2…) e a indicação "anterior" ou "seguinte".

    ## O que procurar
    - Só ligações reais entre conteúdos: conceitos que a aula atual usa e que vieram de aulas anteriores, e conceitos da aula atual que são usados ou aprofundados em aulas seguintes.
    - Temas que aparecem em várias aulas.
    - Não inventes conteúdos que não estejam nos resumos ou nos temas.

    ## Resposta
    Devolve só JSON válido, sem texto antes nem depois e sem ```, neste formato:

    {
      "ligacoes": [
        {"aula": "A1", "direcao": "anterior", "conceitos": ["valor próprio", "polinómio característico"],
         "explicacao": "Uma ou duas frases: o que vem de onde e para que serve aqui.", "momento": "00:17"}
      ],
      "temas_comuns": [
        {"tema": "Descida do gradiente", "aulas": ["A1"], "explicacao": "Uma frase sobre como o tema aparece nas aulas."}
      ]
    }

    - `direcao`: "anterior" se o conteúdo vem dessa aula para a atual; "seguinte" se a aula atual prepara essa aula.
    - Uma entrada por aula e direção, com todos os conceitos dessa ligação (2 a 5 palavras cada).
    - `momento`: o mm:ss da aula atual onde a ligação aparece, tirado dos apontamentos, ou null.
    - Listas vazias se não houver ligações.
    - Nas explicações, refere as outras aulas pelo título ("na aula de Autovalores…"), nunca pelo id (A1).
    - Português europeu (PT-PT). Sem LaTeX nem Markdown: símbolos em Unicode (λ, Σ, ∇, A⁻¹, x²).
    """
}
