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
    /// Recorta a zona do slide dentro da janela captada (ver `zonaDoSlide`), deixando de fora o chat,
    /// os participantes e o resto do ecrã. Para as capturas em direto; sem zona do slide não há slides.
    var recortarZonaAtiva = false
    /// Só aceita imagens com texto. Depois de recortar a zona do slide, uma imagem sem texto é a câmara
    /// ou o avatar de alguém, não um slide.
    var soComTexto = false
    /// Parte de cada imagem (normalizada, origem em cima à esquerda) onde se medem as trocas de slide; nil = toda.
    /// Guarda-se o vídeo inteiro, mas só o texto do meio muda de slide para slide.
    var zonaDeteccao: CGRect?
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
    /// Um `AVAssetImageGenerator` por tamanho: criar um (com o seu `AVURLAsset`) por cada frame pedido era o
    /// custo dominante ao validar e gravar dezenas de slides.
    private let geradores = CacheGeradores()

    private final class CacheGeradores: @unchecked Sendable {
        private let lock = NSLock()
        private var porChave: [String: AVAssetImageGenerator] = [:]

        func obter(_ chave: String, criar: () -> AVAssetImageGenerator) -> AVAssetImageGenerator {
            lock.lock(); defer { lock.unlock() }
            if let g = porChave[chave] { return g }
            let g = criar()
            porChave[chave] = g
            return g
        }
    }

    init(url: URL) { self.url = url }

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
        geradores.obter("\(maxLado)/\(tolerancia)") {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: maxLado, height: maxLado)
            g.requestedTimeToleranceBefore = CMTime(seconds: tolerancia, preferredTimescale: 600)
            g.requestedTimeToleranceAfter = CMTime(seconds: tolerancia, preferredTimescale: 600)
            return g
        }
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
    /// Fração de células da grelha fina que mudam de uma captura para a seguinte, num recorte do slide, a partir
    /// da qual é outro slide. Medido em capturas do PowerPoint partilhado: trocas de slide 0,11–0,49 (só o texto
    /// trocado, no mesmo modelo, 0,14); o cursor 0,002.
    static let mudancaDeSlide = 0.05
    /// Diferença de luminância (0–1) a partir da qual uma célula mudou.
    static let limiarCelula: Float = 0.08

    func extrair(de video: URL, para pasta: URL, progresso: @escaping @Sendable (Double) -> Void) async throws -> [Slide] {
        try await extrair(de: FonteVideo(url: video), para: pasta, progresso: progresso)
    }

    @concurrent
    func extrair(de fonte: some FonteFrames, para pasta: URL, progresso: @escaping @Sendable (Double) -> Void) async throws -> [Slide] {
        if config.recortarZonaAtiva {
            var grelhas: [[Float]] = []
            var aspeto = 16.0 / 9.0
            var variacao = Variacao(celulas: Self.colunasVideo * Self.linhasVideo)
            try await fonte.percorrer(intervalo: config.intervalo, maxLado: 640) { _, imagem in
                if grelhas.isEmpty { aspeto = Double(imagem.width) / Double(max(1, imagem.height)) }
                grelhas.append(Self.grelha(imagem, colunas: Self.colunasFinas, linhas: Self.linhasFinas))
                variacao.juntar(Self.grelha(imagem, colunas: Self.colunasVideo, linhas: Self.linhasVideo))
            }
            // Só a zona do slide (o que muda quando se troca de slide), alargada ao vídeo onde ele está. Sem ela
            // não há slides: a janela inteira, ou a zona que mais mexe, podia ser o chat ou as caras dos colegas.
            guard let zonas = Self.zonasDoSlide(grelhas, aspetoImagem: aspeto, variacao: variacao) else {
                try? FileManager.default.removeItem(at: pasta.appending(path: "slides", directoryHint: .isDirectory))
                try Disco.escreverSlides([], em: pasta)
                progresso(1)
                return []
            }
            var recortado = self
            recortado.config.recortarZonaAtiva = false
            recortado.config.soComTexto = true
            let (z, d) = zonas
            recortado.config.zonaDeteccao = CGRect(x: (d.minX - z.minX) / z.width, y: (d.minY - z.minY) / z.height,
                                                   width: d.width / z.width, height: d.height / z.height)
            return try await recortado.extrair(de: FonteRecortada(base: fonte, zona: z), para: pasta, progresso: progresso)
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
        var finaAnterior: [Float]?
        var i = 0
        try await fonte.percorrer(intervalo: config.intervalo, maxLado: 640) { t, imagem in
            i += 1
            if i % 10 == 0 { progresso(pesoPassagem + (0.9 - pesoPassagem) * Double(i) / Double(total)) }
            let grelha = Self.grelha(imagem)
            let movimento = grelhaAnterior.map { Self.fracaoMudada($0, grelha, ignorar: celulasMascara) } ?? 0
            grelhaAnterior = grelha
            let tapada = Self.tapar(imagem, mascara)
            let medida = config.zonaDeteccao.flatMap { z in
                tapada.cropping(to: CGRect(x: z.minX * Double(tapada.width), y: z.minY * Double(tapada.height),
                                           width: z.width * Double(tapada.width), height: z.height * Double(tapada.height)).integral)
            } ?? tapada
            let fp = try await pedidoFP.perform(on: medida)

            // Num recorte do slide, mudar de uma vez boa parte da imagem é outro slide, mesmo que o feature print
            // fique perto (slides do mesmo modelo, só com o texto diferente, dão 0,17–0,40). Na grelha fina:
            // na grossa, uma linha de texto trocada quase não mexe na média de cada célula.
            let fina = config.soComTexto ? Self.grelha(medida, colunas: Self.colunasFinas, linhas: Self.linhasFinas) : []
            let mudancaFina = finaAnterior.map { Self.fracaoMudada($0, fina, ignorar: []) } ?? 0
            finaAnterior = fina
            let trocou = config.soComTexto && mudancaFina >= Self.mudancaDeSlide
            if var c = atual, !trocou, try fp.distance(to: c.referencia) <= config.limiar {
                c.fim = t + config.intervalo
                c.ultima = tapada
                c.ultimaFP = fp
                c.ultimaFina = fina
                c.ultimoTempo = t
                c.movimento += movimento
                c.amostras += 1
                atual = c
            } else {
                if let c = atual { candidatos.append(c) }
                atual = Candidato(inicio: t, fim: t + config.intervalo, referencia: fp, ultima: tapada, ultimaFP: fp, ultimaFina: fina, ultimoTempo: t)
            }
        }
        if let c = atual { candidatos.append(c) }
        // Num recorte do slide, revelar uma linha de cada vez separa troços; junta-se cada troço ao seguinte
        // quando o seguinte só acrescenta conteúdo, e fica a imagem mais completa.
        if config.soComTexto {
            var juntos: [Candidato] = []
            for c in candidatos {
                if let anterior = juntos.last, Self.soAcrescenta(anterior.ultimaFina, c.ultimaFina) {
                    var novo = c
                    novo.inicio = anterior.inicio
                    novo.amostras += anterior.amostras
                    novo.movimento += anterior.movimento
                    juntos[juntos.count - 1] = novo
                } else {
                    juntos.append(c)
                }
            }
            candidatos = juntos
        }

        // 3. Filtrar e juntar. O frame em resolução completa grava-se já num ficheiro temporário: lê-lo outra vez
        // do vídeo no fim era a segunda passagem mais cara.
        let pastaSlides = pasta.appending(path: "slides", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: pastaSlides)
        try FileManager.default.createDirectory(at: pastaSlides, withIntermediateDirectories: true)
        var escolhidos: [Escolhido] = []
        for c in candidatos where c.amostras >= 2 && c.movimento / Double(c.amostras) < 0.12 {
            try Task.checkCancellation()
            // Em resolução completa: em 640 px o texto de um ecrã partilhado fica pequeno demais para o Vision.
            let frame = try await fonte.frame(em: c.ultimoTempo, maxLado: config.ladoMaximo)
            let grande = Self.tapar(frame, mascara)
            guard try await Self.pareceSlide(grande, soComTexto: config.soComTexto) else { continue }
            let novo = Escolhido(inicio: c.inicio, fim: min(c.fim, duracao), tempoImagem: c.ultimoTempo, fp: c.ultimaFP,
                                 grelha: c.ultimaFina, temporario: pastaSlides.appending(path: "tmp_\(escolhidos.count).jpg"))

            // Já apareceu antes: só regista a reaparição.
            // Mais exigente do que a deteção de mudança: o mesmo slide dá < 0,02, slides parecidos (mesmo modelo,
            // texto diferente) podem ficar abaixo do limiar, sobretudo com capturas comprimidas.
            // Num recorte do slide, o feature print de slides do mesmo modelo fica perto; exige-se também que a imagem
            // seja quase igual.
            let mesmo = { (e: Escolhido) throws -> Bool in
                try e.fp.distance(to: novo.fp) <= config.limiar * 0.5
                    && (!config.soComTexto || Self.fracaoMudada(e.grelha, novo.grelha, ignorar: []) < Self.mudancaDeSlide)
            }
            if let k = try escolhidos.firstIndex(where: mesmo) {
                escolhidos[k].reaparicoes.append(novo.inicio)
                continue
            }
            try Self.gravarJPEG(frame, em: novo.temporario)
            escolhidos.append(novo)
        }
        if escolhidos.count > config.maximo {
            escolhidos = Array(escolhidos.sorted { $0.fim - $0.inicio > $1.fim - $1.inicio }.prefix(config.maximo))
                .sorted { $0.inicio < $1.inicio }
        }

        // 4. Dar o nome final aos ficheiros (os que ficaram de fora do máximo são apagados)
        var slides: [Slide] = []
        let k = config.escalaTempo
        for (n, e) in escolhidos.enumerated() {
            let nome = String(format: "slide_%02d_%@.jpg", n + 1, Timestamp.format(e.inicio * k).replacingOccurrences(of: ":", with: "-"))
            try FileManager.default.moveItem(at: e.temporario, to: pastaSlides.appending(path: nome))
            slides.append(Slide(ficheiro: nome, inicio: e.inicio * k, fim: e.fim * k, reaparicoes: e.reaparicoes.map { $0 * k }))
            progresso(0.9 + 0.1 * Double(n + 1) / Double(max(1, escolhidos.count)))
        }
        for sobra in (try? FileManager.default.contentsOfDirectory(at: pastaSlides, includingPropertiesForKeys: nil)) ?? []
            where sobra.lastPathComponent.hasPrefix("tmp_") {
            try? FileManager.default.removeItem(at: sobra)
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
        /// Grelha fina da última imagem (só num recorte do slide).
        var ultimaFina: [Float]
        var ultimoTempo: Double
        var movimento = 0.0
        var amostras = 1
    }

    private struct Escolhido {
        var inicio: Double
        var fim: Double
        var tempoImagem: Double
        var fp: FeaturePrintObservation
        /// Grelha fina da imagem (só num recorte do slide).
        var grelha: [Float]
        /// O frame em resolução completa, já gravado.
        var temporario: URL
        var reaparicoes: [Double] = []
    }

    // MARK: Auxiliares (puros, testados)

    /// Luminância média em `colunas × linhas` células, de cima para baixo.
    /// Slide, ecrã partilhado ou quadro, e não a câmara do professor nem um ecrã vazio.
    /// Texto chega; sem texto legível (letras pequenas num ecrã partilhado), basta não haver uma cara grande
    /// (na câmara a cara ocupa 2–4% da imagem; a miniatura da câmara num canto já está tapada).
    /// `soComTexto`: sem texto não é slide (para recortes da zona do slide, onde a alternativa é a câmara).
    static func pareceSlide(_ imagem: CGImage, soComTexto: Bool = false) async throws -> Bool {
        if soComTexto {
            let caras = try await DetectFaceRectanglesRequest().perform(on: imagem)
            // A câmara do professor no lugar do slide: uma cara grande, mesmo que haja letras atrás (lombadas de livros).
            if caras.contains(where: { $0.boundingBox.width * $0.boundingBox.height > 0.02 }) { return false }
            // Reconhecer as letras (o detetor de retângulos de texto junta um slide cheio de texto num só bloco).
            var ocr = RecognizeTextRequest()
            ocr.recognitionLevel = .fast
            let letras = try await ocr.perform(on: imagem).compactMap { $0.topCandidates(1).first?.string }
                .joined().filter(\.isLetter).count
            return letras >= 12
        }
        if try await DetectTextRectanglesRequest().perform(on: imagem).count >= 2 { return true }
        let caras = try await DetectFaceRectanglesRequest().perform(on: imagem)
        if caras.contains(where: { $0.boundingBox.width * $0.boundingBox.height > 0.01 }) { return false }
        return !CapturaAudio.uniforme(imagem) && !CapturaAudio.centroPreto(imagem)
    }

    /// Grelha fina para encontrar a zona ativa: numa página web partilhada, as mudanças são letras sobre branco
    /// e quase não mexem na média de uma célula grande.
    static let colunasFinas = 96, linhasFinas = 54

    /// A zona do slide dentro da janela, a partir das trocas de slide, normalizada com a origem em cima à esquerda.
    ///
    /// Quando o professor partilha o ecrã inteiro (o PowerPoint em modo de edição, por exemplo), o slide é só
    /// uma parte da imagem; à volta ficam o friso do programa, o chat e a lista de participantes, que também
    /// mudam, mas aos bocadinhos (uma linha de cada vez). Uma troca de slide muda de uma vez um bloco grande
    /// e compacto. Junta-se o retângulo desse bloco em cada troca e fica a zona comum a boa parte delas,
    /// alargada para 16:9 (o cabeçalho e o rodapé dos slides não mudam, mas fazem parte do slide).
    /// nil se não houver trocas suficientes para decidir.
    /// `aspetoImagem`: largura/altura das capturas em píxeis (para o 16:9 ser em píxeis e não na grelha).
    static func zonaDoSlide(_ grelhas: [[Float]], aspetoImagem: Double = 16.0 / 9.0) -> CGRect? {
        zonasDoSlide(grelhas, aspetoImagem: aspetoImagem)?.deteccao
    }

    /// `deteccao` é a zona de `zonaDoSlide`. Com `variacao`, `video` é essa zona alargada até às bordas do vídeo
    /// (ver `alargarAoVideo`): nos slides do mesmo modelo só muda o texto do meio, e o cabeçalho, o rodapé e as
    /// margens ficavam de fora. É o que se guarda; as trocas de slide continuam a medir-se em `deteccao` (no slide
    /// inteiro, o texto que muda é uma fração menor da imagem). Sem `variacao`, as duas são iguais.
    static func zonasDoSlide(_ grelhas: [[Float]], aspetoImagem: Double = 16.0 / 9.0, variacao: Variacao? = nil)
        -> (video: CGRect, deteccao: CGRect)? {
        let (c, l) = (colunasFinas, linhasFinas)
        guard grelhas.count >= 3 else { return nil }
        var contagem = [Int](repeating: 0, count: c * l)
        var trocas = 0
        for (a, b) in zip(grelhas, grelhas.dropFirst()) {
            let mudou = a.indices.map { abs(a[$0] - b[$0]) > 0.03 }
            let fracao = Double(mudou.filter { $0 }.count) / Double(c * l)
            // Menos de 2%: uma linha no chat, o cursor. Mais de 60%: mudou o ecrã todo (câmara ↔ partilha).
            guard fracao > 0.02, fracao < 0.6, let caixa = maiorBloco(mudou, colunas: c, linhas: l, dilatar: 2) else { continue }
            guard Double(caixa.width * caixa.height) / Double(c * l) >= 0.04 else { continue }
            // O chat ou a lista de participantes a deslizar uma linha muda o painel todo de uma vez, como um slide:
            // não conta.
            guard !eDeslocamento(a, b, caixa: caixa, colunas: c) else { continue }
            trocas += 1
            for y in caixa.minY..<caixa.maxY { for x in caixa.minX..<caixa.maxX { contagem[y * c + x] += 1 } }
        }
        guard trocas >= 2 else { return nil }
        // Metade das trocas, no mínimo: a passagem câmara ↔ partilha também muda um bloco grande (o palco),
        // mas acontece poucas vezes; o slide muda em quase todas. Entre os blocos que ficam, o mais votado.
        let comum = contagem.map { $0 * 2 >= trocas }
        guard let caixa = maiorBloco(comum, colunas: c, linhas: l, dilatar: 0, pesos: contagem) else { return nil }
        let miolo = CGRect(x: Double(caixa.minX) / Double(c), y: Double(caixa.minY) / Double(l),
                           width: Double(caixa.width) / Double(c), height: Double(caixa.height) / Double(l))
        let area = miolo.width * miolo.height
        guard area >= 0.04, area <= 0.9 else { return nil }
        let inteira = CGRect(x: 0, y: 0, width: 1, height: 1)
        // 16:9 em píxeis, em coordenadas normalizadas.
        var deteccao = miolo
        let alvo = (16.0 / 9.0) / aspetoImagem
        if deteccao.width / deteccao.height > alvo {
            deteccao = deteccao.insetBy(dx: 0, dy: -(deteccao.width / alvo - deteccao.height) / 2)
        } else {
            deteccao = deteccao.insetBy(dx: -(deteccao.height * alvo - deteccao.width) / 2, dy: 0)
        }
        deteccao = deteccao.insetBy(dx: -0.01, dy: -0.01).intersection(inteira)
        guard let variacao else { return (deteccao, deteccao) }

        // Células que mudam com o miolo do slide: em boa parte das capturas em que mudam, o miolo também muda
        // (trocas de slide, a câmara a entrar e a sair). O chat e os participantes mudam noutras alturas.
        // Uma célula em que nunca se viu mudança na grelha fina (uma linha de texto fina, que só a grelha do vídeo
        // apanha) também conta: o que a trava é mudar noutras alturas.
        let celulasMiolo = (caixa.minY..<caixa.maxY).flatMap { y in (caixa.minX..<caixa.maxX).map { y * c + $0 } }
        var vezes = [Int](repeating: 0, count: c * l), comMiolo = vezes
        for (a, b) in zip(grelhas, grelhas.dropFirst()) {
            let mudou = a.indices.map { abs(a[$0] - b[$0]) > limiarCelula }
            let mioloMudou = Double(celulasMiolo.filter { mudou[$0] }.count) >= Double(celulasMiolo.count) * mudancaDeSlide
            for i in a.indices where mudou[i] {
                vezes[i] += 1
                if mioloMudou { comMiolo[i] += 1 }
            }
        }
        let video = alargarAoVideo(miolo, variacao, comOSlide: vezes.indices.map { comMiolo[$0] * 2 >= vezes[$0] })
        // Com a forma de um ecrã (de 5:4 a 16:9 e pouco mais) são as bordas do vídeo; senão não se encontraram,
        // e fica a zona de sempre.
        guard (1.2...1.9).contains(video.width / video.height * aspetoImagem) else { return (deteccao, deteccao) }
        let dentro = deteccao.intersection(video)
        return (video, dentro.isEmpty ? video : dentro)
    }

    /// Grelha para encontrar as bordas do vídeo: na grelha fina, uma célula (~20 px numa captura de 1920) é mais
    /// larga do que a faixa escura entre o vídeo e o chat.
    static let colunasVideo = 192, linhasVideo = 108

    /// Luminância mínima e máxima de cada célula ao longo das capturas.
    struct Variacao: Sendable {
        var minimo: [Float], maximo: [Float]
        init(celulas: Int) { (minimo, maximo) = ([Float](repeating: 1, count: celulas), [Float](repeating: 0, count: celulas)) }
        mutating func juntar(_ grelha: [Float]) {
            for i in grelha.indices { minimo[i] = min(minimo[i], grelha[i]); maximo[i] = max(maximo[i], grelha[i]) }
        }
    }

    /// Alarga a zona comum das trocas de slide (`nucleo`) até às bordas do vídeo partilhado.
    ///
    /// O vídeo (o ecrã do professor no leitor) muda em quase todo o lado ao longo da aula: os slides trocam, a câmara
    /// entra e sai. À volta, o palco do leitor fica sempre igual. Cresce-se lado a lado enquanto a linha de fora
    /// for vídeo: células que mudaram, e ao mesmo tempo que o miolo do slide (`comOSlide`, na grelha fina; o chat
    /// muda noutras alturas). Também se atravessa a margem do slide, que nunca muda mas tem a cor do fundo do slide:
    /// só a borda do palco, de outra cor, a trava.
    static func alargarAoVideo(_ nucleo: CGRect, _ v: Variacao, comOSlide: [Bool]) -> CGRect {
        let (c, l) = (colunasVideo, linhasVideo)
        guard v.minimo.count == c * l, comOSlide.count == colunasFinas * linhasFinas else { return nucleo }
        var x0 = max(0, Int((nucleo.minX * Double(c)).rounded(.down))), x1 = min(c, Int((nucleo.maxX * Double(c)).rounded(.up)))
        var y0 = max(0, Int((nucleo.minY * Double(l)).rounded(.down))), y1 = min(l, Int((nucleo.maxY * Double(l)).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return nucleo }
        func sincrona(_ x: Int, _ y: Int) -> Bool { comOSlide[(y * linhasFinas / l) * colunasFinas + x * colunasFinas / c] }
        func mudou(_ i: Int) -> Bool { v.maximo[i] - v.minimo[i] > 0.1 }
        func parado(_ i: Int) -> Bool { v.maximo[i] - v.minimo[i] < 0.06 }
        // Cor do fundo do slide: a mediana das células paradas no núcleo.
        let paradas = (y0..<y1).flatMap { y in (x0..<x1).map { y * c + $0 } }.filter(parado).map { v.maximo[$0] }.sorted()
        let fundo = paradas.isEmpty ? nil : paradas[paradas.count / 2]

        /// A linha ainda é do vídeo: muda com o slide em boa parte dela, ou é fundo parado com texto que muda com
        /// o slide (as linhas de baixo, que só alguns slides ocupam) ou fixo (o cabeçalho). Não é quando muda noutras
        /// alturas (o chat) ou está parada noutra cor (o palco do leitor). Numa coluna o texto fixo tem de ser pouco:
        /// o cabeçalho de um slide atravessa uma linha, mas numa coluna só cabem uma ou duas letras dele, e uma coluna
        /// com uma letra em cada linha é o início das mensagens do chat.
        func doVideo(_ celulas: [(Int, Int)], coluna: Bool) -> Bool {
            var comSlide = 0, outras = 0, deFundo = 0
            for (x, y) in celulas {
                let i = y * c + x
                if mudou(i) { if sincrona(x, y) { comSlide += 1 } else { outras += 1 } }
                else if let fundo, parado(i), abs(v.maximo[i] - fundo) < 0.08 { deFundo += 1 }
            }
            let n = celulas.count
            return outras * 5 < n && (comSlide * 10 >= n * 4 || (comSlide + deFundo) * 10 >= n * (coluna ? 9 : 7))
        }
        var cresceu = true
        while cresceu {
            cresceu = false
            if x0 > 0, doVideo((y0..<y1).map { (x0 - 1, $0) }, coluna: true) { x0 -= 1; cresceu = true }
            if x1 < c, doVideo((y0..<y1).map { (x1, $0) }, coluna: true) { x1 += 1; cresceu = true }
            if y0 > 0, doVideo((x0..<x1).map { ($0, y0 - 1) }, coluna: false) { y0 -= 1; cresceu = true }
            if y1 < l, doVideo((x0..<x1).map { ($0, y1) }, coluna: false) { y1 += 1; cresceu = true }
        }
        return CGRect(x: Double(x0) / Double(c), y: Double(y0) / Double(l), width: Double(x1 - x0) / Double(c), height: Double(y1 - y0) / Double(l))
    }

    struct Caixa: Equatable {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var width: Int { maxX - minX }
        var height: Int { maxY - minY }
    }

    /// O conteúdo da caixa em `b` é o de `a` deslocado na vertical (1 a 6 linhas da grelha): um painel a deslizar.
    static func eDeslocamento(_ a: [Float], _ b: [Float], caixa: Caixa, colunas c: Int) -> Bool {
        func diferentes(_ s: Int) -> Int {
            var n = 0
            for y in caixa.minY..<caixa.maxY where (caixa.minY..<caixa.maxY).contains(y + s) {
                for x in caixa.minX..<caixa.maxX where abs(a[(y + s) * c + x] - b[y * c + x]) > 0.03 { n += 1 }
            }
            return n
        }
        let semDeslocar = diferentes(0)
        guard semDeslocar > 0 else { return false }
        // Deslocada, a imagem quase coincide (sobra no máximo 1/5 da diferença).
        return (Array(-6...(-1)) + Array(1...6)).contains { diferentes($0) * 5 <= semDeslocar }
    }

    /// O retângulo do maior conjunto ligado de células marcadas. `dilatar` junta células a essa distância
    /// (as letras de um slide não se tocam). Com `pesos`, o maior é o de mais peso somado, não o de mais células.
    static func maiorBloco(_ marcadas: [Bool], colunas c: Int, linhas l: Int, dilatar: Int, pesos: [Int]? = nil) -> Caixa? {
        var visto = [Bool](repeating: false, count: c * l)
        var melhor: (n: Int, caixa: Caixa)?
        for inicio in marcadas.indices where marcadas[inicio] && !visto[inicio] {
            var pilha = [inicio]
            visto[inicio] = true
            var n = 0
            var caixa = Caixa(minX: c, minY: l, maxX: 0, maxY: 0)
            while let i = pilha.popLast() {
                n += pesos?[i] ?? 1
                let x = i % c, y = i / c
                caixa = Caixa(minX: min(caixa.minX, x), minY: min(caixa.minY, y), maxX: max(caixa.maxX, x + 1), maxY: max(caixa.maxY, y + 1))
                let r = dilatar + 1
                for dy in -r...r { for dx in -r...r where dx != 0 || dy != 0 {
                    let vx = x + dx, vy = y + dy
                    guard vx >= 0, vx < c, vy >= 0, vy < l else { continue }
                    let j = vy * c + vx
                    if marcadas[j], !visto[j] { visto[j] = true; pilha.append(j) }
                } }
            }
            if n > (melhor?.n ?? 0) { melhor = (n, caixa) }
        }
        return melhor?.caixa
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

    /// `b` é `a` com mais coisas: as células que mudaram eram fundo em `a` (perto da luminância mais comum).
    static func soAcrescenta(_ a: [Float], _ b: [Float]) -> Bool {
        guard !a.isEmpty, a.count == b.count else { return false }
        let fundo = a.sorted()[a.count / 2]
        let mudadas = a.indices.filter { abs(a[$0] - b[$0]) > limiarCelula }
        guard !mudadas.isEmpty else { return false }
        return mudadas.filter { abs(a[$0] - fundo) < 0.05 }.count * 10 >= mudadas.count * 9
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

