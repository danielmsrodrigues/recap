import CryptoKit
import Foundation
import Observation

/// "Sobre a cadeira": a ficha de cada cadeira (avaliação, datas, programa, regras…), fora dos apontamentos.
///
///     ~/Aulas/<cadeira>/sobre.md                a ficha (editável)
///     ~/Aulas/<cadeira>/sobre.json              que aulas (e que programa) já entraram na ficha
///     ~/Aulas/<cadeira>/programa.pdf            o programa oficial da cadeira, se o estudante o juntar
///     ~/Aulas/<cadeira>/<aula>/sobre-aula.md    o que essa aula disse sobre a cadeira
///
/// O Claude escreve essa parte como uma secção dos apontamentos ("## Sobre a cadeira"); a app tira-a de lá
/// (`separar`) e junta-a à ficha com um pedido curto, com pouco raciocínio (`Fichas`). Não com um modelo mais
/// pequeno: a ficha é reescrita a cada aula e o Haiku deixava gralhas nos dados ("1..ª convocatória").
enum FichaCadeira {
    static let fichaMD = "sobre.md"
    static let registoJSON = "sobre.json"
    static let excertoMD = "sobre-aula.md"
    static let programaPDF = "programa.pdf"
    /// Chave do programa no registo (as das aulas são nomes de pasta, que começam pela data).
    static let chavePrograma = "programa"
    static let tituloSeccao = "Sobre a cadeira"

    /// Aulas já juntadas à ficha: nome da pasta da aula (ou `chavePrograma`) → hash do que se juntou.
    struct Registo: Codable, Equatable, Sendable {
        var aulas: [String: String] = [:]
        /// Aulas já vistas pela migração dos apontamentos antigos (não voltam a ser lidas ao arrancar).
        var migradas: Set<String> = []
        /// O programa tal como foi visto da última vez, para não o ler e resumir a cada arranque.
        var programa: ProgramaVisto?

        struct ProgramaVisto: Codable, Equatable, Sendable {
            var tamanho: Int
            var modificado: Date
            var hash: String
        }

        init(aulas: [String: String] = [:]) { self.aulas = aulas }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            aulas = try c.decodeIfPresent([String: String].self, forKey: .aulas) ?? [:]
            migradas = try c.decodeIfPresent(Set<String>.self, forKey: .migradas) ?? []
            programa = try c.decodeIfPresent(ProgramaVisto.self, forKey: .programa)
        }
    }

    // MARK: Separar dos apontamentos

    /// Tira a secção "## Sobre a cadeira" dos apontamentos, até ao título seguinte de nível 1 ou 2.
    /// `sobre` é o corpo da secção (sem o título), ou nil se não houver.
    static func separar(_ markdown: String) -> (apontamentos: String, sobre: String?) {
        let linhas = markdown.components(separatedBy: "\n")
        var emCodigo = false
        var inicio: Int?, fim = linhas.count
        for (i, linha) in linhas.enumerated() {
            if linha.hasPrefix("```") { emCodigo.toggle() }
            guard !emCodigo else { continue }
            if inicio == nil {
                if eTituloSobre(linha) { inicio = i }
            } else if linha.hasPrefix("# ") || linha.hasPrefix("## ") {
                fim = i
                break
            }
        }
        guard let inicio else { return (markdown, nil) }
        let corpo = linhas[(inicio + 1)..<fim].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        var resto = Array(linhas[..<inicio]) + Array(linhas[fim...])
        // Sem linhas em branco a dobrar onde estava a secção.
        resto = resto.enumerated().filter { i, l in !(l.trimmingCharacters(in: .whitespaces).isEmpty && i > 0
            && resto[i - 1].trimmingCharacters(in: .whitespaces).isEmpty) }.map(\.element)
        return (resto.joined(separator: "\n"), corpo.isEmpty ? nil : corpo)
    }

    private static func eTituloSobre(_ linha: String) -> Bool {
        guard linha.hasPrefix("## ") else { return false }
        return linha.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(tituloSeccao.lowercased())
    }

    // MARK: Ficheiros

    /// O ficheiro da ficha; é também o que se seleciona na barra lateral.
    static func url(_ cadeira: URL) -> URL { cadeira.appending(path: fichaMD) }

    static func lerFicha(_ cadeira: URL) -> String? {
        try? String(contentsOf: url(cadeira), encoding: .utf8)
    }

    static func escreverFicha(_ texto: String, em cadeira: URL) throws {
        try texto.write(to: url(cadeira), atomically: true, encoding: .utf8)
    }

    static func lerRegisto(_ cadeira: URL) -> Registo {
        (try? Disco.ler(Registo.self, de: cadeira.appending(path: registoJSON))) ?? Registo()
    }

    static func escreverRegisto(_ r: Registo, em cadeira: URL) throws {
        try Disco.escrever(r, em: cadeira.appending(path: registoJSON))
    }

    static func lerExcerto(_ aula: URL) -> String? {
        try? String(contentsOf: aula.appending(path: excertoMD), encoding: .utf8)
    }

    /// Guarda o que a aula disse sobre a cadeira; sem nada, apaga o excerto antigo.
    static func escreverExcerto(_ texto: String?, em aula: URL) throws {
        let url = aula.appending(path: excertoMD)
        if let texto { try texto.write(to: url, atomically: true, encoding: .utf8) }
        else { try? FileManager.default.removeItem(at: url) }
    }

    static func hash(_ texto: String) -> String { hash(Data(texto.utf8)) }

    static func hash(_ dados: Data) -> String {
        SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Programa

    static func urlPrograma(_ cadeira: URL) -> URL { cadeira.appending(path: programaPDF) }

    static func temPrograma(_ cadeira: URL) -> Bool { FileManager.default.fileExists(atPath: urlPrograma(cadeira).path) }

    /// Copia o PDF do programa para a cadeira, no lugar do anterior (que vai para o Lixo).
    static func juntarPrograma(_ origem: URL, em cadeira: URL) throws {
        let tamanho = (try? origem.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard tamanho <= Disco.tamanhoMaximoPDF else {
            throw NSError(domain: "Recap", code: 30, userInfo: [NSLocalizedDescriptionKey:
                "O PDF tem \(tamanho / 1_048_576) MB; o máximo é \(Disco.tamanhoMaximoPDF / 1_048_576) MB."])
        }
        let destino = urlPrograma(cadeira)
        if FileManager.default.fileExists(atPath: destino.path) { try FileManager.default.trashItem(at: destino, resultingItemURL: nil) }
        try FileManager.default.copyItem(at: origem, to: destino)
    }

    /// O programa vai para o Lixo; o que já entrou na ficha fica.
    static func removerPrograma(em cadeira: URL) throws {
        try FileManager.default.trashItem(at: urlPrograma(cadeira), resultingItemURL: nil)
        var registo = lerRegisto(cadeira)
        registo.aulas[chavePrograma] = nil
        try escreverRegisto(registo, em: cadeira)
    }

    /// Há um programa que a ficha ainda não tem (novo ou trocado).
    static func programaPendente(_ cadeira: URL) -> Bool {
        guard let hash = hashDoPrograma(cadeira) else { return false }
        return lerRegisto(cadeira).aulas[chavePrograma] != hash
    }

    /// O SHA-256 do programa, calculado só quando o ficheiro muda de tamanho ou de data (pode ter 24 MB).
    static func hashDoPrograma(_ cadeira: URL) -> String? {
        let url = urlPrograma(cadeira)
        guard let valores = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let tamanho = valores.fileSize, let modificado = valores.contentModificationDate
        else { return nil }
        var registo = lerRegisto(cadeira)
        if let visto = registo.programa, visto.tamanho == tamanho, visto.modificado == modificado { return visto.hash }
        guard let dados = try? Data(contentsOf: url) else { return nil }
        let h = hash(dados)
        registo.programa = Registo.ProgramaVisto(tamanho: tamanho, modificado: modificado, hash: h)
        try? escreverRegisto(registo, em: cadeira)
        return h
    }

    /// Aulas anteriores à ficha (apontamentos ainda com a secção): passa a secção para o excerto.
    @discardableResult
    static func migrar(_ aula: URL) throws -> Bool {
        guard lerExcerto(aula) == nil, let notas = Disco.lerApontamentos(aula) else { return false }
        let (apontamentos, sobre) = separar(notas)
        guard let sobre else { return false }
        try escreverExcerto(sobre, em: aula)
        try Disco.escreverApontamentos(apontamentos, em: aula)
        return true
    }

    /// Aulas com um excerto que a ficha ainda não tem (novas, ou regeneradas), da mais antiga para a mais recente.
    static func pendentes(_ cadeira: Cadeira) -> [Aula] {
        let registo = lerRegisto(cadeira.pasta)
        return cadeira.aulas
            .filter { a in lerExcerto(a.pasta).map { registo.aulas[a.pasta.lastPathComponent] != hash($0) } ?? false }
            .sorted { ($0.meta.data, $0.meta.criadaEm) < ($1.meta.data, $1.meta.criadaEm) }
    }

    // MARK: Pedido

    static let sistema = """
    Manténs a ficha de uma cadeira universitária: o que um aluno precisa de consultar sobre a cadeira (avaliação, \
    datas, programa, regras…), não a matéria. Recebes a ficha atual (pode estar vazia) e o que uma aula disse sobre \
    a cadeira. Devolves a ficha completa e atualizada, em Markdown, e nada mais (sem comentários nem blocos de código).

    - Começa por "# Sobre a cadeira". Depois uma secção "## " por assunto, por esta ordem quando houver o que pôr: \
    Cadeira e professor, Avaliação, Datas, Programa, Sessões, Atividades, Exame, Ferramentas, Materiais e contactos, \
    Bibliografia, Regras, Recomendações, Slides dados. Sem secções vazias.
    - Tópicos de uma linha; uma tabela só se for mais curta (por exemplo, datas de entrega). Cada facto uma só vez. \
    Datas, horas, pesos e mínimos exatos.
    - No fim de cada tópico, de onde veio: "(Programa)", "(Aula 1)", "(Aulas 1 e 3)".
    - Junta o que é novo ao que já lá está. O que a aula confirma perde o "(por confirmar)". O que mudou (uma data \
    adiada, um peso diferente) fica com o valor novo e o antigo riscado: "~~10/11~~ 2/12 (mudou na Aula 3)".
    - Se a aula já tinha entrado na ficha (vem indicado), o excerto novo substitui o que veio dela: não dupliques.
    - Mantém tal como estão os tópicos que a aula não muda, incluindo o que o estudante escreveu ou corrigiu à mão. \
    Nunca apagues um tópico só porque a aula não fala dele.
    - "Slides dados": uma linha por aula com as páginas dadas de cada PDF e as que ficaram por dar.
    - Português de Portugal.
    """

    private static func fichaAtual(_ ficha: String?) -> String {
        ficha?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? ficha! : "(vazia)"
    }

    static func conteudo(ficha: String?, excerto: String, aula: String, jaJuntada: Bool) -> [BlocoConteudo] {
        let atual = fichaAtual(ficha)
        let nota = jaJuntada ? "\n\nEsta aula já tinha entrado na ficha: substitui o que veio dela por este excerto." : ""
        return [.texto("""
        Ficha atual:

        <ficha>
        \(atual)
        </ficha>

        O que a \(aula) disse sobre a cadeira:

        <aula>
        \(excerto)
        </aula>\(nota)

        Devolve a ficha completa e atualizada.
        """)]
    }

    static func conteudoPrograma(ficha: String?, pdf: Data, jaJuntado: Bool) -> [BlocoConteudo] {
        let nota = jaJuntado ? " Este programa substitui um anterior: o que veio do anterior dá lugar ao que este diz." : ""
        return [
            .texto("Ficha atual:\n\n<ficha>\n\(fichaAtual(ficha))\n</ficha>\n\nPrograma oficial da cadeira (PDF dado pelo professor):"),
            .documentoPDF(base64: pdf.base64EncodedString()),
            .texto("""
            Junta à ficha o que o programa diz sobre a cadeira: identificação, professor, avaliação, datas, programa \
            (temas e subtemas, pela ordem), sessões, atividades, bibliografia, regras. A origem destes tópicos é \
            "(Programa)". O programa é a referência para os títulos dos temas e para o que é oficial; se uma aula disse \
            outra coisa, ficam os dois, com a origem de cada um.\(nota)

            Devolve a ficha completa e atualizada.
            """),
        ]
    }

    /// A resposta como ficha: sem cercas de código à volta e com o título certo.
    static func limpar(_ resposta: String) -> String {
        var t = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !t.hasPrefix("# ") { t = "# \(tituloSeccao)\n\n" + t }
        return t + "\n"
    }
}

/// Mantém as fichas das cadeiras: junta-lhes, uma a uma, as aulas que trouxeram algo novo.
@MainActor @Observable
final class Fichas {
    /// Cadeiras com a ficha a ser atualizada (caminho da pasta) e a aula que está a entrar.
    private(set) var emCurso: [String: String] = [:]
    private(set) var erros: [String: String] = [:]
    /// Muda quando uma ficha é gravada (as vistas voltam a ler do disco).
    private(set) var versao = 0
    @ObservationIgnored private var repetir: Set<String> = []

    private let library: Library
    private let definicoes: Definicoes

    init(library: Library, definicoes: Definicoes) {
        self.library = library
        self.definicoes = definicoes
    }

    static func chave(_ cadeira: URL) -> String { cadeira.standardizedFileURL.path }

    func aAtualizar(_ cadeira: Cadeira) -> String? { emCurso[Self.chave(cadeira.pasta)] }
    func erro(_ cadeira: Cadeira) -> String? { erros[Self.chave(cadeira.pasta)] }

    /// Todas as cadeiras (ao arrancar): passa as aulas antigas para excertos e junta o que faltar.
    func atualizarTodas() {
        for c in library.cadeiras { atualizar(nomeCadeira: c.nome) }
    }

    /// Junta à ficha as aulas pendentes da cadeira. Se já estiver a correr, volta a ver no fim.
    func atualizar(nomeCadeira: String) {
        guard let cadeira = library.cadeira(nome: nomeCadeira) else { return }
        let chave = Self.chave(cadeira.pasta)
        guard emCurso[chave] == nil else { repetir.insert(chave); return }
        // A migração dos apontamentos antigos (com a secção "Sobre a cadeira") só se tenta uma vez por aula.
        var registo = FichaCadeira.lerRegisto(cadeira.pasta)
        let porVer = cadeira.aulas.filter { !registo.migradas.contains($0.pasta.lastPathComponent) }
        if !porVer.isEmpty {
            let migradas = porVer.filter { (try? FichaCadeira.migrar($0.pasta)) == true }
            registo.migradas.formUnion(porVer.map(\.pasta.lastPathComponent))
            try? FichaCadeira.escreverRegisto(registo, em: cadeira.pasta)
            if !migradas.isEmpty { library.recarregar() }
        }
        guard FichaCadeira.programaPendente(cadeira.pasta) || !FichaCadeira.pendentes(cadeira).isEmpty else { return }
        erros[chave] = nil
        emCurso[chave] = ""
        Task {
            defer { emCurso[chave] = nil }
            repeat {
                repetir.remove(chave)
                guard let atual = library.cadeira(nome: nomeCadeira) else { return }
                do {
                    // O programa primeiro: é a base, e as aulas juntam-se ao que ele diz.
                    if FichaCadeira.programaPendente(atual.pasta) {
                        emCurso[chave] = "o programa"
                        try await juntarPrograma(a: atual)
                    }
                    for aula in FichaCadeira.pendentes(atual) {
                        emCurso[chave] = "\"\(aula.meta.titulo)\""
                        try await juntar(aula, a: atual)
                    }
                } catch {
                    erros[chave] = error.localizedDescription
                    return
                }
            } while repetir.contains(chave)
        }
    }

    private func juntar(_ aula: Aula, a cadeira: Cadeira) async throws {
        guard let excerto = FichaCadeira.lerExcerto(aula.pasta) else { return }
        let chave = aula.pasta.lastPathComponent
        let nomeAula = "Aula \(library.numeroDaAula(aula)) (\(aula.meta.data.formatted(date: .numeric, time: .omitted)))"
        let jaJuntada = FichaCadeira.lerRegisto(cadeira.pasta).aulas[chave] != nil
        try await juntar(em: cadeira, chave: chave, hash: FichaCadeira.hash(excerto)) { ficha in
            FichaCadeira.conteudo(ficha: ficha, excerto: excerto, aula: nomeAula, jaJuntada: jaJuntada)
        }
    }

    private func juntarPrograma(a cadeira: Cadeira) async throws {
        let pdf = try Data(contentsOf: FichaCadeira.urlPrograma(cadeira.pasta))
        let jaJuntado = FichaCadeira.lerRegisto(cadeira.pasta).aulas[FichaCadeira.chavePrograma] != nil
        try await juntar(em: cadeira, chave: FichaCadeira.chavePrograma, hash: FichaCadeira.hashDoPrograma(cadeira.pasta) ?? FichaCadeira.hash(pdf)) { ficha in
            FichaCadeira.conteudoPrograma(ficha: ficha, pdf: pdf, jaJuntado: jaJuntado)
        }
    }

    /// Pede a ficha nova e grava-a, registando o que entrou (`chave` → `hash`).
    private func juntar(em cadeira: Cadeira, chave: String, hash: String,
                        conteudo: (String?) -> [BlocoConteudo]) async throws {
        let gerador = try definicoes.gerador(esforco: .low)
        // Se a ficha mudar enquanto o Claude escreve (editada à mão), junta-se outra vez sobre a versão nova.
        for _ in 0..<3 {
            let base = FichaCadeira.lerFicha(cadeira.pasta)
            let r = try await gerador.gerar(sistema: FichaCadeira.sistema, conteudo: conteudo(base),
                                            aoRecomecar: {}, aoReceber: { _ in }, aoRepetir: { _, _, _ in })
            guard FichaCadeira.lerFicha(cadeira.pasta) == base else { continue }
            try FichaCadeira.escreverFicha(FichaCadeira.limpar(r.markdown), em: cadeira.pasta)
            var registo = FichaCadeira.lerRegisto(cadeira.pasta)
            registo.aulas[chave] = hash
            try FichaCadeira.escreverRegisto(registo, em: cadeira.pasta)
            versao += 1
            return
        }
    }
}
