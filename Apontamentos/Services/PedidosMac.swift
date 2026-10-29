import Foundation

/// Um pedido ao Claude feito no iPad ou no iPhone, para o Recap do Mac responder com a subscrição
/// (`<raiz>/_recap/pedidos/<id>.json`). Leva só a intenção: o Mac monta o pedido com os ficheiros da aula
/// que já tem (a transcrição e os PDFs são dezenas de MB) e grava a resposta onde o Mac a gravaria.
struct PedidoMac: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var tipo: Estudo.Tipo
    /// Pasta da aula, relativa à raiz (`<cadeira>/<aula>`).
    var aula: String
    var pergunta: String?
    var citacao: CitacaoPergunta?
    /// Os ficheiros juntados, já na pasta da aula (chegam ao Mac pelo iCloud).
    var anexos: [String]?
    var criadoEm = Date.now
}

/// Como vai um pedido (`<id>.estado.json`), escrito pelo Mac.
struct EstadoPedidoMac: Codable, Equatable, Sendable {
    enum Fase: String, Codable, Sendable { case recebido, aGerar = "a_gerar", feito, erro }
    var fase: Fase
    /// O texto que já chegou (vai sendo atualizado enquanto o Claude escreve).
    var texto: String?
    var erro: String?
    /// Relógio do Mac. Sem atualização há muito tempo, o Mac deixou de responder (fechou a app, adormeceu).
    var atualizadoEm = Date.now
}

/// A pasta dos pedidos, dentro da pasta das aulas: chega aos dois lados pelo iCloud Drive, sem servidor nem rede local.
enum CaixaPedidos {
    static func pasta(_ raiz: URL) -> URL {
        raiz.appending(path: Disco.pastaSistema).appending(path: "pedidos", directoryHint: .isDirectory)
    }

    static func url(_ id: UUID, raiz: URL) -> URL { pasta(raiz).appending(path: "\(id.uuidString).json") }
    static func urlEstado(_ id: UUID, raiz: URL) -> URL { pasta(raiz).appending(path: "\(id.uuidString).estado.json") }

    static func enviar(_ pedido: PedidoMac, raiz: URL) throws {
        try FileManager.default.createDirectory(at: pasta(raiz), withIntermediateDirectories: true)
        try Disco.escrever(pedido, em: url(pedido.id, raiz: raiz))
    }

    static func estado(_ id: UUID, raiz: URL) -> EstadoPedidoMac? {
        try? Disco.ler(EstadoPedidoMac.self, de: urlEstado(id, raiz: raiz))
    }

    static func escreverEstado(_ estado: EstadoPedidoMac, id: UUID, raiz: URL) throws {
        try Disco.escrever(estado, em: urlEstado(id, raiz: raiz))
    }

    /// Os pedidos em que ninguém pegou (ainda sem estado), do mais antigo para o mais recente.
    static func porTratar(_ raiz: URL) -> [PedidoMac] {
        let nomes = (try? FileManager.default.contentsOfDirectory(atPath: pasta(raiz).path)) ?? []
        return nomes
            .filter { $0.hasSuffix(".json") && !$0.hasSuffix(".estado.json") && !nomes.contains($0.dropLast(5) + ".estado.json") }
            .compactMap { try? Disco.ler(PedidoMac.self, de: pasta(raiz).appending(path: $0)) }
            .sorted { $0.criadoEm < $1.criadoEm }
    }

    /// Tira o pedido e o estado (um pedido cancelado antes de o Mac pegar nele já não é respondido).
    static func apagar(_ id: UUID, raiz: URL) {
        try? FileManager.default.removeItem(at: url(id, raiz: raiz))
        try? FileManager.default.removeItem(at: urlEstado(id, raiz: raiz))
    }

    /// Os ficheiros de pedidos com mais de um dia já não servem a ninguém.
    static func limparAntigos(_ raiz: URL, idade: TimeInterval = 86_400, agora: Date = .now) {
        let itens = (try? FileManager.default.contentsOfDirectory(at: pasta(raiz), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for item in itens {
            guard let data = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  agora.timeIntervalSince(data) > idade else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// A aula do pedido, se existir e ficar dentro da pasta das aulas (o caminho vem de outro dispositivo).
    @MainActor
    static func aula(_ pedido: PedidoMac, em library: Library) -> Aula? {
        let raiz = library.raiz.standardizedFileURL
        let pasta = raiz.appending(path: pedido.aula, directoryHint: .isDirectory).standardizedFileURL
        guard pasta.path.hasPrefix(raiz.path + "/") else { return nil }
        return library.aula(em: pasta)
    }
}
