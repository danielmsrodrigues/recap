import Foundation
import Synchronization
@preconcurrency import WhisperKit

enum ErroTranscricao: LocalizedError {
    case modeloNaoCarregado
    case semFala

    var errorDescription: String? {
        switch self {
        case .modeloNaoCarregado: "O modelo do Whisper não está carregado."
        case .semFala: "O Whisper não encontrou fala no áudio."
        }
    }
}

/// Bandeira partilhada entre threads (o callback do WhisperKit corre fora do actor).
final class Sinal: Sendable {
    private let estado = Mutex(false)
    var ativo: Bool { estado.withLock { $0 } }
    func ativar() { estado.withLock { $0 = true } }
}

/// Transcrição com o WhisperKit. O modelo fica em memória entre aulas da fila.
actor Transcriber {
    private var kit: WhisperKit?
    private var modeloCarregado: WhisperModelo?

    /// Carrega o modelo já descarregado. Na primeira vez o Core ML especializa-o para este Mac, o que demora.
    func carregar(_ modelo: WhisperModelo, store: ModelStore) async throws {
        if modeloCarregado == modelo, kit != nil { return }
        kit = nil
        let config = WhisperKitConfig(
            modelFolder: store.pasta(modelo).path,
            tokenizerFolder: store.base,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        kit = try await WhisperKit(config)
        modeloCarregado = modelo
    }

    func libertar() {
        kit = nil
        modeloCarregado = nil
    }

    /// Descodificadores em paralelo. O WhisperKit usa 16 no Mac; medido com 20 min de áudio:
    /// 16 → 1544 MB / 86 s, 4 → 1245 MB / 120 s, 2 → 905 MB / 119 s, 1 → 737 MB / 149 s.
    /// Corre em segundo plano, por isso a RAM pesa mais do que a velocidade. (Variável só para os testes.)
    nonisolated(unsafe) static var descodificadores = 1

    /// Segundos de áudio em memória de cada vez (≈ 19 MB). Uma aula de 90 min nunca está toda em RAM.
    static let janela: Double = 300
    /// Margem lida depois da janela para encontrar um silêncio onde cortar sem partir palavras.
    static let margemCorte: Double = 20

    /// Transcreve um ficheiro de áudio ou vídeo por blocos, cortados em pausas da fala.
    func transcrever(
        ficheiro url: URL,
        duracao: Double,
        glossario: String,
        progresso: @escaping @Sendable (Double) -> Void
    ) async throws -> [Segmento] {
        let taxa = AudioExtractor.taxa
        var inicio = 0.0
        var todos: [Segmento] = []
        while inicio < duracao - 0.5 {
            try Task.checkCancellation()
            let pedido = min(duracao - inicio, Self.janela + Self.margemCorte)
            var amostras = try await AudioExtractor().extrair(de: url, inicio: inicio, duracao: pedido).amostras
            if inicio + pedido < duracao - 0.5 {
                let corte = Self.pontoDeCorte(amostras, minimo: Int(Self.janela * taxa))
                amostras.removeLast(amostras.count - corte)
            }
            let base = inicio, tamanho = Double(amostras.count) / taxa
            let segs = try await transcreverBloco(amostras, glossario: glossario) { p in
                progresso(min(1, (base + p * tamanho) / duracao))
            }
            todos += segs.map { Segmento(inicio: $0.inicio + base, fim: $0.fim + base, texto: $0.texto) }
            inicio += max(tamanho, 1)
        }
        let segmentos = Self.limpar(todos)
        guard !segmentos.isEmpty else { throw ErroTranscricao.semFala }
        progresso(1)
        return segmentos
    }

    /// Para áudio já em memória (testes e áudios curtos).
    func transcrever(
        _ amostras: [Float],
        glossario: String,
        progresso: @escaping @Sendable (Double) -> Void
    ) async throws -> [Segmento] {
        let segmentos = Self.limpar(try await transcreverBloco(amostras, glossario: glossario, progresso: progresso))
        guard !segmentos.isEmpty else { throw ErroTranscricao.semFala }
        progresso(1)
        return segmentos
    }

    private func transcreverBloco(
        _ amostras: [Float],
        glossario: String,
        progresso: @escaping @Sendable (Double) -> Void
    ) async throws -> [Segmento] {
        guard let kit else { throw ErroTranscricao.modeloNaoCarregado }

        var opcoes = DecodingOptions(
            task: .transcribe,
            language: "es",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            concurrentWorkerCount: Self.descodificadores,
            chunkingStrategy: .vad
        )
        let prompt = Self.promptDoGlossario(glossario)
        if !prompt.isEmpty, let tokenizer = kit.tokenizer {
            // O decoder só aceita ~224 tokens de prompt e fica com os últimos; cortamos nós para manter os primeiros termos.
            let tokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            opcoes.promptTokens = Array(tokens.prefix(200))
        }

        let cancelado = Sinal()
        // O WhisperKit só troca este Progress no fim da transcrição; o objeto é thread-safe.
        let progressoKit = kit.progress
        let monitor = Task {
            while !Task.isCancelled {
                progresso(progressoKit.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { monitor.cancel() }

        let resultados = try await withTaskCancellationHandler {
            try await kit.transcribe(audioArray: amostras, decodeOptions: opcoes) { _ in
                cancelado.ativo ? false : nil
            }
        } onCancel: {
            cancelado.ativar()
        }
        try Task.checkCancellation()

        return resultados.flatMap(\.segments).map {
            Segmento(inicio: Double($0.start), fim: Double($0.end), texto: $0.text)
        }
    }

    // MARK: Auxiliares (puros, testados)

    /// Índice da pausa mais funda depois de `minimo` (janelas de 100 ms), para cortar o bloco entre frases.
    static func pontoDeCorte(_ amostras: [Float], minimo: Int) -> Int {
        let passo = Int(AudioExtractor.taxa / 10)
        guard amostras.count > minimo + passo else { return amostras.count }
        var melhor = minimo, menor = Float.greatestFiniteMagnitude
        var i = minimo
        while i + passo <= amostras.count {
            var soma: Float = 0
            for j in i..<(i + passo) { soma += amostras[j] * amostras[j] }
            if soma < menor { menor = soma; melhor = i + passo / 2 }
            i += passo
        }
        return melhor
    }

    /// Só os termos em espanhol: cada linha do glossário até ao primeiro `=`, `→`, `->` ou `|`.
    static func promptDoGlossario(_ glossario: String) -> String {
        let termos = glossario
            .split(whereSeparator: \.isNewline)
            .compactMap { linha -> String? in
                var termo = String(linha)
                for separador in ["=", "→", "->", "|"] {
                    if let r = termo.range(of: separador) { termo = String(termo[..<r.lowerBound]) }
                }
                termo = termo.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-*•")))
                return termo.isEmpty ? nil : termo
            }
        return termos.isEmpty ? "" : "Glosario: " + termos.joined(separator: ", ") + "."
    }

    /// Frases que o Whisper inventa em silêncio quando transcreve espanhol.
    private static let alucinacoes = [
        "amara.org", "subtítulos realizados por", "subtitulado por", "subtítulos por la comunidad",
        "¡suscríbete", "gracias por ver el video",
    ]

    /// Segmentos que, sozinhos, costumam ser o Whisper a preencher silêncio.
    private static let sozinhosEmSilencio: Set<String> = ["gracias.", "gracias", "¡gracias!", "gracias!", "...", "…"]

    /// Ordena, tira segmentos vazios ou alucinados e junta repetições consecutivas.
    static func limpar(_ segmentos: [Segmento]) -> [Segmento] {
        var saida: [Segmento] = []
        for var s in segmentos.sorted(by: { $0.inicio < $1.inicio }) {
            s.texto = s.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.texto.isEmpty else { continue }
            let minusculas = s.texto.lowercased()
            if alucinacoes.contains(where: minusculas.contains) || sozinhosEmSilencio.contains(minusculas) { continue }
            if let ultimo = saida.last, ultimo.texto == s.texto {
                saida[saida.count - 1].fim = max(ultimo.fim, s.fim)
                continue
            }
            saida.append(s)
        }
        return saida
    }
}
