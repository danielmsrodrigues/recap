import AVFoundation
import SwiftUI

/// "Ouvir": lê os apontamentos de uma aula com a voz do sistema, secção a secção (ver `TextoFalado`). Continua com
/// o ecrã bloqueado (sessão de áudio de leitura e o modo de áudio em segundo plano).
@MainActor @Observable
final class LeitorAula: NSObject {
    private(set) var trechos: [TextoFalado.Trecho] = []
    private(set) var atual = 0
    private(set) var aTocar = false
    var velocidade: Float = 1

    @ObservationIgnored private let sintetizador = AVSpeechSynthesizer()
    @ObservationIgnored private var idioma = "pt-PT"

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    var ativo: Bool { !trechos.isEmpty }
    var tituloAtual: String { trechos.indices.contains(atual) ? (trechos[atual].titulo ?? "Início") : "" }

    func comecar(_ md: String, idioma: String) {
        parar()
        trechos = TextoFalado.trechos(md)
        self.idioma = idioma
        atual = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        falar()
    }

    func pausarOuRetomar() {
        if sintetizador.isPaused {
            sintetizador.continueSpeaking()
            aTocar = true
        } else if sintetizador.isSpeaking {
            sintetizador.pauseSpeaking(at: .word)
            aTocar = false
        } else {
            falar()
        }
    }

    func seguinte() { saltar(para: atual + 1) }
    func anterior() { saltar(para: atual - 1) }

    /// Muda de velocidade a meio: recomeça a secção atual com a velocidade nova.
    func mudarVelocidade(_ v: Float) {
        velocidade = v
        if aTocar { saltar(para: atual) }
    }

    func parar() {
        sintetizador.stopSpeaking(at: .immediate)
        aTocar = false
        trechos = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func saltar(para i: Int) {
        guard trechos.indices.contains(i) else { return }
        sintetizador.stopSpeaking(at: .immediate)
        atual = i
        falar()
    }

    private func falar() {
        guard trechos.indices.contains(atual) else { aTocar = false; return }
        let t = trechos[atual]
        let u = AVSpeechUtterance(string: [t.titulo.map { $0 + "." }, t.texto].compactMap { $0 }.joined(separator: " "))
        u.voice = AVSpeechSynthesisVoice(language: idioma)
        u.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * velocidade)
        u.postUtteranceDelay = 0.6
        sintetizador.speak(u)
        aTocar = true
    }

    /// Uma secção acabou de ser lida (não interrompida): passa à seguinte, ou termina no fim.
    private func acabou() {
        guard aTocar else { return }
        if atual + 1 < trechos.count {
            atual += 1
            falar()
        } else {
            aTocar = false
        }
    }
}

extension LeitorAula: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.acabou() }
    }
}

/// A barra do leitor, por baixo da aula: a secção a ser lida, anterior · pausa · seguinte, a velocidade e fechar.
struct BarraLeitor: View {
    let leitor: LeitorAula

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(leitor.tituloAtual).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(leitor.atual + 1) de \(leitor.trechos.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Secção anterior", systemImage: "backward.fill") { leitor.anterior() }
                .disabled(leitor.atual == 0)
            Button(leitor.aTocar ? "Pausa" : "Continuar", systemImage: leitor.aTocar ? "pause.fill" : "play.fill") { leitor.pausarOuRetomar() }
                .font(.title2)
            Button("Secção seguinte", systemImage: "forward.fill") { leitor.seguinte() }
                .disabled(leitor.atual + 1 >= leitor.trechos.count)
            Menu {
                ForEach([Float(0.8), 1, 1.2, 1.5], id: \.self) { v in
                    Button("\(v.formatted())×") { leitor.mudarVelocidade(v) }
                }
            } label: {
                Text("\(leitor.velocidade.formatted())×").font(.callout.weight(.semibold)).monospacedDigit()
            }
            Button("Fechar", systemImage: "xmark") { leitor.parar() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
