import Foundation
import Observation

enum Esforco: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high, xhigh, max
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .low: "Baixo"
        case .medium: "Médio"
        case .high: "Alto"
        case .xhigh: "Muito alto"
        case .max: "Máximo"
        }
    }
}

enum MotorTipo: String, CaseIterable, Identifiable, Sendable {
    #if os(macOS)
    /// Só no Mac: o iOS não corre processos.
    case claudeCode
    #endif
    #if !os(macOS)
    /// Só no iOS: o pedido vai ao Recap do Mac, que responde com o Claude Code (ver `PonteMac`).
    case mac
    #endif
    case api
    var id: String { rawValue }
    var nome: String {
        switch self {
        #if os(macOS)
        case .claudeCode: "Claude Code (subscrição)"
        #else
        case .mac: "Recap no Mac (subscrição)"
        #endif
        case .api: "API da Anthropic"
        }
    }

    #if os(macOS)
    static let porDefeito = MotorTipo.claudeCode
    #else
    static let porDefeito = MotorTipo.mac
    #endif
}

/// As preferências de que o estudo precisa (os prompts das perguntas, exercícios e ligações, e a barra lateral),
/// escritas pelo Mac em `_recap/definicoes.json`: o `UserDefaults` não passa para o iPad e o iPhone.
/// As línguas e a organização vão pelo `rawValue`: um valor que a outra versão não conheça é ignorado.
struct DefinicoesPartilhadas: Codable, Equatable, Sendable {
    var contextoCurso: String
    var linguaApontamentos: String
    var idiomaAulas: String
    var organizacao: String
    var iniciosPeriodos: [Int]
    var duracaoCurso: Int

    static let ficheiro = "definicoes.json"

    static func url(raiz: URL) -> URL {
        raiz.appending(path: Disco.pastaSistema).appending(path: ficheiro)
    }

    static func ler(raiz: URL) -> DefinicoesPartilhadas? {
        try? Disco.ler(DefinicoesPartilhadas.self, de: url(raiz: raiz))
    }

    /// Só escreve se mudou: cada escrita é um envio para o iCloud.
    static func escrever(_ d: DefinicoesPartilhadas, raiz: URL) throws {
        guard ler(raiz: raiz) != d else { return }
        try FileManager.default.createDirectory(at: raiz.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)
        try Disco.escrever(d, em: url(raiz: raiz))
    }
}

/// Preferências da app em `UserDefaults`. A chave API fica na Keychain e o prompt num ficheiro.
@MainActor @Observable
final class Definicoes {
    static let modeloClaudePorDefeito = "claude-sonnet-5-5"

    /// Os modelos atuais do Claude, para o menu das Definições (platform.claude.com/docs/en/about-claude/models,
    /// consultada a 2026-10-21). Servem tanto ao Claude Code como à API.
    static let modelosClaude: [(id: String, nome: String)] = [
        ("claude-sonnet-5-5", "Sonnet 5.5 (recomendado)"),
        ("claude-opus-5-5", "Opus 5.5 (mais cuidado, ~2× o preço)"),
        ("claude-fable-5-1", "Fable 5.1 (o mais capaz, ~5× o preço)"),
        ("claude-haiku-5-5", "Haiku 5.5 (rápido e barato)"),
    ]

    private let defaults: UserDefaults

    var motor: MotorTipo { didSet { defaults.set(motor.rawValue, forKey: "motor") } }
    #if os(macOS)
    /// Vazio = procurar o `claude` nos sítios habituais.
    var caminhoClaude: String { didSet { defaults.set(caminhoClaude, forKey: "caminhoClaude") } }
    #endif
    var modeloClaude: String { didSet { defaults.set(modeloClaude, forKey: "modeloClaude") } }
    var esforco: Esforco { didSet { defaults.set(esforco.rawValue, forKey: "esforco") } }
    #if os(macOS)
    /// Responder aos pedidos ao Claude feitos no iPad e no iPhone (`PonteMac`).
    var responderPedidos: Bool { didSet { defaults.set(responderPedidos, forKey: "responderPedidos") } }
    var modeloWhisper: WhisperModelo { didSet { defaults.set(modeloWhisper.rawValue, forKey: "modeloWhisper") } }
    var slidesLimiar: Double { didSet { defaults.set(slidesLimiar, forKey: "slidesLimiar") } }
    var slidesIntervalo: Double { didSet { defaults.set(slidesIntervalo, forKey: "slidesIntervalo") } }
    var slidesMaximo: Int { didSet { defaults.set(slidesMaximo, forKey: "slidesMaximo") } }
    #endif
    /// Vazio = `~/Aulas`.
    var pastaAulas: String { didSet { defaults.set(pastaAulas, forKey: "pastaAulas") } }
    var organizacao: OrganizacaoCurso { didSet { defaults.set(organizacao.rawValue, forKey: "organizacao") } }
    /// Os meses em que começa cada período do ano letivo (`CalendarioLetivo`). Setembro e fevereiro por defeito.
    var iniciosPeriodos: [Int] { didSet { defaults.set(iniciosPeriodos, forKey: "iniciosPeriodos") } }
    /// Anos do curso, para as escolhas manuais de ano de cada cadeira. 4 por defeito, como até aqui.
    var duracaoCurso: Int { didSet { defaults.set(duracaoCurso, forKey: "duracaoCurso") } }
    /// A língua em que as aulas são dadas (o Whisper transcreve nela). Espanhol por defeito, como até aqui.
    var idiomaAulas: IdiomaAula { didSet { defaults.set(idiomaAulas.rawValue, forKey: "idiomaAulas") } }
    /// O curso, para o Claude saber para quem escreve: "licenciatura em X, 1.º ano, universidade Y". Vazio = genérico.
    var contextoCurso: String { didSet { defaults.set(contextoCurso, forKey: "contextoCurso") } }
    /// A língua em que o Claude escreve. Português de Portugal por defeito, como até aqui.
    var linguaApontamentos: LinguaApontamentos { didSet { defaults.set(linguaApontamentos.rawValue, forKey: "linguaApontamentos") } }
    var precosPersonalizados: [String: Preco] {
        didSet { defaults.set(try? JSONEncoder().encode(precosPersonalizados), forKey: "precosPersonalizados") }
    }
    /// Muda quando a chave é guardada ou apagada, para as vistas reagirem.
    private(set) var temChaveAPI: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        motor = defaults.string(forKey: "motor").flatMap(MotorTipo.init) ?? .porDefeito
        #if os(macOS)
        caminhoClaude = defaults.string(forKey: "caminhoClaude") ?? ""
        #endif
        modeloClaude = defaults.string(forKey: "modeloClaude") ?? Self.modeloClaudePorDefeito
        esforco = defaults.string(forKey: "esforco").flatMap(Esforco.init) ?? .high
        #if os(macOS)
        responderPedidos = defaults.object(forKey: "responderPedidos") as? Bool ?? true
        modeloWhisper = defaults.string(forKey: "modeloWhisper").flatMap(WhisperModelo.init) ?? .largeV3Turbo
        #endif
        pastaAulas = defaults.string(forKey: "pastaAulas") ?? ""
        organizacao = defaults.string(forKey: "organizacao").flatMap(OrganizacaoCurso.init) ?? .anoESemestre
        iniciosPeriodos = (defaults.array(forKey: "iniciosPeriodos") as? [Int]).flatMap { CalendarioLetivo.valido($0) ? $0 : nil }
            ?? CalendarioLetivo.porDefeito
        duracaoCurso = max(1, defaults.object(forKey: "duracaoCurso") as? Int ?? 4)
        idiomaAulas = defaults.string(forKey: "idiomaAulas").flatMap(IdiomaAula.init) ?? .espanhol
        contextoCurso = defaults.string(forKey: "contextoCurso") ?? ""
        linguaApontamentos = defaults.string(forKey: "linguaApontamentos").flatMap(LinguaApontamentos.init) ?? .ptPT
        #if os(macOS)
        let padrao = ConfigSlides()
        slidesLimiar = defaults.object(forKey: "slidesLimiar") as? Double ?? padrao.limiar
        slidesIntervalo = defaults.object(forKey: "slidesIntervalo") as? Double ?? padrao.intervalo
        slidesMaximo = defaults.object(forKey: "slidesMaximo") as? Int ?? padrao.maximo
        #endif
        precosPersonalizados = defaults.data(forKey: "precosPersonalizados")
            .flatMap { try? JSONDecoder().decode([String: Preco].self, from: $0) } ?? [:]
        temChaveAPI = KeychainStore.temChave()
    }

    /// Em DEBUG, `APONTAMENTOS_RAIZ` ganha a tudo (testes manuais sem tocar nas aulas reais).
    var raizAulas: URL {
        #if DEBUG
        if let p = ProcessInfo.processInfo.environment["APONTAMENTOS_RAIZ"] { return URL(fileURLWithPath: p, isDirectory: true) }
        #endif
        return pastaAulas.isEmpty ? Disco.raizPorDefeito : URL(fileURLWithPath: pastaAulas, isDirectory: true)
    }

    var tabelaPrecos: TabelaPrecos { TabelaPrecos(personalizados: precosPersonalizados) }

    var partilhadas: DefinicoesPartilhadas {
        DefinicoesPartilhadas(contextoCurso: contextoCurso, linguaApontamentos: linguaApontamentos.rawValue,
                              idiomaAulas: idiomaAulas.rawValue, organizacao: organizacao.rawValue,
                              iniciosPeriodos: iniciosPeriodos, duracaoCurso: duracaoCurso)
    }

    /// Passa a usar as preferências escritas pelo Mac (no iPad e no iPhone, ao abrir a pasta).
    func aplicar(_ p: DefinicoesPartilhadas) {
        contextoCurso = p.contextoCurso
        duracaoCurso = max(1, p.duracaoCurso)
        if let l = LinguaApontamentos(rawValue: p.linguaApontamentos) { linguaApontamentos = l }
        if let i = IdiomaAula(rawValue: p.idiomaAulas) { idiomaAulas = i }
        if let o = OrganizacaoCurso(rawValue: p.organizacao) { organizacao = o }
        if CalendarioLetivo.valido(p.iniciosPeriodos) { iniciosPeriodos = p.iniciosPeriodos }
    }

    /// Um prompt com os marcadores (`{{contexto}}`, `{{idioma}}`…) já substituídos pelo curso e pelas línguas escolhidos.
    /// `idioma` é o da aula, quando não é o das Definições (uma cadeira dada noutra língua).
    func prompt(_ texto: String, idioma: IdiomaAula? = nil) -> String {
        ContextoCurso.aplicar(texto, idioma: idioma ?? idiomaAulas, contexto: contextoCurso, apontamentos: linguaApontamentos)
    }

    /// A língua em que a cadeira é dada: a dela, se a tiver, ou a das Definições.
    func idioma(da cadeira: Cadeira?) -> IdiomaAula {
        cadeira?.meta.idioma ?? idiomaAulas
    }

    /// O prompt de sistema dos apontamentos de uma aula transcrita em `idioma`, pronto a enviar.
    func promptApontamentos(idioma: IdiomaAula) -> String { prompt(PromptStore.ler(), idioma: idioma) }

    #if os(macOS)
    func configSlides(regiao: RegiaoIgnorar) -> ConfigSlides {
        ConfigSlides(intervalo: slidesIntervalo, limiar: slidesLimiar, maximo: slidesMaximo, regiao: regiao)
    }

    /// Onde está o `claude`. Procurá-lo são até cinco acessos ao disco, e isto é lido em `body` por cada tecla
    /// escrita no painel das perguntas: fica guardado até o caminho mudar ou a app voltar a primeiro plano.
    var claudeCode: URL? {
        if let cache = claudeCodeCache, cache.caminho == caminhoClaude { return cache.url }
        let url = ClaudeCodeClient.localizar(personalizado: caminhoClaude)
        claudeCodeCache = (caminhoClaude, url)
        return url
    }

    @ObservationIgnored private var claudeCodeCache: (caminho: String, url: URL?)?

    /// Volta a procurar o `claude` (depois de o instalar, por exemplo).
    func esquecerClaudeCode() { claudeCodeCache = nil }
    #endif

    /// O gerador com o motor, o modelo e o esforço escolhidos; falha se faltar o Claude Code ou a chave.
    /// `motor`: outro que não o das Definições.
    func gerador(esforco: Esforco? = nil, motor tipo: MotorTipo? = nil) throws -> NotesGenerator {
        let motor: Motor
        switch tipo ?? self.motor {
        #if os(macOS)
        case .claudeCode:
            guard let url = claudeCode else { throw ErroClaudeCode.naoEncontrado }
            motor = .claudeCode(ClaudeCodeClient(executavel: url))
        #else
        case .mac:
            // Os pedidos pelo Mac não passam por aqui: o `Estudo` entrega-os inteiros (`PonteMac`).
            throw ErroClaude.semChave
        #endif
        case .api:
            guard let chave = KeychainStore.chaveAPI() else { throw ErroClaude.semChave }
            motor = .api(AnthropicClient(chave: chave))
        }
        return NotesGenerator(motor: motor, modelo: modeloClaude, esforco: esforco ?? self.esforco, precos: tabelaPrecos)
    }

    /// nil = pronto a gerar; caso contrário, o que falta.
    var faltaParaGerar: String? {
        switch motor {
        #if os(macOS)
        case .claudeCode: claudeCode == nil ? ErroClaudeCode.naoEncontrado.localizedDescription : nil
        #else
        case .mac: nil
        #endif
        case .api: temChaveAPI ? nil : ErroClaude.semChave.localizedDescription
        }
    }

    func guardarChaveAPI(_ chave: String) throws {
        try KeychainStore.guardar(chave)
        temChaveAPI = KeychainStore.temChave()
    }

    func apagarChaveAPI() throws {
        try KeychainStore.apagar()
        temChaveAPI = false
    }
}
