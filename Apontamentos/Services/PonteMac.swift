#if os(macOS)
import Foundation

/// Responde aos pedidos do iPad e do iPhone (`CaixaPedidos`) com o `Estudo` do Mac, ou seja, com o Claude Code e a
/// subscrição: o iOS não corre processos. Enquanto o Recap está aberto, vê a pasta dos pedidos de 2 em 2 segundos
/// (o iCloud demora mais do que isso a trazê-los) e vai escrevendo o estado, com o texto que já chegou.
@MainActor
final class PonteMac {
    private let library: Library
    private let estudo: Estudo
    private let definicoes: Definicoes
    private var ciclo: Task<Void, Never>?
    /// Pedidos já entregues ao `Estudo` nesta sessão (o estado pode ainda não estar no disco).
    private var tratados: Set<UUID> = []

    init(library: Library, estudo: Estudo, definicoes: Definicoes) {
        self.library = library
        self.estudo = estudo
        self.definicoes = definicoes
    }

    func ligar() {
        guard ciclo == nil else { return }
        ciclo = Task { [weak self] in
            while !Task.isCancelled {
                self?.verificar()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func verificar() {
        guard definicoes.responderPedidos else { return }
        let raiz = library.raiz
        CaixaPedidos.limparAntigos(raiz)
        for pedido in CaixaPedidos.porTratar(raiz) where !tratados.contains(pedido.id) {
            tratar(pedido, raiz: raiz)
        }
    }

    private func tratar(_ pedido: PedidoMac, raiz: URL) {
        tratados.insert(pedido.id)
        func estado(_ fase: EstadoPedidoMac.Fase, texto: String? = nil, erro: String? = nil) {
            try? CaixaPedidos.escreverEstado(EstadoPedidoMac(fase: fase, texto: texto, erro: erro), id: pedido.id, raiz: raiz)
        }
        guard let aula = CaixaPedidos.aula(pedido, em: library) else {
            estado(.erro, erro: "Esta aula não está no Mac (ou ainda não chegou pelo iCloud).")
            return
        }
        guard estudo.emCurso(aula, pedido.tipo) == nil else {
            estado(.erro, erro: "O Mac já está a tratar de um pedido destes nesta aula. Tenta daqui a pouco.")
            return
        }
        estado(.recebido)
        Task { [weak self] in
            // Os ficheiros juntados no iPhone podem chegar pelo iCloud depois do pedido.
            await Self.esperarAnexos(pedido.anexos ?? [], em: aula.pasta)
            switch pedido.tipo {
            case .pergunta: self?.estudo.perguntar(pedido.pergunta ?? "", sobre: aula, citacao: pedido.citacao, anexos: pedido.anexos ?? [])
            case .exercicios: self?.estudo.gerarExercicios(aula)
            case .ligacoes: self?.estudo.gerarLigacoes(aula)
            }
            var escrito: String?
            var ultimaEscrita = Date.now
            while let self, let emCurso = self.estudo.emCurso(aula, pedido.tipo) {
                // Cada escrita vai ao iCloud: só quando há texto novo, ou de 20 em 20 s para o iOS saber que o Mac continua.
                if emCurso.texto != escrito || Date.now.timeIntervalSince(ultimaEscrita) > 20 {
                    estado(.aGerar, texto: emCurso.texto)
                    escrito = emCurso.texto
                    ultimaEscrita = .now
                }
                try? await Task.sleep(for: .seconds(2))
            }
            if let erro = self?.estudo.erro(aula, pedido.tipo) {
                estado(.erro, erro: erro)
            } else {
                // O último pedaço pode ter chegado entre duas voltas: o texto final é o que ficou gravado.
                let final = switch pedido.tipo {
                case .pergunta: Disco.lerPerguntas(aula.pasta).last?.resposta
                case .exercicios: Disco.lerTexto(Disco.exerciciosMD, em: aula.pasta)
                case .ligacoes: escrito
                }
                estado(.feito, texto: final ?? escrito)
            }
        }
    }

    /// Até 2 minutos à espera de que os ficheiros apareçam na pasta da aula (descarregá-los fica para quando forem lidos).
    private static func esperarAnexos(_ nomes: [String], em pasta: URL) async {
        let fim = Date.now.addingTimeInterval(120)
        while Date.now < fim, nomes.contains(where: { nome in
            Anexos.nomeSeguro(nome).map { !FileManager.default.fileExists(atPath: Anexos.url($0, em: pasta).path) } ?? false
        }) {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
