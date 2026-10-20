import Foundation
import Observation
import Synchronization

/// Separadores da vista de uma aula.
enum SeparadorAula: String, CaseIterable, Identifiable, Sendable {
    case apontamentos = "Apontamentos"
    case exercicios = "Exercícios"
    case ligacoes = "Ligações"
    case transcricao = "Transcrição"
    case slides = "Slides"
    var id: String { rawValue }
}

/// Pedido para abrir uma aula num sítio concreto (resultado da pesquisa, link de outra aula).
struct DestinoAula: Equatable, Sendable {
    var pasta: URL
    var separador: SeparadorAula
    /// Segundo da transcrição a mostrar.
    var tempo: Double?
    /// Texto a realçar: o primeiro que existir na página (um pedaço da frase, depois só a palavra).
    var termos: [String] = []
    /// Secção dos apontamentos a mostrar (link numa resposta do painel das perguntas).
    var seccao: LigacaoSeccao?
    var id = UUID()
}

@MainActor @Observable
final class Navegacao {
    var destino: DestinoAula?
}

struct ResultadoPesquisa: Identifiable, Sendable {
    enum Onde: Sendable, Equatable {
        case titulo
        case apontamentos
        case transcricao(Double)
        /// Na ficha "Sobre a cadeira" (`pasta` é o ficheiro da ficha).
        case ficha
    }

    var id = UUID()
    var pasta: URL
    var titulo: String
    var cadeira: String
    var data: Date
    var onde: Onde
    /// O trecho onde aparece, já cortado à volta da primeira palavra.
    var trecho: String
}

/// Pesquisa em todas as aulas e nas fichas das cadeiras: títulos, apontamentos (PT), transcrições (ES) e
/// "Sobre a cadeira", sem distinguir maiúsculas nem acentos.
/// Cada aula fica em memória já sem acentos nem maiúsculas, e só é relida quando o ficheiro muda: ler e
/// descodificar todas as transcrições (JSON de MB) a cada tecla demorava segundos com muitas aulas.
enum Pesquisa {
    /// Uma linha (ou segmento) como está no ficheiro e como se compara.
    struct Linha: Sendable {
        var texto: String
        var dobrado: String
        /// Segundos, nos segmentos da transcrição.
        var inicio: Double?
    }

    struct Indexada: Sendable {
        var modificado: Date?
        var linhas: [Linha]
    }

    private static let indice = Mutex<[String: Indexada]>([:])

    /// As linhas de um ficheiro, do índice se não mudou desde a última leitura.
    private static func linhas(de url: URL, ler: () -> [Linha]) -> [Linha] {
        let chave = url.path
        let modificado = Disco.dataModificacao(url)
        if let feita = indice.withLock({ $0[chave] }), feita.modificado == modificado, modificado != nil { return feita.linhas }
        let novas = modificado == nil ? [] : ler()
        indice.withLock { cache in
            if cache.count > 2000 { cache.removeAll(keepingCapacity: true) }
            cache[chave] = Indexada(modificado: modificado, linhas: novas)
        }
        return novas
    }

    static func dobrar(_ texto: String) -> String {
        texto.folding(options: opcoes, locale: nil)
    }

    private static func contem(_ linha: Linha, _ dobradas: [String]) -> Bool {
        dobradas.allSatisfy { linha.dobrado.contains($0) }
    }

    struct AulaRef: Sendable {
        var pasta: URL
        var titulo: String
        var cadeira: String
        var data: Date
    }

    struct FichaRef: Sendable {
        /// O ficheiro da ficha (`FichaCadeira.url`).
        var url: URL
        var cadeira: String
    }

    static let maximoPorAula = 4
    static let maximoTotal = 200
    private static let opcoes: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    @concurrent
    static func procurar(_ termo: String, em aulas: [AulaRef], fichas: [FichaRef] = []) async -> [ResultadoPesquisa] {
        let palavras = termo.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !palavras.isEmpty else { return [] }
        let dobradas = palavras.map(dobrar)
        var resultados: [ResultadoPesquisa] = []
        // As fichas primeiro: é lá que estão datas, avaliação e regras, o que mais se procura assim.
        for f in fichas {
            guard let md = try? String(contentsOf: f.url, encoding: .utf8) else { continue }
            let linhas = md.components(separatedBy: .newlines).filter { !$0.hasPrefix("# ") && contem($0, palavras) }
            for linha in linhas.prefix(maximoPorAula) {
                resultados.append(ResultadoPesquisa(pasta: f.url, titulo: FichaCadeira.tituloSeccao, cadeira: f.cadeira,
                                                    data: .distantFuture, onde: .ficha, trecho: trecho(limparMarkdown(linha), palavras)))
            }
        }
        for aula in aulas.sorted(by: { $0.data > $1.data }) {
            if Task.isCancelled || resultados.count >= maximoTotal { break }
            func juntar(_ onde: ResultadoPesquisa.Onde, _ texto: String) {
                resultados.append(ResultadoPesquisa(pasta: aula.pasta, titulo: aula.titulo, cadeira: aula.cadeira,
                                                    data: aula.data, onde: onde, trecho: trecho(texto, palavras)))
            }
            var nesta = 0
            if contem(aula.titulo, palavras) { juntar(.titulo, aula.titulo); nesta += 1 }
            let apontamentos = linhas(de: aula.pasta.appending(path: Disco.apontamentosMD)) {
                (Disco.lerApontamentos(aula.pasta) ?? "").components(separatedBy: .newlines).map { Linha(texto: $0, dobrado: dobrar($0)) }
            }
            for linha in apontamentos where nesta < maximoPorAula && contem(linha, dobradas) {
                juntar(.apontamentos, limparMarkdown(linha.texto))
                nesta += 1
            }
            let segmentos = linhas(de: aula.pasta.appending(path: Disco.transcricaoJSON)) {
                (Disco.lerTranscricao(aula.pasta)?.segmentos ?? []).map { Linha(texto: $0.texto, dobrado: dobrar($0.texto), inicio: $0.inicio) }
            }
            for s in segmentos where nesta < maximoPorAula + 2 && contem(s, dobradas) {
                juntar(.transcricao(s.inicio ?? 0), s.texto)
                nesta += 1
            }
        }
        return resultados
    }

    static func contem(_ texto: String, _ palavras: [String]) -> Bool {
        palavras.allSatisfy { texto.range(of: $0, options: opcoes) != nil }
    }

    /// Até ~140 caracteres à volta da primeira palavra encontrada.
    static func trecho(_ texto: String, _ palavras: [String]) -> String {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard t.count > 140, let r = palavras.lazy.compactMap({ t.range(of: $0, options: opcoes) }).first else { return t }
        let inicio = t.index(r.lowerBound, offsetBy: -50, limitedBy: t.startIndex) ?? t.startIndex
        let fim = t.index(inicio, offsetBy: 140, limitedBy: t.endIndex) ?? t.endIndex
        return (inicio > t.startIndex ? "…" : "") + t[inicio..<fim] + (fim < t.endIndex ? "…" : "")
    }

    private static let simbolos: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
        "sigma": "σ", "Sigma": "Σ", "pi": "π", "eta": "η", "nabla": "∇", "partial": "∂", "times": "×", "cdot": "·",
        "leq": "≤", "geq": "≥", "neq": "≠", "approx": "≈", "in": "∈", "infty": "∞", "to": "→", "rightarrow": "→", "sum": "Σ",
    ]

    /// Tira os marcadores de Markdown do início da linha e simplifica o LaTeX (`$\lambda_1$` → `λ1`), para mostrar o trecho.
    static func limparMarkdown(_ linha: String) -> String {
        var l = Substring(linha)
        while let c = l.first, "#>-*+ \t".contains(c) { l = l.dropFirst() }
        var t = String(l).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "$", with: "")
        t = t.replacing(/\\([A-Za-z]+)/) { m in simbolos[String(m.1)] ?? String(m.1) }
        return t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "\\", with: "")
    }

    /// O texto a procurar na página para chegar ao sítio certo: a palavra e as seguintes, até a uma fórmula,
    /// e depois só a palavra (a primeira ocorrência pode ser noutro parágrafo).
    static func termosParaRealcar(_ trecho: String, _ palavras: [String]) -> [String] {
        guard let r = realces(trecho, palavras).min(by: { $0.lowerBound < $1.lowerBound }) else { return palavras.prefix(1).map { $0 } }
        let palavra = String(trecho[r])
        var frase = ""
        for c in trecho[r.lowerBound...].prefix(45) {
            if "λμσαβγδεθπη∇∂×·≤≥≠≈∈∞→Σ()[]=+^/|…".contains(c) { break }
            frase.append(c)
        }
        if frase.count == 45, let espaco = frase.lastIndex(of: " ") { frase = String(frase[..<espaco]) }
        frase = frase.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return frase.count > palavra.count + 8 ? [frase, palavra] : [palavra]
    }

    /// Partes do trecho com as palavras procuradas (para as mostrar a negrito).
    static func realces(_ texto: String, _ palavras: [String]) -> [Range<String.Index>] {
        var r: [Range<String.Index>] = []
        for p in palavras where !p.isEmpty {
            var desde = texto.startIndex
            while let achado = texto.range(of: p, options: opcoes, range: desde..<texto.endIndex) {
                r.append(achado)
                desde = achado.upperBound
            }
        }
        return r
    }
}
