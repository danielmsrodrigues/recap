// Gera um vídeo sintético que imita uma aula gravada no Zoom: partilha de ecrã com slides,
// a câmara do professor numa miniatura no canto e um troço inicial só com a câmara.
// Voz em espanhol com o `say` do macOS. Serve para desenvolver e calibrar o Recap sem aulas reais.
//
//   swiftc -O Ferramentas/GeraAulaTeste/main.swift -o /tmp/gera-aula && /tmp/gera-aula ~/Downloads/aula.mp4

import AVFoundation
import AppKit

let largura = 1280, altura = 720, fps: Int32 = 10

enum Ecra {
    case camara
    case slide(titulo: String, linhas: [String], revelar: Int? = nil, ponteiro: Bool = false)
}

struct Segmento {
    var ecra: Ecra
    var fala: String
}

let guiao: [Segmento] = [
    Segmento(ecra: .camara, fala: "Buenos días a todos. Antes de compartir la pantalla, os recuerdo que la entrega de la práctica uno es el viernes a las once y cincuenta y nueve."),
    Segmento(ecra: .slide(titulo: "Tema 3", linhas: ["Diagonalización de matrices", "", "Álgebra Lineal · Grado en Ciencia de Datos e IA"]),
             fala: "Bien, vamos a empezar el tema tres: diagonalización de matrices."),
    Segmento(ecra: .slide(titulo: "Autovalores y autovectores", linhas: ["Sea A ∈ ℝⁿˣⁿ. Un escalar λ es autovalor de A si", "", "        ∃ v ≠ 0  tal que  A v = λ v", "", "v es un autovector asociado a λ."], ponteiro: true),
             fala: "Un escalar lambda es un autovalor de la matriz A si existe un vector v distinto de cero tal que A por v es igual a lambda por v. A ese vector v lo llamamos autovector asociado a lambda."),
    Segmento(ecra: .slide(titulo: "Polinomio característico", linhas: ["Los autovalores son las raíces de", "", "        p(λ) = det(A − λ I) = 0", "", "I es la matriz identidad de orden n."]),
             fala: "Para calcularlos usamos el polinomio característico: el determinante de A menos lambda por la identidad, igualado a cero. Las raíces de ese polinomio son los autovalores."),
    Segmento(ecra: .slide(titulo: "Ejemplo", linhas: ["A = ( 2  1 )", "      ( 1  2 )", "", "det(A − λI) = (2 − λ)² − 1 = 0", "", "λ₁ = 1,   λ₂ = 3"], revelar: 3),
             fala: "Veamos un ejemplo. Tomamos la matriz dos uno, uno dos. El determinante de A menos lambda I es dos menos lambda al cuadrado menos uno. Igualando a cero obtenemos lambda uno igual a uno y lambda dos igual a tres."),
    Segmento(ecra: .slide(titulo: "Autovalores y autovectores", linhas: ["Sea A ∈ ℝⁿˣⁿ. Un escalar λ es autovalor de A si", "", "        ∃ v ≠ 0  tal que  A v = λ v", "", "v es un autovector asociado a λ."]),
             fala: "Volvamos un momento a la definición: fijaos en que el vector tiene que ser distinto de cero."),
    Segmento(ecra: .slide(titulo: "Diagonalización", linhas: ["A es diagonalizable si existe P invertible tal que", "", "        A = P D P⁻¹", "", "D = diag(λ₁, …, λₙ),  columnas de P = autovectores."]),
             fala: "Decimos que A es diagonalizable si existe una matriz P invertible tal que A es igual a P por D por la inversa de P, donde D es diagonal con los autovalores, y las columnas de P son los autovectores."),
    Segmento(ecra: .slide(titulo: "Aplicación: descenso del gradiente", linhas: ["Actualización de los pesos:", "", "        w ← w − η ∇L(w)", "", "η = tasa de aprendizaje. Si η es demasiado grande, diverge."]),
             fala: "Una aplicación en aprendizaje automático: en el descenso del gradiente actualizamos los pesos restando la tasa de aprendizaje por el gradiente de la función de coste. Si la tasa es demasiado grande, el algoritmo diverge. El examen parcial será el quince de noviembre."),
]

// MARK: Áudio

func falar(_ texto: String, para url: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-v", "Mónica", "-o", url.path, "--data-format=LEF32@22050", texto]
    try p.run()
    p.waitUntilExit()
}

let taxa = 22_050.0
let tmp = FileManager.default.temporaryDirectory.appending(path: "gera-aula-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

var amostras: [Float] = []
var inicios: [Double] = []
for (i, s) in guiao.enumerated() {
    let url = tmp.appending(path: "seg\(i).caf")
    try falar(s.fala, para: url)
    let ficheiro = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: ficheiro.processingFormat, frameCapacity: AVAudioFrameCount(ficheiro.length))!
    try ficheiro.read(into: buffer)
    inicios.append(Double(amostras.count) / taxa)
    amostras += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    amostras += [Float](repeating: 0, count: Int(taxa * 1.5)) // pausa entre slides
}
let duracao = Double(amostras.count) / taxa
let urlAudio = tmp.appending(path: "audio.caf")
do {
    let formato = AVAudioFormat(standardFormatWithSampleRate: taxa, channels: 1)!
    let saida = try AVAudioFile(forWriting: urlAudio, settings: formato.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(amostras.count))!
    buffer.frameLength = AVAudioFrameCount(amostras.count)
    amostras.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: amostras.count) }
    try saida.write(from: buffer)
}

// MARK: Vídeo

func segmento(em t: Double) -> Int { max(0, (inicios.lastIndex { $0 <= t }) ?? 0) }

func desenharCamara(_ ctx: CGContext, em r: CGRect, t: Double) {
    ctx.setFillColor(NSColor(red: 0.18, green: 0.2, blue: 0.24, alpha: 1).cgColor)
    ctx.fill(r)
    // Parede com uma prateleira, e o "professor" a mexer-se (cabeça e ombros).
    ctx.setFillColor(NSColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 1).cgColor)
    ctx.fill(CGRect(x: r.minX, y: r.minY + r.height * 0.7, width: r.width, height: r.height * 0.05))
    let dx = sin(t * 1.3) * r.width * 0.08, dy = sin(t * 2.1) * r.height * 0.03
    let cx = r.midX + dx, base = r.minY + dy
    ctx.setFillColor(NSColor(red: 0.2, green: 0.35, blue: 0.6, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - r.width * 0.25, y: base - r.height * 0.2, width: r.width * 0.5, height: r.height * 0.55))
    ctx.setFillColor(NSColor(red: 0.85, green: 0.68, blue: 0.55, alpha: 1).cgColor)
    let cabeca = r.height * 0.32
    ctx.fillEllipse(in: CGRect(x: cx - cabeca / 2, y: base + r.height * 0.3, width: cabeca, height: cabeca * 1.15))
}

func desenharSlide(_ ctx: CGContext, titulo: String, linhas: [String], visiveis: Int) {
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: largura, height: altura))
    ctx.setFillColor(NSColor(red: 0.0, green: 0.27, blue: 0.55, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: altura - 110, width: largura, height: 110))
    (titulo as NSString).draw(at: NSPoint(x: 60, y: CGFloat(altura - 80)), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 42), .foregroundColor: NSColor.white])
    for (i, linha) in linhas.prefix(visiveis).enumerated() {
        let y = CGFloat(altura - 190) - CGFloat(i) * 62
        (linha as NSString).draw(at: NSPoint(x: 70, y: y),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
    }
    ("Universidad · Curso 2026/27" as NSString).draw(at: NSPoint(x: 60, y: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.gray])
}

func desenharPonteiro(_ ctx: CGContext, t: Double) {
    let x = 400 + sin(t * 0.9) * 250, y = 360 + cos(t * 0.7) * 120
    let seta = CGMutablePath()
    seta.move(to: CGPoint(x: x, y: y))
    seta.addLine(to: CGPoint(x: x, y: y - 26))
    seta.addLine(to: CGPoint(x: x + 7, y: y - 19))
    seta.addLine(to: CGPoint(x: x + 18, y: y - 19))
    seta.closeSubpath()
    ctx.addPath(seta); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
}

let urlVideo = tmp.appending(path: "video.mp4")
let escritor = try AVAssetWriter(outputURL: urlVideo, fileType: .mp4)
let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: largura, AVVideoHeightKey: altura,
])
let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: largura, kCVPixelBufferHeightKey as String: altura,
])
escritor.add(entrada)
escritor.startWriting()
escritor.startSession(atSourceTime: .zero)

let totalFrames = Int(duracao * Double(fps)) + 1
for f in 0..<totalFrames {
    while !entrada.isReadyForMoreMediaData { usleep(2000) }
    let t = Double(f) / Double(fps)
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptador.pixelBufferPool!, &pb)
    guard let pb else { fatalError("sem pixel buffer") }
    CVPixelBufferLockBaseAddress(pb, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: largura, height: altura, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let i = segmento(em: t)
    switch guiao[i].ecra {
    case .camara:
        desenharCamara(ctx, em: CGRect(x: 0, y: 0, width: largura, height: altura), t: t)
    case .slide(let titulo, let linhas, let revelar, let ponteiro):
        // Revelação progressiva: as linhas a partir de `revelar` só aparecem a meio do segmento.
        let fim = i + 1 < inicios.count ? inicios[i + 1] : duracao
        let meio = (inicios[i] + fim) / 2
        let visiveis = revelar.map { t < meio ? $0 : linhas.count } ?? linhas.count
        desenharSlide(ctx, titulo: titulo, linhas: linhas, visiveis: visiveis)
        if ponteiro { desenharPonteiro(ctx, t: t) }
        desenharCamara(ctx, em: CGRect(x: largura - 260, y: 20, width: 240, height: 135), t: t)
    }

    NSGraphicsContext.current = nil
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptador.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps))
}
entrada.markAsFinished()
await escritor.finishWriting()
guard escritor.status == .completed else { fatalError("vídeo: \(String(describing: escritor.error))") }

// MARK: Juntar vídeo e áudio

let composicao = AVMutableComposition()
let video = AVURLAsset(url: urlVideo), audio = AVURLAsset(url: urlAudio)
let duracaoVideo = try await video.load(.duration)
let faixaV = composicao.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try faixaV.insertTimeRange(CMTimeRange(start: .zero, duration: duracaoVideo), of: try await video.loadTracks(withMediaType: .video)[0], at: .zero)
let faixaA = composicao.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let duracaoAudio = try await audio.load(.duration)
try faixaA.insertTimeRange(CMTimeRange(start: .zero, duration: duracaoAudio), of: try await audio.loadTracks(withMediaType: .audio)[0], at: .zero)

let destino = URL(fileURLWithPath: (CommandLine.arguments.dropFirst().first ?? "aula-teste.mp4"))
try? FileManager.default.removeItem(at: destino)
let exportacao = AVAssetExportSession(asset: composicao, presetName: AVAssetExportPresetHighestQuality)!
try await exportacao.export(to: destino, as: .mp4)

print("Gravado \(destino.path) (\(Int(duracao)) s)")
print("Mudanças de ecrã (s):", inicios.map { String(format: "%.1f", $0) }.joined(separator: ", "))
