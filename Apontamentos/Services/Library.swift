import Foundation
import Observation
import Synchronization

/// Cadeiras e aulas lidas da pasta das aulas (`~/Aulas` por defeito). Não há base de dados: cada `recarregar()` volta a ler o disco.
@MainActor @Observable
final class Library {
    private(set) var raiz: URL
    /// Muda os grupos da barra lateral; o que está em `cadeira.json` não é tocado.
    var organizacao: OrganizacaoCurso { didSet { if organizacao != oldValue { recarregar() } } }
    /// Os meses em que começa cada período do ano letivo (ver `CalendarioLetivo`).
    var iniciosPeriodos: [Int] { didSet { if iniciosPeriodos != oldValue { recarregar() } } }
    /// Até onde vão as escolhas manuais de ano de uma cadeira.
    var duracaoCurso: Int
    private(set) var cadeiras: [Cadeira] = []
    /// Muda quando uma leitura do disco encontra algo diferente; as vistas usam-no para recarregar ficheiros.
    private(set) var versao = 0
    private(set) var erro: String?
    /// Avisa quando outro dispositivo (pelo iCloud Drive) ou outra app muda a pasta. Só depois de `vigiar()`.
    @ObservationIgnored private var observador: ObservadorPasta?

    init(raiz: URL = Disco.raizPorDefeito, organizacao: OrganizacaoCurso = .anoESemestre,
         iniciosPeriodos: [Int] = CalendarioLetivo.porDefeito, duracaoCurso: Int = 4) {
        self.raiz = raiz
        self.organizacao = organizacao
        self.iniciosPeriodos = iniciosPeriodos
        self.duracaoCurso = duracaoCurso
        recarregar()
    }

    /// Volta a ler o disco. Só avisa as vistas (`versao`) se algo mudou: cada ação pequena chamava aqui e todas as
    /// vistas abertas reliam a transcrição, os apontamentos e a pesquisa sem necessidade.
    ///
    /// Com `forcar`, avisa sempre: uma mudança vinda de fora (apontamentos editados no iPad, uma resposta nova)
    /// pode não mexer na lista de cadeiras e aulas, mas as vistas abertas têm de reler os ficheiros.
    func recarregar(forcar: Bool = false) {
        do {
            try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
            let novas = try Self.ler(raiz: raiz, organizacao: organizacao, inicios: iniciosPeriodos)
            let mudou = novas != cadeiras || erro != nil
            cadeiras = novas
            erro = nil
            if mudou || forcar { versao += 1 }
        } catch {
            erro = "Não foi possível ler \(raiz.path): \(error.localizedDescription)"
            versao += 1
        }
    }

    /// Passa a ler outra pasta. Com `mover`, as cadeiras da pasta atual vão para lá primeiro.
    func mudarRaiz(para nova: URL, mover: Bool) throws {
        let nova = nova.standardizedFileURL
        guard !nova.mesmoCaminho(raiz) else { return }
        if mover { try Self.moverCadeiras(de: raiz, para: nova) }
        raiz = nova
        recarregar()
        if observador != nil { vigiar() }
    }

    /// Passa a reler sozinha quando a pasta muda fora da app (por exemplo o iCloud a trazer o que se fez no iPad).
    func vigiar() {
        observador = ObservadorPasta(raiz) { [weak self] in self?.recarregar(forcar: true) }
    }

    /// Move cada pasta de `origem` para `destino`. Recusa antes de mexer em nada se uma já existir lá
    /// ou se uma pasta estiver dentro da outra.
    nonisolated static func moverCadeiras(de origem: URL, para destino: URL) throws {
        let fm = FileManager.default
        let o = origem.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let d = destino.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard !d.hasPrefix(o), !o.hasPrefix(d) else { throw ErroPasta.dentroDaOutra }
        guard fm.fileExists(atPath: origem.path) else { return }
        let itens = try fm.contentsOfDirectory(at: origem, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        let repetidos = itens.map(\.lastPathComponent).filter { fm.fileExists(atPath: destino.appending(path: $0).path) }
        guard repetidos.isEmpty else { throw ErroPasta.jaExiste(repetidos) }
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)
        for item in itens {
            try fm.moveItem(at: item, to: destino.appending(path: item.lastPathComponent))
        }
    }

    nonisolated static func ler(raiz: URL, organizacao: OrganizacaoCurso = .anoESemestre,
                                inicios: [Int] = CalendarioLetivo.porDefeito, hoje: Date = .now) throws -> [Cadeira] {
        let fm = FileManager.default
        let pastas = try fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        let lidas = pastas
            .filter { $0.lastPathComponent != Disco.pastaSistema && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { pasta in
                let nome = pasta.lastPathComponent
                let subpastas = (try? fm.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                let aulas = subpastas.compactMap { sub -> Aula? in
                    guard let meta = try? Disco.lerMeta(sub) else { return nil }
                    return Aula(
                        pasta: sub,
                        cadeira: nome,
                        meta: meta,
                        temTranscricao: Disco.existe(Disco.transcricaoJSON, em: sub),
                        temApontamentos: Disco.existe(Disco.apontamentosMD, em: sub),
                        temSlides: Disco.existe(Disco.slidesJSON, em: sub)
                    )
                }
                .sorted { ($0.meta.data, $0.meta.criadaEm) > ($1.meta.data, $1.meta.criadaEm) }
                return (nome: nome, pasta: pasta, meta: Disco.lerCadeira(pasta), aulas: aulas,
                        letivo: Semestre.letivo(aulas.last?.meta.data ?? hoje, inicios: inicios))
            }
        // O 1.º ano é o ano letivo da aula mais antiga; uma cadeira ainda sem aulas fica no semestre de hoje.
        let primeiro = lidas.map(\.letivo.inicio).min() ?? 0
        return lidas
            .map { c in
                Cadeira(nome: c.nome, pasta: c.pasta, meta: c.meta, aulas: c.aulas,
                        semestre: Semestre.grupo(escolhido: c.meta.semestre,
                                                 deduzido: Semestre(ano: c.letivo.inicio - primeiro + 1, numero: c.letivo.numero),
                                                 organizacao: organizacao))
            }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    // MARK: Consultas

    func aula(em pasta: URL) -> Aula? {
        for c in cadeiras { if let a = c.aulas.first(where: { $0.pasta.mesmoCaminho(pasta) }) { return a } }
        return nil
    }

    /// O URL tal como a biblioteca o lê do disco, para seleções e comparações baterem certo.
    private func canonico(_ pasta: URL) -> URL {
        aula(em: pasta)?.pasta ?? pasta
    }

    func cadeira(nome: String) -> Cadeira? {
        cadeiras.first { $0.nome == nome }
    }

    /// Os semestres que têm cadeiras, do mais recente para o mais antigo.
    var semestres: [Semestre] {
        Set(cadeiras.map(\.semestre)).sorted(by: >)
    }

    /// As cadeiras agrupadas por semestre, do mais recente para o mais antigo (para os seletores de cadeira).
    var cadeirasPorSemestre: [(semestre: Semestre, cadeiras: [Cadeira])] {
        semestres.map { s in (s, cadeiras.filter { $0.semestre == s }) }
    }

    /// "semestre", "trimestre"…, conforme o calendário letivo.
    var nomePeriodo: String { CalendarioLetivo.nomePeriodo(iniciosPeriodos) }

    /// "2.º ano · 1.º semestre", "1.º ano · 3.º trimestre"…
    func nome(_ semestre: Semestre) -> String { semestre.nome(periodo: nomePeriodo) }

    /// Nome do seletor da cadeira: "Semestre", "Trimestre"… ou "Ano".
    var rotuloPeriodo: String { organizacao.rotulo(periodo: nomePeriodo) }

    /// As escolhas manuais de semestre (ou ano) para uma cadeira, até ao fim do curso.
    func opcoesSemestre(_ cadeira: Cadeira) -> [Semestre] {
        organizacao.opcoes(ate: max(duracaoCurso, cadeira.semestre.ano), periodos: iniciosPeriodos.count)
    }

    /// Número da aula dentro da cadeira, pela ordem das datas (a primeira é 1).
    func numeroDaAula(_ aula: Aula) -> Int {
        let anteriores = cadeira(nome: aula.cadeira)?.aulas.filter {
            !$0.pasta.mesmoCaminho(aula.pasta) && ($0.meta.data, $0.meta.criadaEm) < (aula.meta.data, aula.meta.criadaEm)
        }
        return (anteriores?.count ?? 0) + 1
    }

    // MARK: Alterações

    @discardableResult
    func criarCadeira(nome: String) throws -> URL {
        let pasta = try pastaDaCadeira(nome)
        recarregar()
        return pasta
    }

    /// A pasta da cadeira, criada se ainda não existir (sem reler a biblioteca).
    private func pastaDaCadeira(_ nome: String) throws -> URL {
        let pasta = raiz.appending(path: Disco.nomeDePasta(nome), directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: pasta.path) {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            try Disco.escreverCadeira(CadeiraMeta(), em: pasta)
        }
        return pasta
    }

    #if os(macOS)
    func criarAula(cadeira: String, titulo: String, data: Date, video: URL?) throws -> URL {
        let pastaCadeira = try pastaDaCadeira(cadeira)
        let pasta = Disco.pastaLivre(Disco.nomePastaAula(titulo: titulo, data: data), em: pastaCadeira)
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        var meta = AulaMeta(titulo: titulo, data: data, video: video.map(VideoResolver.referencia(para:)))
        if video == nil { meta.origem = "direto" }
        try Disco.escreverMeta(meta, em: pasta)
        recarregar()
        return canonico(pasta)
    }
    #endif

    func atualizarMeta(em pasta: URL, _ alterar: (inout AulaMeta) -> Void) throws {
        var meta = try Disco.lerMeta(pasta)
        alterar(&meta)
        try Disco.escreverMeta(meta, em: pasta)
        recarregar()
    }

    func guardarCadeira(_ meta: CadeiraMeta, cadeira: Cadeira) throws {
        try Disco.escreverCadeira(meta, em: cadeira.pasta)
        recarregar()
    }

    /// Renomeia a pasta da cadeira. Devolve a nova pasta.
    @discardableResult
    func renomearCadeira(_ cadeira: Cadeira, para nome: String) throws -> URL {
        let novoNome = Disco.nomeDePasta(nome)
        guard novoNome != cadeira.pasta.lastPathComponent else { return cadeira.pasta }
        let destino = raiz.appending(path: novoNome, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: destino.path) else {
            throw NSError(domain: "Recap", code: 20, userInfo: [NSLocalizedDescriptionKey: "Já existe uma cadeira chamada \"\(novoNome)\"."])
        }
        try FileManager.default.moveItem(at: cadeira.pasta, to: destino)
        recarregar()
        return destino
    }

    /// Muda título, data ou cadeira de uma aula; a pasta é renomeada ou movida para acompanhar. Devolve a nova pasta.
    func editarAula(_ aula: Aula, titulo: String, data: Date, cadeira: String) throws -> URL {
        var meta = aula.meta
        if meta.titulo != titulo { meta.tituloManual = true }
        meta.titulo = titulo
        meta.data = data
        try Disco.escreverMeta(meta, em: aula.pasta)

        let pastaCadeira = raiz.appending(path: Disco.nomeDePasta(cadeira), directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: pastaCadeira.path) {
            try FileManager.default.createDirectory(at: pastaCadeira, withIntermediateDirectories: true)
            try Disco.escreverCadeira(CadeiraMeta(), em: pastaCadeira)
        }
        let nome = Disco.nomePastaAula(titulo: titulo, data: data)
        var destino = aula.pasta
        if aula.pasta.deletingLastPathComponent().standardizedFileURL != pastaCadeira.standardizedFileURL
            || aula.pasta.lastPathComponent != nome {
            destino = Disco.pastaLivre(nome, em: pastaCadeira)
            try FileManager.default.moveItem(at: aula.pasta, to: destino)
        }
        recarregar()
        return canonico(destino)
    }

    func definirRevista(_ revista: Bool, em pasta: URL) throws {
        try atualizarMeta(em: pasta) { $0.revista = revista }
    }

    #if os(macOS)
    /// Junta a `segunda` gravação a seguir à `primeira` (ver `JuntarAulas`) e manda a pasta da segunda para o Lixo.
    /// Os apontamentos da primeira ficam como estavam: quem chama gera-os de novo. Devolve a pasta da primeira.
    func juntar(_ segunda: Aula, a primeira: Aula) throws -> URL {
        try JuntarAulas.juntar(segunda.pasta, a: primeira.pasta)
        try FileManager.default.trashItem(at: segunda.pasta, resultingItemURL: nil)
        recarregar()
        return canonico(primeira.pasta)
    }

    /// Vai para o Lixo (recuperável), não é apagado.
    func moverParaLixo(_ pasta: URL) throws {
        try FileManager.default.trashItem(at: pasta, resultingItemURL: nil)
        recarregar()
    }
    #endif
}

extension URL {
    /// Compara caminhos de ficheiros ignorando symlinks (/var ↔ /private/var) e a normalização Unicode dos acentos.
    func mesmoCaminho(_ outro: URL) -> Bool {
        self == outro || caminhoCanonico == outro.caminhoCanonico
    }

    /// Resolver symlinks são várias chamadas ao sistema por componente, e isto corre em `body` em loops
    /// (cada linha da barra lateral contra cada job): guarda-se o resultado por caminho.
    private var caminhoCanonico: String {
        let bruto = standardizedFileURL.path
        if let feito = Self.canonicos.withLock({ $0[bruto] }) { return feito }
        let feito = standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        Self.canonicos.withLock { cache in
            if cache.count > 4000 { cache.removeAll(keepingCapacity: true) }
            cache[bruto] = feito
        }
        return feito
    }

    private static let canonicos = Mutex<[String: String]>([:])
}

enum ErroPasta: LocalizedError {
    case dentroDaOutra
    case jaExiste([String])

    var errorDescription: String? {
        switch self {
        case .dentroDaOutra: "A pasta nova não pode estar dentro da atual, nem a atual dentro da nova."
        case .jaExiste(let nomes): "A pasta nova já tem \(nomes.joined(separator: ", ")). Nada foi movido."
        }
    }
}
