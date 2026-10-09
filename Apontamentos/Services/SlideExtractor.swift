import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision

struct ConfigSlides: Sendable {
    /// Segundos entre frames analisados.
    var intervalo: Double = 2
    /// Distância entre feature prints a partir da qual se considera outro slide.
    /// No vídeo de teste: o mesmo slide < 0,02; revelar linhas ~0,25; slides diferentes ≥ 0,63.
    var limiar: Double = 0.45
    var maximo = 40
    /// Lado maior das imagens guardadas.
    var ladoMaximo = 1280
    var regiao: RegiaoIgnorar = .automatica
    /// Multiplica os tempos guardados (capturas feitas a 1,5× ou 2× correspondem a mais tempo de aula).
    var escalaTempo: Double = 1
    /// Recorta a zona que muda ao longo da aula (o leitor de vídeo dentro da janela do browser),
    /// deixando de fora a barra do browser e as margens da página. Para as capturas em direto.
    var recortarZonaAtiva = false
}

/// De onde vêm os frames: um vídeo, ou as capturas feitas durante uma aula em direto.
protocol FonteFrames: Sendable {
    func duracao() async throws -> Double
    /// Tempos dos frames a analisar, mais ou menos a cada `intervalo` segundos.
    func tempos(intervalo: Double) async throws -> [Double]
    /// Percorre os frames por ordem, com o lado maior até `maxLado`.
    func percorrer(intervalo: Double, maxLado: Int, _ corpo: (Double, CGImage) async throws -> Void) async throws
    func frame(em t: Double, maxLado: Int) async throws -> CGImage
}

struct FonteVideo: FonteFrames {
    let url: URL

    func duracao() async throws -> Double { try await AVURLAsset(url: url).load(.duration).seconds }

    func tempos(intervalo: Double) async throws -> [Double] {
        guard try await !AVURLAsset(url: url).loadTracks(withMediaType: .video).isEmpty else { return [] }
        let d = try await duracao()
        guard d.isFinite, d > 0 else { return [] }
        return Array(stride(from: 0.0, to: d, by: intervalo))
    }

    func percorrer(intervalo: Double, maxLado: Int, _ corpo: (Double, CGImage) async throws -> Void) async throws {
        let tempos = try await tempos(intervalo: intervalo).map { CMTime(seconds: $0, preferredTimescale: 600) }
        let gerador = gerador(maxLado: maxLado, tolerancia: min(0.5, intervalo / 3))
        for await r in gerador.images(for: tempos) {
            try Task.checkCancellation()
            if case .success(let pedido, let imagem, _) = r { try await corpo(pedido.seconds, imagem) }
        }
    }

    func frame(em t: Double, maxLado: Int) async throws -> CGImage {
        try await gerador(maxLado: maxLado, tolerancia: 0).image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    private func gerador(maxLado: Int, tolerancia: Double) -> AVAssetImageGenerator {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: maxLado, height: maxLado)
        g.requestedTimeToleranceBefore = CMTime(seconds: tolerancia, preferredTimescale: 600)
        g.requestedTimeToleranceAfter = CMTime(seconds: tolerancia, preferredTimescale: 600)
        return g
    }
}

/// Só uma parte de cada frame (`zona`, normalizada, origem em cima à esquerda).
struct FonteRecortada<Base: FonteFrames>: FonteFrames {
    let base: Base
    let zona: CGRect

    func duracao() async throws -> Double { try await base.duracao() }
    func tempos(intervalo: Double) async throws -> [Double] { try await base.tempos(intervalo: intervalo) }

    /// Lê a base maior, para o recorte ficar com cerca de `maxLado`.
    private func ladoBase(_ maxLado: Int) -> Int { Int(Double(maxLado) / max(0.05, max(zona.width, zona.height))) }

    private func recortar(_ imagem: CGImage) -> CGImage {
        let w = Double(imagem.width), h = Double(imagem.height)
        return imagem.cropping(to: CGRect(x: zona.minX * w, y: zona.minY * h, width: zona.width * w, height: zona.height * h).integral) ?? imagem
    }

    func percorrer(intervalo: Double, maxLado: Int, _ corpo: (Double, CGImage) async throws -> Void) async throws {
        try await base.percorrer(intervalo: intervalo, maxLado: ladoBase(maxLado)) { t, imagem in try await corpo(t, recortar(imagem)) }
    }

    func frame(em t: Double, maxLado: Int) async throws -> CGImage {
        recortar(try await base.frame(em: t, maxLado: ladoBase(maxLado)))
    }
}

/// Pasta com capturas `<segundos>.jpg` (modo em direto).
struct FontePasta: FonteFrames {
    let pasta: URL

    static func nome(_ segundos: Double) -> String { String(format: "%09.1f.jpg", segundos) }

    private func ficheiros() -> [(Double, URL)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { u in Double(u.deletingPathExtension().lastPathComponent).map { ($0, u) } }
            .sorted { $0.0 < $1.0 }
    }

    func duracao() async throws -> Double { (ficheiros().last?.0 ?? 0) + 2 }

    private func escolhidos(intervalo: Double) -> [(Double, URL)] {
        var ultimo = -Double.infinity
        return ficheiros().filter { t, _ in
            guard t - ultimo >= intervalo * 0.9 else { return false }
            ultimo = t
            return true
        }
    }

    func tempos(intervalo: Double) async throws -> [Double] { escolhidos(intervalo: intervalo).map(\.0) }

    func percorrer(intervalo: Double, maxLado: Int, _ corpo: (Double, CGImage) async throws -> Void) async throws {
        for (t, url) in escolhidos(intervalo: intervalo) {
            try Task.checkCancellation()
            if let imagem = Self.ler(url, maxLado: maxLado) { try await corpo(t, imagem) }
        }
    }

    func frame(em t: Double, maxLado: Int) async throws -> CGImage {
        guard let (_, url) = ficheiros().min(by: { abs($0.0 - t) < abs($1.0 - t) }), let img = Self.ler(url, maxLado: maxLado) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return img
    }

    static func ler(_ url: URL, maxLado: Int) -> CGImage? {
        guard let fonte = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(fonte, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLado,
        ] as CFDictionary)
    }
}

/// Extrai os slides de uma gravação de ecrã (Zoom, Collaborate…).
///
/// 1. Se a região for automática, encontra a zona que mexe sempre (a câmara do professor) numa grelha de baixa resolução.
/// 2. Percorre o vídeo a cada `intervalo` segundos, tapa essa zona e compara feature prints do Vision.
///    Cada troço estável é um candidato; fica a última imagem do troço, a mais completa se o professor
///    for revelando linhas (uma revelação muda pouco o feature print e fica no mesmo troço).
/// 3. Descarta troços que não parecem slides (muito movimento ou sem texto: só a câmara) e slides repetidos.
/// 4. Guarda até `maximo` imagens JPEG em `slides/` e devolve a lista.
struct SlideExtractor: Sendable {
    var config = ConfigSlides()

    /// Grelha de luminância usada para medir movimento.
    static let colunas = 32, linhas = 18
    /// Diferença de luminância (0–1) a partir da qual uma célula mudou.
    static let limiarCelula: Float = 0.08

    func extrair(de video: URL, para pasta: URL, progresso: @escaping @Sendable (Double) -> Void) async throws -> [Slide] {
        try await extrair(de: FonteVideo(url: video), para: pasta, progresso: progresso)
    }

    @concurrent
    func extrair(de fonte: some FonteFrames, para pasta: URL, progresso: @escaping @Sendable (Double) -> Void) async throws -> [Slide] {
        if config.recortarZonaAtiva {
            var grelhas: [[Float]] = []
            try await fonte.percorrer(intervalo: config.intervalo, maxLado: 640) { _, imagem in
                grelhas.append(Self.grelha(imagem, colunas: Self.colunasFinas, linhas: Self.linhasFinas))
            }
            if let zona = Self.zonaAtiva(grelhas) {
                var semRecorte = self
                semRecorte.config.recortarZonaAtiva = false
                return try await semRecorte.extrair(de: FonteRecortada(base: fonte, zona: zona), para: pasta, progresso: progresso)
            }
        }
        let duracao = try await fonte.duracao()
        let total = try await fonte.tempos(intervalo: config.intervalo).count
        guard duracao.isFinite, duracao > 0, total > 0 else { return [] }

        // 1. Zona a tapar
        var mascara = config.regiao.retangulos
        let pesoPassagem: Double = config.regiao == .automatica ? 0.35 : 0
        if config.regiao == .automatica {
            var grelhas: [[Float]] = []
            try await fonte.percorrer(intervalo: config.intervalo, maxLado: 640) { _, imagem in
                grelhas.append(Self.grelha(imagem))
                if grelhas.count % 10 == 0 { progresso(pesoPassagem * Double(grelhas.count) / Double(total)) }
            }
            mascara = Self.zonaEmMovimento(grelhas)
        }
        let celulasMascara = Self.celulas(de: mascara)

        // 2. Troços estáveis
        let pedidoFP = GenerateImageFeaturePrintRequest()
        var candidatos: [Candidato] = []
        var atual: Candidato?
        var grelhaAnterior: [Float]?
        var i = 0
        try await fonte.percorrer(intervalo: config.intervalo, maxLado: 640) { t, imagem in
            i += 1
            if i % 10 == 0 { progresso(pesoPassagem + (0.9 - pesoPassagem) * Double(i) / Double(total)) }
            let grelha = Self.grelha(imagem)
            let movimento = grelhaAnterior.map { Self.fracaoMudada($0, grelha, ignorar: celulasMascara) } ?? 0
            grelhaAnterior = grelha
            let tapada = Self.tapar(imagem, mascara)
            let fp = try await pedidoFP.perform(on: tapada)

            if var c = atual, try fp.distance(to: c.referencia) <= config.limiar {
                c.fim = t + config.intervalo
                c.ultima = tapada
                c.ultimaFP = fp
                c.ultimoTempo = t
                c.movimento += movimento
                c.amostras += 1
                atual = c
            } else {
                if let c = atual { candidatos.append(c) }
                atual = Candidato(inicio: t, fim: t + config.intervalo, referencia: fp, ultima: tapada, ultimaFP: fp, ultimoTempo: t)
            }
        }
        if let c = atual { candidatos.append(c) }

        // 3. Filtrar e juntar
        var escolhidos: [Escolhido] = []
        for c in candidatos where c.amostras >= 2 && c.movimento / Double(c.amostras) < 0.12 {
            // Em resolução completa: em 640 px o texto de um ecrã partilhado fica pequeno demais para o Vision.
            let grande = Self.tapar(try await fonte.frame(em: c.ultimoTempo, maxLado: config.ladoMaximo), mascara)
            guard try await Self.pareceSlide(grande) else { continue }
            let novo = Escolhido(inicio: c.inicio, fim: min(c.fim, duracao), tempoImagem: c.ultimoTempo, fp: c.ultimaFP)

            // Já apareceu antes: só regista a reaparição.
            // Mais exigente do que a deteção de mudança: o mesmo slide dá < 0,02, slides parecidos (mesmo modelo,
            // texto diferente) podem ficar abaixo do limiar, sobretudo com capturas comprimidas.
            if let k = try escolhidos.firstIndex(where: { try $0.fp.distance(to: novo.fp) <= config.limiar * 0.5 }) {
                escolhidos[k].reaparicoes.append(novo.inicio)
                continue
            }
            escolhidos.append(novo)
        }
        if escolhidos.count > config.maximo {
            escolhidos = Array(escolhidos.sorted { $0.fim - $0.inicio > $1.fim - $1.inicio }.prefix(config.maximo))
                .sorted { $0.inicio < $1.inicio }
        }

        // 4. Guardar em resolução final
        let pastaSlides = pasta.appending(path: "slides", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: pastaSlides)
        try FileManager.default.createDirectory(at: pastaSlides, withIntermediateDirectories: true)
        var slides: [Slide] = []
        let k = config.escalaTempo
        for (n, e) in escolhidos.enumerated() {
            try Task.checkCancellation()
            let imagem = try await fonte.frame(em: e.tempoImagem, maxLado: config.ladoMaximo)
            let nome = String(format: "slide_%02d_%@.jpg", n + 1, Timestamp.format(e.inicio * k).replacingOccurrences(of: ":", with: "-"))
            try Self.gravarJPEG(imagem, em: pastaSlides.appending(path: nome))
            slides.append(Slide(ficheiro: nome, inicio: e.inicio * k, fim: e.fim * k, reaparicoes: e.reaparicoes.map { $0 * k }))
            progresso(0.9 + 0.1 * Double(n + 1) / Double(max(1, escolhidos.count)))
        }
        try Disco.escreverSlides(slides, em: pasta)
        progresso(1)
        return slides
    }

    // MARK: Tipos internos

    private struct Candidato {
        var inicio: Double
        var fim: Double
        var referencia: FeaturePrintObservation
        var ultima: CGImage
        var ultimaFP: FeaturePrintObservation
        var ultimoTempo: Double
        var movimento = 0.0
        var amostras = 1
    }

    private struct Escolhido {
        var inicio: Double
        var fim: Double
        var tempoImagem: Double
        var fp: FeaturePrintObservation
        var reaparicoes: [Double] = []
    }

    // MARK: Auxiliares (puros, testados)

    /// Luminância média em `colunas × linhas` células, de cima para baixo.
    /// Slide, ecrã partilhado ou quadro, e não a câmara do professor nem um ecrã vazio.
    /// Texto chega; sem texto legível (letras pequenas num ecrã partilhado), basta não haver uma cara grande
    /// (na câmara a cara ocupa 2–4% da imagem; a miniatura da câmara num canto já está tapada).
    static func pareceSlide(_ imagem: CGImage) async throws -> Bool {
        if try await DetectTextRectanglesRequest().perform(on: imagem).count >= 2 { return true }
        let caras = try await DetectFaceRectanglesRequest().perform(on: imagem)
        if caras.contains(where: { $0.boundingBox.width * $0.boundingBox.height > 0.01 }) { return false }
        return !CapturaAudio.uniforme(imagem) && !CapturaAudio.centroPreto(imagem)
    }

    /// Grelha fina para encontrar a zona ativa: numa página web partilhada, as mudanças são letras sobre branco
    /// e quase não mexem na média de uma célula grande.
    static let colunasFinas = 96, linhasFinas = 54

    /// A zona que muda durante a aula (o vídeo dentro da janela do browser), normalizada com a origem em cima
    /// à esquerda. nil se for quase tudo (já é só o vídeo), se nada mudar ou se não houver dados suficientes.
    static func zonaAtiva(_ grelhas: [[Float]]) -> CGRect? {
        let (c, l) = (colunasFinas, linhasFinas)
        guard grelhas.count >= 3 else { return nil }
        var mudou = [Bool](repeating: false, count: c * l)
        for (a, b) in zip(grelhas, grelhas.dropFirst()) {
            for i in a.indices where abs(a[i] - b[i]) > 0.03 { mudou[i] = true }
        }
        // Ignora células isoladas (um ícone que pisca não alarga a zona).
        func vizinhaMudou(_ x: Int, _ y: Int) -> Bool {
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let vx = x + dx, vy = y + dy
                if vx >= 0, vx < c, vy >= 0, vy < l, mudou[vy * c + vx] { return true }
            } }
            return false
        }
        var x0 = c, y0 = l, x1 = -1, y1 = -1
        for y in 0..<l {
            for x in 0..<c where mudou[y * c + x] && vizinhaMudou(x, y) {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= x0, y1 >= y0 else { return nil }
        // Uma célula de margem, para não cortar as bordas do slide.
        x0 = max(0, x0 - 1); y0 = max(0, y0 - 1); x1 = min(c - 1, x1 + 1); y1 = min(l - 1, y1 + 1)
        let zona = CGRect(x: Double(x0) / Double(c), y: Double(y0) / Double(l),
                          width: Double(x1 - x0 + 1) / Double(c), height: Double(y1 - y0 + 1) / Double(l))
        let area = zona.width * zona.height
        return area > 0.85 || area < 0.05 ? nil : zona
    }

    static func grelha(_ imagem: CGImage, colunas: Int = colunas, linhas: Int = linhas) -> [Float] {
        var px = [UInt8](repeating: 0, count: colunas * linhas)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: colunas, height: linhas, bitsPerComponent: 8, bytesPerRow: colunas,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.interpolationQuality = .medium
            ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: colunas, height: linhas))
        }
        return px.map { Float($0) / 255 }
    }

    /// Índices das células cobertas pelos retângulos normalizados.
    static func celulas(de retangulos: [CGRect]) -> Set<Int> {
        var s = Set<Int>()
        for y in 0..<linhas {
            for x in 0..<colunas {
                let centro = CGPoint(x: (Double(x) + 0.5) / Double(colunas), y: (Double(y) + 0.5) / Double(linhas))
                if retangulos.contains(where: { $0.contains(centro) }) { s.insert(y * colunas + x) }
            }
        }
        return s
    }

    static func fracaoMudada(_ a: [Float], _ b: [Float], ignorar: Set<Int>) -> Double {
        var mudadas = 0, total = 0
        for i in a.indices where !ignorar.contains(i) {
            total += 1
            if abs(a[i] - b[i]) > limiarCelula { mudadas += 1 }
        }
        return total == 0 ? 0 : Double(mudadas) / Double(total)
    }

    /// A zona que muda em muitos pares de frames consecutivos, ignorando os pares em que muda quase tudo
    /// (troca de slide ou só câmara). Devolve retângulos normalizados, com uma célula de margem.
    static func zonaEmMovimento(_ grelhas: [[Float]]) -> [CGRect] {
        guard grelhas.count >= 3 else { return [] }
        var contagem = [Int](repeating: 0, count: colunas * linhas)
        var pares = 0
        for (a, b) in zip(grelhas, grelhas.dropFirst()) {
            let mudadas = a.indices.filter { abs(a[$0] - b[$0]) > limiarCelula }
            guard Double(mudadas.count) / Double(a.count) < 0.3 else { continue }
            pares += 1
            for i in mudadas { contagem[i] += 1 }
        }
        guard pares >= 2 else { return [] }
        var ativas = Set(contagem.indices.filter { Double(contagem[$0]) / Double(pares) > 0.25 })
        // Margem de uma célula à volta.
        for i in ativas {
            let x = i % colunas, y = i / colunas
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if (0..<colunas).contains(nx), (0..<linhas).contains(ny) { ativas.insert(ny * colunas + nx) }
            } }
        }
        // Se "mexe" mais de 40% do ecrã, não é uma miniatura: melhor não tapar nada.
        guard !ativas.isEmpty, Double(ativas.count) / Double(colunas * linhas) <= 0.4 else { return [] }
        let w = 1 / Double(colunas), h = 1 / Double(linhas)
        return ativas.sorted().map { CGRect(x: Double($0 % colunas) * w, y: Double($0 / colunas) * h, width: w, height: h) }
    }

    /// Pinta de preto os retângulos normalizados (origem em cima à esquerda).
    static func tapar(_ imagem: CGImage, _ retangulos: [CGRect]) -> CGImage {
        guard !retangulos.isEmpty,
              let ctx = CGContext(data: nil, width: imagem.width, height: imagem.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return imagem }
        let w = Double(imagem.width), h = Double(imagem.height)
        ctx.draw(imagem, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for r in retangulos {
            ctx.fill(CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h))
        }
        return ctx.makeImage() ?? imagem
    }

    static func gravarJPEG(_ imagem: CGImage, em url: URL, qualidade: Double = 0.82) throws {
        guard let destino = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destino, imagem, [kCGImageDestinationLossyCompressionQuality: qualidade] as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { throw CocoaError(.fileWriteUnknown) }
    }
}
