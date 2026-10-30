// O ícone do Recap: um "R" arredondado com a bolinha vermelha de gravar (design "Recap App Icon", 11a e 11b).
// Gera o PNG de 1024 px do Mac (com margem e sombra, como os ícones do macOS) e os do iOS (claro e escuro,
// opacos e até às bordas: o iOS arredonda os cantos e não aceita transparência).
//
//   swift Ferramentas/GerarIcone.swift <pasta de saída>
//
// Depois, `sips` faz os tamanhos mais pequenos do Mac (ver o fim deste ficheiro).
import AppKit
import CoreText

let saida = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
try FileManager.default.createDirectory(at: saida, withIntermediateDirectories: true)

func cor(_ hex: UInt32, _ alfa: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alfa)
}

/// oklch(0.63 0.21 27) do design.
let vermelho: UInt32 = 0xED413B

struct Tema {
    var topo: CGColor, fundo: CGColor
    /// O gradiente do design claro é de cima para baixo (180°); o escuro, quase (165°).
    var angulo: CGFloat
    var letra: CGColor
    var anel: CGFloat
}
let claro = Tema(topo: cor(0xFFFFFF), fundo: cor(0xE9EBF0), angulo: 180, letra: cor(0x1D1D22), anel: 0.18)
let escuro = Tema(topo: cor(0x34343A), fundo: cor(0x141417), angulo: 165, letra: cor(0xFFFFFF), anel: 0.22)

/// Desenha o ícone do design (uma caixa de 200 px) dentro de `caixa`.
func desenhar(_ ctx: CGContext, _ tema: Tema, caixa: CGRect, cantos: CGFloat?) {
    let s = caixa.width / 200
    ctx.saveGState()
    if let cantos {
        ctx.addPath(CGPath(roundedRect: caixa, cornerWidth: cantos, cornerHeight: cantos, transform: nil))
        ctx.clip()
    }
    // Ângulo CSS: 180° vai de cima para baixo.
    let rad = (tema.angulo - 90) * .pi / 180
    let meio = CGPoint(x: caixa.midX, y: caixa.midY)
    let d = CGPoint(x: cos(rad) * caixa.width / 2, y: -sin(rad) * caixa.height / 2)
    let gradiente = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [tema.topo, tema.fundo] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradiente, start: CGPoint(x: meio.x - d.x, y: meio.y - d.y), end: CGPoint(x: meio.x + d.x, y: meio.y + d.y),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // O "R": SF Pro Rounded, 800 (heavy), 132 px.
    let base = NSFont.systemFont(ofSize: 132 * s, weight: .heavy)
    let fonte = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 132 * s) ?? base
    let texto = NSAttributedString(string: "R", attributes: [.font: fonte, .foregroundColor: NSColor(cgColor: tema.letra)!])
    let linha = CTLineCreateWithAttributedString(texto)
    let largura = CTLineGetTypographicBounds(linha, nil, nil, nil)
    let bola = 32 * s, espaco = 5 * s
    // Como no design: o grupo "R" + bola ao centro, 9 px para a direita; a altura das maiúsculas ao centro.
    let grupo = CGFloat(largura) + espaco + bola
    let x = caixa.midX - grupo / 2 + 9 * s
    let linhaBase = caixa.midY - fonte.capHeight / 2
    ctx.textPosition = CGPoint(x: x, y: linhaBase)
    CTLineDraw(linha, ctx)

    // A bola assenta na linha de base, com um anel à volta.
    let centro = CGPoint(x: x + CGFloat(largura) + espaco + bola / 2, y: linhaBase + bola / 2)
    let anel = bola / 2 + 6 * s
    ctx.setFillColor(cor(vermelho, tema.anel))
    ctx.fillEllipse(in: CGRect(x: centro.x - anel, y: centro.y - anel, width: anel * 2, height: anel * 2))
    ctx.setFillColor(cor(vermelho))
    ctx.fillEllipse(in: CGRect(x: centro.x - bola / 2, y: centro.y - bola / 2, width: bola, height: bola))
    ctx.restoreGState()
}

func gravar(_ nome: String, lado: Int = 1024, opaco: Bool, _ corpo: (CGContext) -> Void) throws {
    let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (opaco ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    corpo(ctx)
    let url = saida.appending(path: nome)
    let destino = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destino, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(destino) else { throw CocoaError(.fileWriteUnknown) }
    print(url.path)
}

// macOS: a forma arredondada de 824 px dentro de 1024, com sombra (a grelha dos ícones do macOS).
try gravar("mac-1024.png", opaco: false) { ctx in
    let caixa = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: cor(0x000000, 0.3))
    ctx.setFillColor(cor(0xFFFFFF))
    ctx.addPath(CGPath(roundedRect: caixa, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    desenhar(ctx, claro, caixa: caixa, cantos: 185)
}
// iOS: até às bordas e opaco.
try gravar("ios-1024.png", opaco: true) { desenhar($0, claro, caixa: CGRect(x: 0, y: 0, width: 1024, height: 1024), cantos: nil) }
try gravar("ios-1024-escuro.png", opaco: true) { desenhar($0, escuro, caixa: CGRect(x: 0, y: 0, width: 1024, height: 1024), cantos: nil) }

// Os tamanhos do Mac, a partir do de 1024:
//   for t in 16 32 128 256 512; do
//     sips -z $t $t mac-1024.png --out icon_${t}x${t}.png; sips -z $((t*2)) $((t*2)) mac-1024.png --out icon_${t}x${t}@2x.png
//   done
