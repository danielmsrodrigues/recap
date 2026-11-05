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

/// As preferências de um curso (para quem o Claude escreve, as línguas e a barra lateral), em `_recap/definicoes.json`:
/// é daí que todos os aparelhos as leem, e só se grava quando alguém as muda (ver `Library.alterarPreferencias`).
/// As línguas e a organização vão pelo `rawValue`: um valor que a outra versão não conheça é ignorado, mas não se perde.
struct DefinicoesPartilhadas: Codable, Equatable, Sendable {
    var contextoCurso: String
    var linguaApontamentos: String
    var idiomaAulas: String
    var organizacao: String
    var iniciosPeriodos: [Int]
    var duracaoCurso: Int

    static let ficheiro = "definicoes.json"

    /// Como numa instalação nova: espanhol e 4 anos, como até aqui.
    static let porDefeito = DefinicoesPartilhadas(
        contextoCurso: "", linguaApontamentos: LinguaApontamentos.ptPT.rawValue, idiomaAulas: IdiomaAula.espanhol.rawValue,
        organizacao: OrganizacaoCurso.anoESemestre.rawValue, iniciosPeriodos: CalendarioLetivo.porDefeito, duracaoCurso: 4)

    /// Para um curso novo: o contexto e o resto começam de novo, porque são deste curso. A língua dos apontamentos vem
    /// da do curso aberto, que costuma ser a mesma. A das aulas pede-se sempre: errada, uma transcrição fica para sempre.
    static func paraCursoNovo(idioma: IdiomaAula, como atual: DefinicoesPartilhadas) -> DefinicoesPartilhadas {
        var p = DefinicoesPartilhadas.porDefeito
        p.idioma = idioma
        p.lingua = atual.lingua
        return p
    }

    /// A língua em que o Claude escreve.
    var lingua: LinguaApontamentos {
        get { LinguaApontamentos(rawValue: linguaApontamentos) ?? .ptPT }
        set { linguaApontamentos = newValue.rawValue }
    }

    /// A língua em que as aulas são dadas (o Whisper transcreve nela).
    var idioma: IdiomaAula {
        get { IdiomaAula(rawValue: idiomaAulas) ?? .espanhol }
        set { idiomaAulas = newValue.rawValue }
    }

    var organizacaoCurso: OrganizacaoCurso {
        get { OrganizacaoCurso(rawValue: organizacao) ?? .anoESemestre }
        set { organizacao = newValue.rawValue }
    }

    /// Os meses em que começa cada período do ano letivo (`CalendarioLetivo`).
    var inicios: [Int] {
        get { CalendarioLetivo.valido(iniciosPeriodos) ? iniciosPeriodos : CalendarioLetivo.porDefeito }
        set { iniciosPeriodos = newValue }
    }

    /// Anos do curso, para as escolhas manuais de ano de cada cadeira.
    var duracao: Int {
        get { max(1, duracaoCurso) }
        set { duracaoCurso = newValue }
    }

    static func url(raiz: URL) -> URL {
        raiz.appending(path: Disco.pastaSistema).appending(path: ficheiro)
    }

    static func ler(raiz: URL) -> DefinicoesPartilhadas? {
        try? Disco.ler(DefinicoesPartilhadas.self, de: url(raiz: raiz))
    }

    /// Só escreve se mudou: cada escrita é um envio para o iCloud. Um ficheiro ainda por descarregar lê-se como nil e
    /// parecia diferente: substituí-lo levava esta cópia para cima da que vem a caminho.
    static func escrever(_ d: DefinicoesPartilhadas, raiz: URL, porDescarregar: (URL) -> Bool = Disco.porDescarregar) throws {
        // Ler primeiro: se faltar, pede o download.
        let atual = ler(raiz: raiz)
        guard !porDescarregar(url(raiz: raiz)), atual != d else { return }
        try FileManager.default.createDirectory(at: raiz.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)
        try Disco.escrever(d, em: url(raiz: raiz))
    }
}

extension DefinicoesPartilhadas {
    /// Um campo em falta não invalida o ficheiro: sem isto, um campo novo fazia as versões anteriores lerem nil e
    /// escreverem por cima. Na falta de um campo, o de `porDefeito`.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = Self.porDefeito
        contextoCurso = try c.decodeIfPresent(String.self, forKey: .contextoCurso) ?? p.contextoCurso
        linguaApontamentos = try c.decodeIfPresent(String.self, forKey: .linguaApontamentos) ?? p.linguaApontamentos
        idiomaAulas = try c.decodeIfPresent(String.self, forKey: .idiomaAulas) ?? p.idiomaAulas
        organizacao = try c.decodeIfPresent(String.self, forKey: .organizacao) ?? p.organizacao
        iniciosPeriodos = try c.decodeIfPresent([Int].self, forKey: .iniciosPeriodos) ?? p.iniciosPeriodos
        duracaoCurso = try c.decodeIfPresent(Int.self, forKey: .duracaoCurso) ?? p.duracaoCurso
    }
}

/// O ficheiro das preferências do curso existe mas ainda não se leu.
enum ErroPreferencias: LocalizedError {
    case porLer

    var errorDescription: String? {
        "As definições deste curso ainda não se leram: estão a chegar do iCloud, ou não se consegue ler o ficheiro _recap/definicoes.json. Tenta daqui a pouco."
    }
}

/// As preferências deste aparelho em `UserDefaults`. A chave API fica na Keychain e o prompt num ficheiro.
/// As de cada curso estão na `Library`.
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

    let defaults: UserDefaults

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
    /// Ao fim destes minutos de silêncio, uma aula em direto termina sozinha.
    var minutosSilencio: Int { didSet { defaults.set(minutosSilencio, forKey: "minutosSilencio") } }
    #endif
    /// A pasta das aulas, com todos os cursos. Vazio = a de `Disco.raizPorDefeito`.
    var pastaAulas: String { didSet { defaults.set(pastaAulas, forKey: "pastaAulas") } }
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
        #if os(macOS)
        let padrao = ConfigSlides()
        slidesLimiar = defaults.object(forKey: "slidesLimiar") as? Double ?? padrao.limiar
        slidesIntervalo = defaults.object(forKey: "slidesIntervalo") as? Double ?? padrao.intervalo
        slidesMaximo = defaults.object(forKey: "slidesMaximo") as? Int ?? padrao.maximo
        minutosSilencio = (defaults.object(forKey: "minutosSilencio") as? Int).flatMap { Self.opcoesMinutosSilencio.contains($0) ? $0 : nil }
            ?? Self.minutosSilencioPorDefeito
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

    /// O que as versões anteriores guardavam neste aparelho. Só serve de recurso a uma pasta sem `definicoes.json`
    /// (ver `Library`); as chaves ficam, para a app poder voltar a uma versão anterior.
    var preferenciasAntigas: DefinicoesPartilhadas {
        var p = DefinicoesPartilhadas.porDefeito
        if let c = defaults.string(forKey: "contextoCurso") { p.contextoCurso = c }
        if let l = defaults.string(forKey: "linguaApontamentos").flatMap(LinguaApontamentos.init) { p.lingua = l }
        if let i = defaults.string(forKey: "idiomaAulas").flatMap(IdiomaAula.init) { p.idioma = i }
        if let o = defaults.string(forKey: "organizacao").flatMap(OrganizacaoCurso.init) { p.organizacaoCurso = o }
        if let m = defaults.array(forKey: "iniciosPeriodos") as? [Int], CalendarioLetivo.valido(m) { p.inicios = m }
        if let d = defaults.object(forKey: "duracaoCurso") as? Int { p.duracao = max(1, d) }
        return p
    }

    #if os(macOS)
    /// 3 por defeito, como até aqui.
    static let minutosSilencioPorDefeito = 3
    static let opcoesMinutosSilencio = [1, 3, 5, 10, 15, 30, 60]

    /// "1 minuto", "5 minutos", "1 hora".
    static func nomeMinutos(_ minutos: Int) -> String {
        switch minutos {
        case 1: "1 minuto"
        case 60: "1 hora"
        default: "\(minutos) minutos"
        }
    }

    var limiteSilencio: Double { Double(minutosSilencio) * 60 }

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
