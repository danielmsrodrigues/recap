import SwiftUI

/// Etapas de um job com progresso, cancelar e tentar de novo.
struct ProgressoJobView: View {
    @Environment(ProcessingQueue.self) private var fila
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Etapa.allCases) { etapa in
                LinhaEtapa(etapa: etapa, estado: job.estadoDe(etapa))
            }

            if let aviso = job.aviso {
                Label(aviso, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            if case .falhou(let mensagem) = job.estado {
                Label(mensagem, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                switch job.estado {
                case .emEspera:
                    Text("Em espera na fila").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancelar") { fila.cancelar(job) }
                case .aCorrer:
                    Spacer()
                    Button("Cancelar", role: .cancel) { fila.cancelar(job) }
                case .falhou, .cancelado:
                    if job.estado == .cancelado { Text("Cancelado").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Fechar") { fila.remover(job) }
                    Button("Tentar de novo") { fila.repetir(job) }
                        .buttonStyle(.borderedProminent)
                case .concluido:
                    Spacer()
                    Button("Fechar") { fila.remover(job) }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

private struct LinhaEtapa: View {
    let etapa: Etapa
    let estado: EstadoEtapa

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            icone.frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(etapa.nome)
                    .fontWeight(estado.fase == .emCurso ? .semibold : .regular)
                    .foregroundStyle(estado.fase == .saltada || estado.fase == .pendente ? .secondary : .primary)
                if estado.fase == .emCurso {
                    if let p = estado.progresso {
                        ProgressView(value: p)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                if let detalhe = estado.detalhe {
                    Text(detalhe).font(.caption).foregroundStyle(.secondary)
                }
            }
            if estado.fase == .emCurso, let p = estado.progresso {
                Text(p.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var icone: some View {
        switch estado.fase {
        case .pendente: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .emCurso: Girador()
        case .concluida: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .saltada: Image(systemName: "arrow.uturn.forward.circle").foregroundStyle(.secondary)
        case .falhou: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
