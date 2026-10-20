import Foundation
import Synchronization
@preconcurrency import SpeakerKit
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
    /// Separação por vozes (professor/alunos). nil = indisponível; a transcrição continua sem ela.
    private var vozes: SpeakerKit?
    /// Porque é que a separação por vozes não está disponível (para mostrar no progresso).
    private(set) var semVozes: String?

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

    /// Descarrega (só na primeira vez, ~30 MB) e carrega os modelos de separação por vozes.
    /// Se falhar (sem rede na primeira vez, por exemplo) a transcrição faz-se na mesma, sem professor/alunos.
    func carregarVozes(base: URL) async {
        guard vozes == nil else { return }
        do {
            let config = PyannoteConfig(
                modelDownloadConfig: ModelDownloadConfig(downloadBase: base.path, modelRepo: "argmaxinc/speakerkit-coreml"),
                download: true, load: true, verbose: false, logLevel: .error)
            vozes = try await SpeakerKit(config)
            semVozes = nil
        } catch {
            semVozes = error.localizedDescription
        }
    }

    func libertar() async {
        kit = nil
        modeloCarregado = nil
        // Limpar antes de suspender: um carregarVozes a meio não pode ver o modelo que está a sair.
        let saida = vozes
        vozes = nil
        await saida?.unloadModels()
    }

    /// Descodificadores em paralelo. O WhisperKit usa 16 no Mac; medido com 20 min de áudio:
    /// 16 → 1544 MB / 86 s, 4 → 1245 MB / 120 s, 2 → 905 MB / 119 s, 1 → 737 MB / 149 s.
    /// Corre em segundo plano (e agora ao mesmo tempo que os slides), por isso a RAM pesa mais do que a velocidade:
    /// 1 até 16 GB, 2 até 32 GB, 4 a partir daí. (Variável só para os testes.)
    nonisolated(unsafe) static var descodificadores: Int = {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return gb >= 32 ? 4 : (gb >= 16 ? 2 : 1)
    }()

    /// Segundos de áudio em memória de cada vez (≈ 19 MB). Uma aula de 90 min nunca está toda em RAM.
    static let janela: Double = 300
    /// Margem lida depois da janela para encontrar um silêncio onde cortar sem partir palavras.
    static let margemCorte: Double = 20

    /// Transcreve um ficheiro de áudio ou vídeo por blocos, cortados em pausas da fala.
    func transcrever(
        ficheiro url: URL,
        duracao: Double,
        glossario: String,
        idioma: IdiomaAula = .espanhol,
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
            let segs = try await transcreverBloco(amostras, glossario: glossario, idioma: idioma) { p in
                progresso(min(1, (base + p * tamanho) / duracao))
            }
            todos += segs.map { Segmento(inicio: $0.inicio + base, fim: $0.fim + base, texto: $0.texto, orador: $0.orador) }
            inicio += max(tamanho, 1)
        }
        let segmentos = Self.limpar(todos, idioma: idioma)
        guard !segmentos.isEmpty else { throw ErroTranscricao.semFala }
        progresso(1)
        return segmentos
    }

    /// Para áudio já em memória (testes e áudios curtos).
    func transcrever(
        _ amostras: [Float],
        glossario: String,
        idioma: IdiomaAula = .espanhol,
        progresso: @escaping @Sendable (Double) -> Void
    ) async throws -> [Segmento] {
        let segmentos = Self.limpar(try await transcreverBloco(amostras, glossario: glossario, idioma: idioma, progresso: progresso), idioma: idioma)
        guard !segmentos.isEmpty else { throw ErroTranscricao.semFala }
        progresso(1)
        return segmentos
    }

    private func transcreverBloco(
        _ amostras: [Float],
        glossario: String,
        idioma: IdiomaAula,
        progresso: @escaping @Sendable (Double) -> Void
    ) async throws -> [Segmento] {
        guard let kit else { throw ErroTranscricao.modeloNaoCarregado }

        var opcoes = DecodingOptions(
            task: .transcribe,
            language: idioma.rawValue,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            // As palavras com tempos servem para partir um segmento onde muda quem fala.
            wordTimestamps: vozes != nil,
            concurrentWorkerCount: Self.descodificadores,
            chunkingStrategy: .vad
        )
        let prompt = Self.promptDoGlossario(glossario, idioma: idioma)
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

        let segmentos = resultados.flatMap(\.segments).map { s in
            (segmento: Segmento(inicio: Double(s.start), fim: Double(s.end), texto: s.text),
             palavras: (s.words ?? []).map { Oradores.Palavra(texto: $0.word, inicio: Double($0.start), fim: Double($0.end)) })
        }
        return await marcarOradores(segmentos, amostras: amostras)
    }

    /// Professor ou aluno em cada segmento do bloco. Uma falha aqui não estraga a transcrição.
    private func marcarOradores(_ segmentos: [(segmento: Segmento, palavras: [Oradores.Palavra])], amostras: [Float]) async -> [Segmento] {
        guard let vozes, !segmentos.isEmpty else { return segmentos.map(\.segmento) }
        do {
            let resultado = try await vozes.diarize(audioArray: amostras)
            try Task.checkCancellation()
            let turnos = resultado.segments.compactMap { s in
                s.speaker.speakerId.map { Oradores.Turno(inicio: Double(s.startTime), fim: Double(s.endTime), voz: $0) }
            }
            guard let principal = Oradores.vozPrincipal(turnos) else { return segmentos.map(\.segmento) }
            let professor = Oradores.vozesDoProfessor(principal: principal, turnos: turnos) {
                resultado.centroidCosineDistance(between: $0, and: $1)
            }
            return Oradores.marcar(segmentos, turnos: turnos, professor: professor)
        } catch {
            return segmentos.map(\.segmento)
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

    /// Só os termos na língua da aula: cada linha do glossário até ao primeiro `=`, `→`, `->` ou `|`.
    static func promptDoGlossario(_ glossario: String, idioma: IdiomaAula = .espanhol) -> String {
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
        return termos.isEmpty ? "" : "\(idioma.glossario): " + termos.joined(separator: ", ") + "."
    }

    /// Ordena, tira segmentos vazios ou alucinados (as frases que o Whisper inventa em silêncio nessa língua)
    /// e junta repetições consecutivas.
    static func limpar(_ segmentos: [Segmento], idioma: IdiomaAula = .espanhol) -> [Segmento] {
        let alucinacoes = idioma.alucinacoes, sozinhos = idioma.sozinhosEmSilencio
        var saida: [Segmento] = []
        for var s in segmentos.sorted(by: { $0.inicio < $1.inicio }) {
            s.texto = s.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.texto.isEmpty else { continue }
            let minusculas = s.texto.lowercased()
            if alucinacoes.contains(where: minusculas.contains) || sozinhos.contains(minusculas) { continue }
            if let ultimo = saida.last, ultimo.texto == s.texto {
                saida[saida.count - 1].fim = max(ultimo.fim, s.fim)
                continue
            }
            saida.append(s)
        }
        return saida
    }
}
