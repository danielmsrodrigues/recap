import SwiftUI

/// Uma imagem juntada a uma pergunta, em grande por cima da janela (como no WhatsApp), e não numa janela à
/// parte do Quick Look. Fecha com ✕, Esc ou um clique fora da imagem.
struct ImagemEmGrande: View {
    let url: URL
    var aoFechar: () -> Void
    @State private var imagem: CGImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture(perform: aoFechar)
            if let imagem {
                Image(decorative: imagem, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 6))
                    .padding(40)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("Fechar", systemImage: "xmark.circle.fill", action: aoFechar)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title)
                .foregroundStyle(.white, .white.opacity(0.25))
                .keyboardShortcut(.cancelAction)
                .padding(12)
        }
        .overlay(alignment: .bottom) {
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 12)
        }
        .task(id: url) {
            let url = url
            imagem = await Task.detached { Anexos.miniatura(de: url, lado: Anexos.ladoMaximoImagem) }.value
        }
    }
}

extension View {
    /// Mostra por cima desta vista a imagem que estiver em `Navegacao.imagemAberta`.
    func imagemEmGrande(_ navegacao: Navegacao) -> some View {
        overlay {
            if let url = navegacao.imagemAberta {
                ImagemEmGrande(url: url) { withAnimation(.easeOut(duration: 0.15)) { navegacao.imagemAberta = nil } }
                    .transition(.opacity)
            }
        }
    }
}
