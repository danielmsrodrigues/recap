import Foundation
import Observation

/// O que trabalha sobre um curso: a `Library` da pasta dele, e a ficha e o estudo que dependem dela.
/// Fica vivo enquanto a app estiver aberta: o que estiver em curso acaba no curso certo, mesmo com outro aberto.
@MainActor
final class ServicosCurso: Identifiable {
    let library: Library
    let fichas: Fichas
    let estudo: Estudo
    private var aberto = false

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(library: Library, fichas: Fichas, estudo: Estudo) {
        self.library = library
        self.fichas = fichas
        self.estudo = estudo
    }

    convenience init(library: Library, definicoes: Definicoes) {
        self.init(library: library, fichas: Fichas(library: library, definicoes: definicoes),
                  estudo: Estudo(library: library, definicoes: definicoes))
    }

    /// Da primeira vez que o curso abre nesta sessão: as aulas antigas com "Sobre a cadeira" nos apontamentos, ou que
    /// ainda não entraram na ficha. Não se repete a cada troca de curso, porque cada volta lê todas as aulas.
    func aoAbrir() {
        guard !aberto else { return }
        aberto = true
        fichas.atualizarTodas()
    }
}

enum ErroCurso: LocalizedError, Equatable {
    case semNome
    case jaExiste(String)
    case aChegar(String)

    var errorDescription: String? {
        switch self {
        case .semNome: "O curso precisa de um nome."
        case .jaExiste(let nome): "Já existe um curso chamado \"\(nome)\"."
        case .aChegar(let nome): "\"\(nome)\" ainda está a chegar do iCloud. Tenta daqui a pouco."
        }
    }
}

/// A pasta das aulas, com os cursos que tem. Não há base de dados nem índice: o catálogo lê-se das pastas (ver `Curso`).
@MainActor @Observable
final class Biblioteca {
    private(set) var raiz: URL
    private(set) var cursos: [Curso]
    /// O curso aberto neste aparelho. Cada aparelho escolhe o seu.
    private(set) var cursoAtivo: Curso
    private(set) var ativo: ServicosCurso
    /// O curso escolhido não está aqui (ainda não chegou pelo iCloud, ou foi apagado): abriu-se outro, sem esquecer a
    /// escolha. Quando ele aparecer, volta a abrir.
    private(set) var cursoEmFalta: String?
    /// Por id de curso. Só para o catálogo: enche-se com `atualizarResumos()`.
    private(set) var resumos: [String: ResumoCurso] = [:]

    @ObservationIgnored private let definicoes: Definicoes
    @ObservationIgnored private var servicosPorCurso: [String: ServicosCurso] = [:]
    @ObservationIgnored private var observador: ObservadorPasta?

    static let chaveCursoAtivo = "cursoAtivo"

    init(raiz: URL, definicoes: Definicoes) {
        self.raiz = raiz
        self.definicoes = definicoes
        let cursos = Self.ler(raiz: raiz)
        let escolha = Self.escolher(definicoes.defaults.string(forKey: Self.chaveCursoAtivo), em: cursos)
        let servicos = Self.criarServicos(escolha.curso, definicoes: definicoes)
        self.cursos = cursos
        cursoAtivo = escolha.curso
        cursoEmFalta = escolha.emFalta
        ativo = servicos
        servicosPorCurso[escolha.curso.id] = servicos
    }

    // MARK: Ler o catálogo

    /// Cada pasta em `_recap/cursos` é um curso, mesmo com o `curso.json` ainda por descarregar. A raiz é um curso se
    /// tiver cadeiras, se já tiver nome, ou se não houver mais nenhum: quem tem um só curso não vê diferença.
    /// Nunca fica vazio.
    nonisolated static func ler(raiz: URL) -> [Curso] {
        let novos = pastas(em: Disco.urlCursos(raiz: raiz)).map { Curso(id: $0.lastPathComponent, pasta: $0, meta: Disco.lerCurso($0)) }
        let temNome = FileManager.default.fileExists(atPath: Disco.urlCurso(raiz).path)
        let daRaiz = temCadeiras(raiz) || temNome || novos.isEmpty ? [cursoDaRaiz(raiz)] : []
        return (daRaiz + novos).sorted { a, b in
            if a.concluido != b.concluido { return !a.concluido }
            return a.nome.localizedStandardCompare(b.nome) == .orderedAscending
        }
    }

    nonisolated private static func pastas(em pai: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: pai, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    nonisolated private static func temCadeiras(_ raiz: URL) -> Bool {
        pastas(em: raiz).contains { $0.lastPathComponent != Disco.pastaSistema }
    }

    nonisolated private static func cursoDaRaiz(_ raiz: URL) -> Curso {
        Curso(id: Curso.idDaRaiz, pasta: raiz, meta: Disco.lerCurso(raiz))
    }

    /// O curso guardado, ou o primeiro de que se possa abrir. `emFalta`: o guardado, se era um curso novo e não está lá.
    nonisolated private static func escolher(_ guardado: String?, em cursos: [Curso]) -> (curso: Curso, emFalta: String?) {
        if let guardado, let curso = cursos.first(where: { $0.id == guardado }) { return (curso, nil) }
        let porDefeito = cursos.first(where: \.naRaiz) ?? cursos.first(where: { !$0.concluido }) ?? cursos[0]
        return (porDefeito, guardado.flatMap { $0 == Curso.idDaRaiz ? nil : $0 })
    }

    /// Volta a ler os cursos das pastas. O curso aberto pode ter desaparecido, e o escolhido pode ter chegado agora.
    func recarregarCursos() {
        let lidos = Self.ler(raiz: raiz)
        if lidos != cursos { cursos = lidos }
        if let falta = cursoEmFalta, let chegou = lidos.first(where: { $0.id == falta }) {
            cursoEmFalta = nil
            mudarPara(chegou)
        } else if let atual = lidos.first(where: { $0.id == cursoAtivo.id }) {
            if atual != cursoAtivo { cursoAtivo = atual }
        } else {
            let escolha = Self.escolher(definicoes.defaults.string(forKey: Self.chaveCursoAtivo), em: lidos)
            cursoEmFalta = escolha.emFalta
            mudarPara(escolha.curso)
        }
    }

    /// Passa a reler o catálogo quando a pasta muda fora da app (um curso novo a chegar pelo iCloud).
    func vigiar() {
        observador = ObservadorPasta(raiz, ignorar: ObservadorPasta.ignorarNoCatalogo) { [weak self] in self?.recarregarCursos() }
    }

    /// Calcula o resumo de cada curso, fora do fio principal.
    func atualizarResumos() {
        let alvos = cursos
        Task {
            let novos = await Task.detached(priority: .utility) { Self.resumos(de: alvos) }.value
            if novos != resumos { resumos = novos }
        }
    }

    nonisolated static func resumos(de cursos: [Curso]) -> [String: ResumoCurso] {
        var r: [String: ResumoCurso] = [:]
        for curso in cursos {
            guard let cadeiras = try? Library.ler(raiz: curso.pasta) else { continue }
            let aulas = cadeiras.flatMap(\.aulas)
            r[curso.id] = ResumoCurso(cadeiras: cadeiras.count, aulas: aulas.count, porRever: Revisao.porRever(cadeiras).count,
                                      ultimaAula: aulas.map(\.meta.data).max())
        }
        return r
    }

    // MARK: Gerir os cursos

    /// O curso da raiz, se ainda não tem nome e tem cadeiras: com outro curso ao lado, tem de se saber qual é.
    var cursoDaRaizPorNomear: Curso? {
        guard let daRaiz = cursos.first(where: \.naRaiz), daRaiz.meta.nome == nil, Self.temCadeiras(raiz) else { return nil }
        return daRaiz
    }

    /// Cria um curso novo, sem tocar em nada do que já existe: as cadeiras da raiz ficam onde estão.
    /// `nomeDoCursoDaRaiz`: o nome a dar ao curso que já havia (ver `cursoDaRaizPorNomear`).
    @discardableResult
    func criarCurso(nome: String, preferencias: DefinicoesPartilhadas, nomeDoCursoDaRaiz: String? = nil) throws -> Curso {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let nomeDaRaiz = nomeDoCursoDaRaiz?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty, nomeDaRaiz?.isEmpty != true else { throw ErroCurso.semNome }
        recarregarCursos()
        try verificarNomeLivre(nome, exceto: nil)
        if let nomeDaRaiz {
            guard nomeDaRaiz.localizedCaseInsensitiveCompare(nome) != .orderedSame else { throw ErroCurso.jaExiste(nome) }
            try verificarNomeLivre(nomeDaRaiz, exceto: Curso.idDaRaiz)
        }
        let id = Disco.nomeDePasta(nome)
        let pasta = Disco.urlCursos(raiz: raiz).appending(path: id, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: pasta.path) else { throw ErroCurso.jaExiste(nome) }
        if let nomeDaRaiz, let daRaiz = cursos.first(where: \.naRaiz) {
            try alterarMeta(daRaiz) { $0.nome = nomeDaRaiz }
        }
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try Disco.escreverCurso(CursoMeta(nome: nome), em: pasta)
        try DefinicoesPartilhadas.escrever(preferencias, raiz: pasta)
        recarregarCursos()
        return cursos.first { $0.id == id } ?? Curso(id: id, pasta: pasta, meta: CursoMeta(nome: nome))
    }

    /// Muda só o nome em `curso.json`. A pasta fica: renomeá-la deixava um aparelho desatualizado a recriar a antiga.
    func renomear(_ curso: Curso, para nome: String) throws {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty else { throw ErroCurso.semNome }
        try verificarNomeLivre(nome, exceto: curso.id)
        try alterarMeta(curso) { $0.nome = nome }
    }

    func definirConcluido(_ concluido: Bool, curso: Curso) throws {
        try alterarMeta(curso) {
            $0.estadoCurso = concluido ? .concluido : .aDecorrer
            $0.concluidoEm = concluido ? .now : nil
        }
    }

    private func verificarNomeLivre(_ nome: String, exceto id: String?) throws {
        if cursos.contains(where: { $0.id != id && $0.nome.localizedCaseInsensitiveCompare(nome) == .orderedSame }) {
            throw ErroCurso.jaExiste(nome)
        }
    }

    /// Com o `curso.json` por descarregar, recusa: ler daria um vazio, e gravá-lo levava-o por cima do verdadeiro.
    private func alterarMeta(_ curso: Curso, _ alterar: (inout CursoMeta) -> Void) throws {
        guard !Disco.porDescarregar(Disco.urlCurso(curso.pasta)) else { throw ErroCurso.aChegar(curso.nome) }
        var meta = Disco.lerCurso(curso.pasta)
        alterar(&meta)
        try Disco.escreverCurso(meta, em: curso.pasta)
        recarregarCursos()
    }

    // MARK: Abrir um curso

    /// Abre o curso e lembra-se dele neste aparelho.
    func abrir(_ curso: Curso) {
        definicoes.defaults.set(curso.id, forKey: Self.chaveCursoAtivo)
        cursoEmFalta = nil
        guard curso.id != cursoAtivo.id else { return }
        mudarPara(curso)
    }

    private func mudarPara(_ curso: Curso) {
        let novo = servicos(do: curso)
        // Em memória desde a última vez que esteve aberto, e sem vigiar a pasta entretanto.
        novo.library.recarregar()
        if novo !== ativo { ativo.library.deixarDeVigiar() }
        cursoAtivo = curso
        ativo = novo
    }

    private func servicos(do curso: Curso) -> ServicosCurso {
        if let feitos = servicosPorCurso[curso.id] { return feitos }
        let novos = Self.criarServicos(curso, definicoes: definicoes)
        servicosPorCurso[curso.id] = novos
        return novos
    }

    /// As preferências antigas do aparelho só servem ao curso da raiz, que era o único. Um curso novo não cria a sua
    /// pasta se ela desaparecer: seria um curso fantasma, levado de volta pelo iCloud.
    private static func criarServicos(_ curso: Curso, definicoes: Definicoes) -> ServicosCurso {
        let library = curso.naRaiz
            ? Library(raiz: curso.pasta, preferenciasDeRecurso: definicoes.preferenciasAntigas)
            : Library(raiz: curso.pasta, criarRaiz: false)
        return ServicosCurso(library: library, definicoes: definicoes)
    }

    // MARK: A que curso pertence

    /// As pastas dos cursos, para quem tem de ver todos (os pedidos do iPad e do iPhone). A raiz vai sempre: um aparelho
    /// com uma versão anterior pede por lá.
    var raizesDosCursos: [URL] { [raiz] + cursos.filter { !$0.naRaiz }.map(\.pasta) }

    /// O curso a que pertence um caminho (a pasta de uma aula, ou a do próprio curso), pelo prefixo mais longo:
    /// a raiz contém os cursos novos. nil se não for de nenhum, em vez de um curso errado.
    func curso(de pasta: URL) -> Curso? {
        if let novo = cursos.first(where: { !$0.naRaiz && (pasta.mesmoCaminho($0.pasta) || pasta.estaDentro(de: $0.pasta)) }) {
            return novo
        }
        guard pasta.mesmoCaminho(raiz) || pasta.estaDentro(de: raiz),
              !pasta.estaDentro(de: raiz.appending(path: Disco.pastaSistema)) else { return nil }
        return cursos.first(where: \.naRaiz) ?? Self.cursoDaRaiz(raiz)
    }

    /// Os serviços do curso de um caminho. Se não se encontrar, relê o catálogo: o curso pode ter acabado de chegar.
    func servicos(de pasta: URL) -> ServicosCurso? {
        if let curso = curso(de: pasta) { return servicos(do: curso) }
        recarregarCursos()
        return curso(de: pasta).map { servicos(do: $0) }
    }

    /// Onde está agora uma aula que estava em `antiga`: a mesma cadeira noutro curso, ou a mesma pasta da aula noutra
    /// cadeira (a cadeira mudou de nome). Só se houver uma resposta: com duas, não se adivinha.
    func procurarAula(_ antiga: URL) -> URL? {
        let fm = FileManager.default
        let nomeAula = antiga.lastPathComponent, nomeCadeira = antiga.deletingLastPathComponent().lastPathComponent
        func aula(_ cadeira: URL) -> URL? {
            let pasta = cadeira.appending(path: nomeAula, directoryHint: .isDirectory)
            return fm.fileExists(atPath: pasta.appending(path: Disco.aulaJSON).path) ? pasta : nil
        }
        recarregarCursos()
        let naMesmaCadeira = cursos.compactMap { aula($0.pasta.appending(path: nomeCadeira, directoryHint: .isDirectory)) }
        if naMesmaCadeira.count == 1 { return naMesmaCadeira[0] }
        guard naMesmaCadeira.isEmpty else { return nil }
        let noutraCadeira = cursos.flatMap { curso in
            ((try? fm.contentsOfDirectory(at: curso.pasta, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                .filter { $0.lastPathComponent != Disco.pastaSistema }
                .compactMap(aula)
        }
        return noutraCadeira.count == 1 ? noutraCadeira[0] : nil
    }

    // MARK: Mudar a pasta das aulas

    /// Passa a usar outra pasta das aulas. Com `mover`, vai tudo o que está na atual, os cursos novos incluídos
    /// (estão em `_recap`). Quem chama garante que não há nada em curso.
    func mudarRaiz(para nova: URL, mover: Bool) throws {
        let daRaiz = servicos(do: Self.cursoDaRaiz(raiz))
        try daRaiz.library.mudarRaiz(para: nova, mover: mover)
        raiz = daRaiz.library.raiz
        // Os outros serviços ficaram com o caminho antigo.
        servicosPorCurso = [Curso.idDaRaiz: daRaiz]
        let lidos = Self.ler(raiz: raiz)
        cursos = lidos
        let id = cursoAtivo.id
        if let mesmo = lidos.first(where: { $0.id == id }) {
            mudarPara(mesmo)
        } else {
            let escolha = Self.escolher(definicoes.defaults.string(forKey: Self.chaveCursoAtivo), em: lidos)
            cursoEmFalta = escolha.emFalta
            mudarPara(escolha.curso)
        }
        if observador != nil { vigiar() }
    }
}
