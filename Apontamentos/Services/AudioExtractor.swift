import AVFoundation

enum ErroVideo: LocalizedError, Equatable {
    case formatoNaoSuportado(extensao: String)
    case semAudio
    case leitura(String)

    var errorDescription: String? {
        switch self {
        case .formatoNaoSuportado(let ext) where ext == "mkv":
            "O macOS não consegue ler este .mkv. Converte-o para .mp4 (por exemplo, com o HandBrake) e volta a largá-lo."
        case .formatoNaoSuportado(let ext):
            "O macOS não consegue ler este vídeo (.\(ext)). Converte-o para .mp4 e volta a largá-lo."
        case .semAudio:
            "O vídeo não tem faixa de áudio."
        case .leitura(let detalhe):
            "Falhou a leitura do áudio do vídeo: \(detalhe)"
        }
    }
}

/// Extrai o áudio de um vídeo para PCM Float32, 16 kHz, mono (o formato do Whisper).
struct AudioExtractor: Sendable {
    static let taxa: Double = 16_000

    struct Resultado: Sendable {
        var amostras: [Float]
        var duracao: Double
    }

    /// Verifica se o AVFoundation consegue abrir o vídeo, sem ler o áudio.
    static func validar(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let legivel = (try? await asset.load(.isReadable)) ?? false
        guard legivel else { throw ErroVideo.formatoNaoSuportado(extensao: url.pathExtension.lowercased()) }
        let faixas = try await asset.loadTracks(withMediaType: .audio)
        guard !faixas.isEmpty else { throw ErroVideo.semAudio }
    }

    /// Duração do áudio, validando que o ficheiro se lê e tem som.
    static func duracao(_ url: URL) async throws -> Double {
        try await validar(url)
        let d = try await AVURLAsset(url: url).load(.duration).seconds
        guard d.isFinite, d > 0 else { throw ErroVideo.leitura("duração desconhecida") }
        return d
    }

    /// Lê o áudio inteiro, ou só o troço `inicio..<inicio+duracao` (para transcrever por blocos sem ter tudo em memória).
    @concurrent
    func extrair(de url: URL, inicio: Double = 0, duracao trecho: Double? = nil) async throws -> Resultado {
        let asset = AVURLAsset(url: url)
        let legivel = (try? await asset.load(.isReadable)) ?? false
        guard legivel else { throw ErroVideo.formatoNaoSuportado(extensao: url.pathExtension.lowercased()) }
        let total = try await asset.load(.duration).seconds
        let faixas = try await asset.loadTracks(withMediaType: .audio)
        guard !faixas.isEmpty else { throw ErroVideo.semAudio }
        let duracao = trecho.map { min($0, total - inicio) } ?? (total - inicio)

        let leitor: AVAssetReader
        do { leitor = try AVAssetReader(asset: asset) } catch { throw ErroVideo.leitura(error.localizedDescription) }
        if inicio > 0 || trecho != nil {
            leitor.timeRange = CMTimeRange(start: CMTime(seconds: inicio, preferredTimescale: 48_000),
                                           duration: CMTime(seconds: duracao, preferredTimescale: 48_000))
        }

        // O AVAssetReader converte a taxa e mistura as faixas para mono.
        let saida = AVAssetReaderAudioMixOutput(audioTracks: faixas, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.taxa,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        saida.alwaysCopiesSampleData = false
        guard leitor.canAdd(saida) else { throw ErroVideo.leitura("saída de áudio incompatível") }
        leitor.add(saida)
        guard leitor.startReading() else {
            throw ErroVideo.leitura(leitor.error?.localizedDescription ?? "não foi possível começar a leitura")
        }

        var amostras = [Float]()
        if duracao.isFinite, duracao > 0 { amostras.reserveCapacity(Int(duracao * Self.taxa) + Int(Self.taxa)) }

        while let buffer = saida.copyNextSampleBuffer() {
            if Task.isCancelled {
                leitor.cancelReading()
                throw CancellationError()
            }
            guard let bloco = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let bytes = CMBlockBufferGetDataLength(bloco)
            let n = bytes / MemoryLayout<Float>.size
            guard n > 0 else { continue }
            let inicio = amostras.count
            amostras.append(contentsOf: repeatElement(0, count: n))
            let estado = amostras.withUnsafeMutableBytes { destino in
                CMBlockBufferCopyDataBytes(bloco, atOffset: 0, dataLength: n * MemoryLayout<Float>.size,
                                           destination: destino.baseAddress! + inicio * MemoryLayout<Float>.size)
            }
            guard estado == kCMBlockBufferNoErr else { throw ErroVideo.leitura("erro \(estado) ao copiar o áudio") }

        }

        if leitor.status == .failed {
            throw ErroVideo.leitura(leitor.error?.localizedDescription ?? "erro desconhecido")
        }
        return Resultado(amostras: amostras, duracao: duracao.isFinite ? duracao : Double(amostras.count) / Self.taxa)
    }
}
