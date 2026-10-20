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
    case claudeCode, api
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .claudeCode: "Claude Code (subscrição)"
        case .api: "API da Anthropic"
        }
    }
}

/// Preferências da app em `UserDefaults`. A chave API fica na Keychain e o prompt num ficheiro.
@MainActor @Observable
final class Definicoes {
    static let modeloClaudePorDefeito = "claude-sonnet-5-5"

    private let defaults: UserDefaults

    var motor: MotorTipo { didSet { defaults.set(motor.rawValue, forKey: "motor") } }
    /// Vazio = procurar o `claude` nos sítios habituais.
    var caminhoClaude: String { didSet { defaults.set(caminhoClaude, forKey: "caminhoClaude") } }
    var modeloClaude: String { didSet { defaults.set(modeloClaude, forKey: "modeloClaude") } }
    var esforco: Esforco { didSet { defaults.set(esforco.rawValue, forKey: "esforco") } }
    var modeloWhisper: WhisperModelo { didSet { defaults.set(modeloWhisper.rawValue, forKey: "modeloWhisper") } }
    var slidesLimiar: Double { didSet { defaults.set(slidesLimiar, forKey: "slidesLimiar") } }
    var slidesIntervalo: Double { didSet { defaults.set(slidesIntervalo, forKey: "slidesIntervalo") } }
    var slidesMaximo: Int { didSet { defaults.set(slidesMaximo, forKey: "slidesMaximo") } }
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
    var precosPersonalizados: [String: Preco] {
        didSet { defaults.set(try? JSONEncoder().encode(precosPersonalizados), forKey: "precosPersonalizados") }
    }
    /// Muda quando a chave é guardada ou apagada, para as vistas reagirem.
    private(set) var temChaveAPI: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        motor = defaults.string(forKey: "motor").flatMap(MotorTipo.init) ?? .claudeCode
        caminhoClaude = defaults.string(forKey: "caminhoClaude") ?? ""
        modeloClaude = defaults.string(forKey: "modeloClaude") ?? Self.modeloClaudePorDefeito
        esforco = defaults.string(forKey: "esforco").flatMap(Esforco.init) ?? .high
        modeloWhisper = defaults.string(forKey: "modeloWhisper").flatMap(WhisperModelo.init) ?? .largeV3Turbo
        pastaAulas = defaults.string(forKey: "pastaAulas") ?? ""
        organizacao = defaults.string(forKey: "organizacao").flatMap(OrganizacaoCurso.init) ?? .anoESemestre
        iniciosPeriodos = (defaults.array(forKey: "iniciosPeriodos") as? [Int]).flatMap { CalendarioLetivo.valido($0) ? $0 : nil }
            ?? CalendarioLetivo.porDefeito
        duracaoCurso = max(1, defaults.object(forKey: "duracaoCurso") as? Int ?? 4)
        idiomaAulas = defaults.string(forKey: "idiomaAulas").flatMap(IdiomaAula.init) ?? .espanhol
        contextoCurso = defaults.string(forKey: "contextoCurso") ?? ""
        let padrao = ConfigSlides()
        slidesLimiar = defaults.object(forKey: "slidesLimiar") as? Double ?? padrao.limiar
        slidesIntervalo = defaults.object(forKey: "slidesIntervalo") as? Double ?? padrao.intervalo
        slidesMaximo = defaults.object(forKey: "slidesMaximo") as? Int ?? padrao.maximo
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

    /// Um prompt com `{{contexto}}` e `{{idioma}}` já substituídos pelo curso e pela língua escolhidos.
    func prompt(_ texto: String) -> String {
        ContextoCurso.aplicar(texto, idioma: idiomaAulas, contexto: contextoCurso)
    }

    /// O prompt de sistema dos apontamentos, pronto a enviar.
    var promptApontamentos: String { prompt(PromptStore.ler()) }

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

    /// O gerador com o motor, o modelo e o esforço escolhidos; falha se faltar o Claude Code ou a chave.
    func gerador(esforco: Esforco? = nil) throws -> NotesGenerator {
        let motor: Motor
        switch self.motor {
        case .claudeCode:
            guard let url = claudeCode else { throw ErroClaudeCode.naoEncontrado }
            motor = .claudeCode(ClaudeCodeClient(executavel: url))
        case .api:
            guard let chave = KeychainStore.chaveAPI() else { throw ErroClaude.semChave }
            motor = .api(AnthropicClient(chave: chave))
        }
        return NotesGenerator(motor: motor, modelo: modeloClaude, esforco: esforco ?? self.esforco, precos: tabelaPrecos)
    }

    /// nil = pronto a gerar; caso contrário, o que falta.
    var faltaParaGerar: String? {
        switch motor {
        case .claudeCode: claudeCode == nil ? ErroClaudeCode.naoEncontrado.localizedDescription : nil
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
