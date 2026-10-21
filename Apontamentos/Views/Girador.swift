import SwiftUI

/// Indicador de atividade que não pisca. O `ProgressView()` do macOS recomeça a animação sempre que a vista
/// é redesenhada, e durante a transcrição e a extração de slides o progresso muda várias vezes por segundo.
/// Aqui o raio aceso vem do relógio, por isso redesenhar a vista não se nota.
struct Girador: View {
    enum Tamanho {
        case mini, pequeno

        var lado: CGFloat {
            switch self {
            case .mini: 10
            case .pequeno: 16
            }
        }
    }

    var tamanho: Tamanho = .pequeno

    private static let raios = 8
    private static let passosPorSegundo = 10.0

    var body: some View {
        let lado = tamanho.lado
        TimelineView(.periodic(from: .now, by: 1 / Self.passosPorSegundo)) { contexto in
            let passo = Int(contexto.date.timeIntervalSinceReferenceDate * Self.passosPorSegundo) % Self.raios
            ZStack {
                ForEach(0..<Self.raios, id: \.self) { i in
                    // O raio aceso é o do passo; os anteriores vão-se apagando, como no indicador do sistema.
                    let atras = (passo - i + Self.raios) % Self.raios
                    Capsule()
                        .fill(.secondary)
                        .frame(width: lado * 0.11, height: lado * 0.3)
                        .offset(y: -lado * 0.33)
                        .rotationEffect(.degrees(Double(i) * 360 / Double(Self.raios)))
                        .opacity(1 - Double(atras) / Double(Self.raios) * 0.8)
                }
            }
            .frame(width: lado, height: lado)
        }
        .accessibilityLabel("A processar")
    }
}
