import Foundation
import Observation

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

/// Pesquisa em todas as aulas: títulos, apontamentos (PT) e transcrições (ES), sem distinguir maiúsculas nem acentos.
/// Lê os ficheiros a cada pesquisa em vez de manter um índice em memória.
enum Pesquisa {
    struct AulaRef: Sendable {
        var pasta: URL
        var titulo: String
        var cadeira: String
        var data: Date
    }

    static let maximoPorAula = 4
    static let maximoTotal = 200
    private static let opcoes: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    @concurrent
    static func procurar(_ termo: String, em aulas: [AulaRef]) async -> [ResultadoPesquisa] {
        let palavras = termo.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !palavras.isEmpty else { return [] }
        var resultados: [ResultadoPesquisa] = []
        for aula in aulas.sorted(by: { $0.data > $1.data }) {
            if Task.isCancelled || resultados.count >= maximoTotal { break }
            func juntar(_ onde: ResultadoPesquisa.Onde, _ texto: String) {
                resultados.append(ResultadoPesquisa(pasta: aula.pasta, titulo: aula.titulo, cadeira: aula.cadeira,
                                                    data: aula.data, onde: onde, trecho: trecho(texto, palavras)))
            }
            var nesta = 0
            if contem(aula.titulo, palavras) { juntar(.titulo, aula.titulo); nesta += 1 }
            if let md = Disco.lerApontamentos(aula.pasta) {
                for linha in md.components(separatedBy: .newlines) where nesta < maximoPorAula && contem(linha, palavras) {
                    juntar(.apontamentos, limparMarkdown(linha))
                    nesta += 1
                }
            }
            if let t = Disco.lerTranscricao(aula.pasta) {
                for s in t.segmentos where nesta < maximoPorAula + 2 && contem(s.texto, palavras) {
                    juntar(.transcricao(s.inicio), s.texto)
                    nesta += 1
                }
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
