import Foundation

/// As secções da guia que uma aula tocou, pelos ids da guia ("2.4"), guardadas em `<aula>/guia-aula.json` quando os
/// apontamentos são gerados (ou pela procura nas aulas anteriores). Os ids, e não as posições, para continuarem
/// certos se o índice for lido outra vez.
struct SeccoesGuardadas: Codable, Equatable, Sendable {
    var explicadas: [String]
    var remetidas: [String]
    var mencionadas: [String]

    init(explicadas: [String], remetidas: [String], mencionadas: [String]) {
        self.explicadas = explicadas
        self.remetidas = remetidas
        self.mencionadas = mencionadas
    }

    init(_ selecao: SelecaoGuia, indice: IndiceGuia) {
        let ids = { (posicoes: [Int]) in posicoes.filter(indice.seccoes.indices.contains).map { indice.seccoes[$0].id } }
        self.init(explicadas: ids(selecao.explicadas), remetidas: ids(selecao.remetidas), mencionadas: ids(selecao.mencionadas))
    }
}

/// O progresso do programa de uma cadeira com guia: cada secção da guia fica vista (dada numa aula), em curso
/// (mandada estudar pela guia, só mencionada, ou com parte dos subtemas dada) ou por ver.
enum ProgressoGuia {
    enum Estado: Sendable { case vista, emCurso, porVer }

    struct Tema: Identifiable, Sendable {
        var seccao: SeccaoGuia
        var estado: Estado
        /// As aulas que tocaram a secção, por data.
        var aulas: [Aula]
        var id: String { seccao.id }
        /// Um subtema ("2.4"), e não um tema ("2").
        var subtema: Bool { seccao.id.contains(".") }
    }

    static func calcular(_ indice: IndiceGuia, aulas: [(Aula, SeccoesGuardadas)]) -> [Tema] {
        let porData = aulas.sorted { $0.0.meta.data < $1.0.meta.data }
        func doProprio(_ id: String) -> (Estado, [Aula]) {
            let tocaram = porData.filter { a in [a.1.explicadas, a.1.remetidas, a.1.mencionadas].contains { $0.contains(id) } }.map(\.0)
            if porData.contains(where: { $0.1.explicadas.contains(id) }) { return (.vista, tocaram) }
            return (tocaram.isEmpty ? .porVer : .emCurso, tocaram)
        }
        return indice.seccoes.map { s in
            let (estado, tocaram) = doProprio(s.id)
            let filhos = indice.seccoes.filter { $0.id.hasPrefix(s.id + ".") }
            guard !filhos.isEmpty, estado != .vista else { return Tema(seccao: s, estado: estado, aulas: tocaram) }
            // Um tema com subtemas: visto quando todos foram dados; em curso quando algum foi tocado.
            let estados = filhos.map { doProprio($0.id).0 }
            let todasAulas = (tocaram + filhos.flatMap { doProprio($0.id).1 })
            var vistas: [URL] = []
            let unicas = todasAulas.sorted { $0.meta.data < $1.meta.data }.filter { a in
                if vistas.contains(a.pasta) { return false }
                vistas.append(a.pasta)
                return true
            }
            let agregado: Estado = estados.allSatisfy { $0 == .vista } ? .vista
                : (estado == .emCurso || estados.contains { $0 != .porVer }) ? .emCurso : .porVer
            return Tema(seccao: s, estado: agregado, aulas: unicas)
        }
    }

    /// "Vistos 2 de 3 temas", só com os temas principais.
    static func resumo(_ temas: [Tema]) -> String {
        let principais = temas.filter { !$0.subtema }
        let vistos = principais.filter { $0.estado == .vista }.count
        return "Vistos \(vistos) de \(principais.count) \(principais.count == 1 ? "tema" : "temas")"
    }

    /// Os acentos que o PDF parte em dois ("N´umeros", "L´ımites", "Espa˜na"), juntos outra vez.
    static func titulo(_ s: String) -> String {
        var t = s
        for (de, para) in [("´a", "á"), ("´e", "é"), ("´ı", "í"), ("´i", "í"), ("´o", "ó"), ("´u", "ú"),
                           ("´A", "Á"), ("´E", "É"), ("´I", "Í"), ("´O", "Ó"), ("´U", "Ú"), ("˜n", "ñ"), ("˜N", "Ñ"), ("¨u", "ü")] {
            t = t.replacingOccurrences(of: de, with: para)
        }
        return t
    }

    /// O índice já lido da guia da cadeira (`guia.json`), sem abrir o PDF.
    static func indiceGuardado(_ cadeira: URL) -> IndiceGuia? {
        try? Disco.ler(IndiceGuia.self, de: cadeira.appending(path: GuiaEstudo.ficheiro))
    }
}

extension Disco {
    static let seccoesGuiaJSON = "guia-aula.json"

    static func lerSeccoesGuia(_ pasta: URL) -> SeccoesGuardadas? {
        guard let dados = try? lerDados(pasta.appending(path: seccoesGuiaJSON)) else { return nil }
        return try? decoder.decode(SeccoesGuardadas.self, from: dados)
    }

    static func escreverSeccoesGuia(_ s: SeccoesGuardadas, em pasta: URL) throws {
        try gravar(encoder.encode(s), em: pasta.appending(path: seccoesGuiaJSON))
    }
}
