import Foundation
import Testing
@testable import Apontamentos

/// As preferências de cada curso vivem em `_recap/definicoes.json`, lidas pela `Library` dessa pasta.
/// Ler nunca escreve, e nada que fique para sempre começa sem elas.
@MainActor
struct PreferenciasCursoTests {
    private func pasta() throws -> URL {
        let raiz = FileManager.default.temporaryDirectory.appending(path: "preferencias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        return raiz
    }

    private func gravar(contexto: String, em raiz: URL) throws {
        var p = DefinicoesPartilhadas.porDefeito
        p.contextoCurso = contexto
        try DefinicoesPartilhadas.escrever(p, raiz: raiz)
    }

    private func dataDe(_ url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    // MARK: Ler

    /// Abrir uma pasta sem preferências não cria o ficheiro nem a pasta do sistema: seria ir para o iCloud por cima de nada.
    @Test func lerUmaPastaSemFicheiroNaoEscreve() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        var recurso = DefinicoesPartilhadas.porDefeito
        recurso.contextoCurso = "Deste aparelho"

        let lib = Library(raiz: raiz, preferenciasDeRecurso: recurso)
        lib.recarregar(forcar: true)

        #expect(lib.contextoCurso == "Deste aparelho")
        #expect(!lib.preferenciasPorLer)
        #expect(!FileManager.default.fileExists(atPath: DefinicoesPartilhadas.url(raiz: raiz).path))
    }

    @Test func lerUmFicheiroNaoOVoltaAEscrever() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "Mestrado", em: raiz)
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        let antiga = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: antiga], ofItemAtPath: url.path)

        let lib = Library(raiz: raiz)
        lib.recarregar(forcar: true)

        #expect(lib.contextoCurso == "Mestrado")
        #expect(try dataDe(url) == antiga)
    }

    /// O ficheiro ganha ao que este aparelho guardava: é o que todos os aparelhos veem.
    @Test func oFicheiroGanhaAoRecurso() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "Do ficheiro", em: raiz)
        var recurso = DefinicoesPartilhadas.porDefeito
        recurso.contextoCurso = "Deste aparelho"

        #expect(Library(raiz: raiz, preferenciasDeRecurso: recurso).contextoCurso == "Do ficheiro")
    }

    /// Mudadas noutro aparelho: chegam com a próxima leitura da pasta.
    @Test func relerApanhaOQueMudouNoutroAparelho() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "Antes", em: raiz)
        let lib = Library(raiz: raiz)
        try gravar(contexto: "Depois", em: raiz)
        lib.recarregar()
        #expect(lib.contextoCurso == "Depois")
    }

    @Test func mudarAOrganizacaoNoutroAparelhoReagrupaACadeiras() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let lib = Library(raiz: raiz)
        try lib.criarCadeira(nome: "Cálculo")
        var p = DefinicoesPartilhadas.porDefeito
        p.organizacaoCurso = .nenhuma
        try DefinicoesPartilhadas.escrever(p, raiz: raiz)
        lib.recarregar()
        #expect(lib.semestres == [.todas])
    }

    // MARK: Editar

    @Test func editarEscreveNaPastaDoCurso() throws {
        let a = try pasta(), b = try pasta()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let curso = Library(raiz: a)
        try curso.alterarPreferencias { $0.contextoCurso = "Mestrado" }

        #expect(DefinicoesPartilhadas.ler(raiz: a)?.contextoCurso == "Mestrado")
        #expect(DefinicoesPartilhadas.ler(raiz: b) == nil)
    }

    /// Duas pastas, dois cursos: o que muda num não passa para o outro.
    @Test func duasLibraryNaoPartilhamPreferencias() throws {
        let a = try pasta(), b = try pasta()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        let mestrado = Library(raiz: a), fintech = Library(raiz: b)
        try mestrado.alterarPreferencias {
            $0.contextoCurso = "Mestrado"
            $0.idioma = .portugues
            $0.organizacaoCurso = .ano
        }
        try fintech.alterarPreferencias {
            $0.contextoCurso = "Fintech360"
            $0.idioma = .ingles
        }
        mestrado.recarregar()
        fintech.recarregar()

        #expect(mestrado.contextoCurso == "Mestrado")
        #expect(mestrado.idiomaAulas == .portugues)
        #expect(mestrado.organizacao == .ano)
        #expect(fintech.contextoCurso == "Fintech360")
        #expect(fintech.idiomaAulas == .ingles)
        #expect(fintech.organizacao == .anoESemestre)
        #expect(fintech.prompt("{{contexto}}") == "As aulas são de Fintech360.")
    }

    /// Editar não escreve nas preferências antigas: quem manda é o ficheiro, e cada curso tem o seu.
    @Test func editarNaoTocaNasPreferenciasDoAparelho() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let defaults = try #require(UserDefaults(suiteName: "preferencias-\(UUID().uuidString)"))
        defaults.set("Licenciatura", forKey: "contextoCurso")
        let definicoes = Definicoes(defaults: defaults)

        let lib = Library(raiz: raiz, preferenciasDeRecurso: definicoes.preferenciasAntigas)
        #expect(lib.contextoCurso == "Licenciatura")
        try lib.alterarPreferencias { $0.contextoCurso = "Mestrado" }

        #expect(defaults.string(forKey: "contextoCurso") == "Licenciatura")
        #expect(Library(raiz: raiz, preferenciasDeRecurso: definicoes.preferenciasAntigas).contextoCurso == "Mestrado")
    }

    @Test func asPreferenciasAntigasVemDasChavesDeSempre() throws {
        let defaults = try #require(UserDefaults(suiteName: "preferencias-\(UUID().uuidString)"))
        #expect(Definicoes(defaults: defaults).preferenciasAntigas == .porDefeito)

        defaults.set("Licenciatura em Física", forKey: "contextoCurso")
        defaults.set(LinguaApontamentos.en.rawValue, forKey: "linguaApontamentos")
        defaults.set(IdiomaAula.ingles.rawValue, forKey: "idiomaAulas")
        defaults.set(OrganizacaoCurso.ano.rawValue, forKey: "organizacao")
        defaults.set([2, 8], forKey: "iniciosPeriodos")
        defaults.set(3, forKey: "duracaoCurso")

        let p = Definicoes(defaults: defaults).preferenciasAntigas
        #expect(p.contextoCurso == "Licenciatura em Física")
        #expect(p.lingua == .en)
        #expect(p.idioma == .ingles)
        #expect(p.organizacaoCurso == .ano)
        #expect(p.inicios == [2, 8])
        #expect(p.duracao == 3)
    }

    // MARK: Por ler

    /// Uma pasta em que `definicoes.json` está só no iCloud.
    private func libraryComFicheiroNaNuvem(_ raiz: URL, recurso: DefinicoesPartilhadas = .porDefeito) -> Library {
        Library(raiz: raiz, preferenciasDeRecurso: recurso,
                porDescarregar: { $0.lastPathComponent == DefinicoesPartilhadas.ficheiro },
                trazer: { _ in }, esperaAoFalhar: .seconds(60))
    }

    @Test func comOFicheiroPorDescarregarFicaPorLerENaoSeGrava() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "O que vem a caminho", em: raiz)
        var recurso = DefinicoesPartilhadas.porDefeito
        recurso.contextoCurso = "Deste aparelho"

        let lib = libraryComFicheiroNaNuvem(raiz, recurso: recurso)
        #expect(lib.preferenciasPorLer)
        #expect(lib.contextoCurso == "Deste aparelho")
        #expect(throws: ErroPreferencias.self) { try lib.alterarPreferencias { $0.contextoCurso = "Por cima" } }
        #expect(lib.contextoCurso == "Deste aparelho")
        #expect(DefinicoesPartilhadas.ler(raiz: raiz)?.contextoCurso == "O que vem a caminho")
    }

    /// Enquanto o ficheiro não se consegue ler, ficam as últimas lidas, não as de recurso.
    @Test func quandoDeixaDeSeLerFicamAsUltimasLidas() throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "As últimas", em: raiz)
        let lib = Library(raiz: raiz)
        #expect(lib.contextoCurso == "As últimas")

        try Data("não é JSON".utf8).write(to: DefinicoesPartilhadas.url(raiz: raiz))
        lib.recarregar()
        #expect(lib.preferenciasPorLer)
        #expect(lib.contextoCurso == "As últimas")

        // Volta a ler-se assim que estiver bom.
        try FileManager.default.removeItem(at: DefinicoesPartilhadas.url(raiz: raiz))
        try gravar(contexto: "Já se lê", em: raiz)
        lib.recarregar()
        #expect(!lib.preferenciasPorLer)
        #expect(lib.contextoCurso == "Já se lê")
    }

    /// As preferências que estão só no iCloud vêm sozinhas, sem contar como uma aula a chegar.
    @Test func asPreferenciasNaNuvemVemSozinhas() async throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let url = DefinicoesPartilhadas.url(raiz: raiz)
        let lib = Library(raiz: raiz,
                          porDescarregar: { $0.lastPathComponent == DefinicoesPartilhadas.ficheiro && !FileManager.default.fileExists(atPath: $0.path) },
                          trazer: { _ in
                              var p = DefinicoesPartilhadas.porDefeito
                              p.contextoCurso = "Chegou"
                              try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                              try Disco.escrever(p, em: url)
                          })
        #expect(lib.preferenciasPorLer)
        #expect(lib.aulasNaNuvem == 0)
        for _ in 0..<300 where lib.preferenciasPorLer { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!lib.preferenciasPorLer)
        #expect(lib.contextoCurso == "Chegou")
    }

    /// Uma língua errada numa transcrição fica para sempre: sem as preferências lidas, o job falha e pode repetir-se.
    @Test func semPreferenciasLidasOJobNaoComeca() async throws {
        let raiz = try pasta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        try gravar(contexto: "Mestrado", em: raiz)
        let library = libraryComFicheiroNaNuvem(raiz)
        let definicoes = Definicoes(defaults: try #require(UserDefaults(suiteName: "preferencias-\(UUID().uuidString)")))
        let fichas = Fichas(library: library, definicoes: definicoes)
        let estudo = Estudo(library: library, definicoes: definicoes)
        let runner = PipelineRunner(library: library, definicoes: definicoes, fichas: fichas, estudo: estudo)
        let pastaAula = try library.criarAula(cadeira: "Finanças", titulo: "Aula 1", data: .now, video: nil)
        let audio = raiz.appending(path: "audio.caf")
        try Data("som".utf8).write(to: audio)

        let job = Job(pastaAula: pastaAula, titulo: "Aula 1", video: nil, gerarApontamentos: true, audioDireto: audio)
        await runner.executar(job)

        #expect(job.estado == .falhou(ErroPreferencias.porLer.localizedDescription))
        #expect(job.faseDe(.transcricao) == .pendente)
        #expect(!Disco.existe(Disco.transcricaoJSON, em: pastaAula))
        // O áudio só se apaga depois de transcrito.
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    // MARK: Mudar de pasta

    @Test func umaPastaComPreferenciasFicaComAsDela() throws {
        let a = try pasta(), b = try pasta()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try gravar(contexto: "A", em: a)
        try gravar(contexto: "B", em: b)
        let lib = Library(raiz: a)

        try lib.mudarRaiz(para: b, mover: false)

        #expect(lib.contextoCurso == "B")
        #expect(DefinicoesPartilhadas.ler(raiz: a)?.contextoCurso == "A")
        #expect(DefinicoesPartilhadas.ler(raiz: b)?.contextoCurso == "B")
    }

    @Test func umaPastaSemPreferenciasFicaComAsAtuais() throws {
        let a = try pasta(), b = try pasta()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try gravar(contexto: "A", em: a)
        let lib = Library(raiz: a)

        try lib.mudarRaiz(para: b, mover: false)

        #expect(lib.contextoCurso == "A")
        #expect(DefinicoesPartilhadas.ler(raiz: b)?.contextoCurso == "A")
        // A que fica para trás continua com as suas.
        #expect(DefinicoesPartilhadas.ler(raiz: a)?.contextoCurso == "A")
    }

    @Test func moverLevaAsPreferencias() throws {
        let a = try pasta()
        let b = FileManager.default.temporaryDirectory.appending(path: "preferencias-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try gravar(contexto: "Vai junto", em: a)
        let lib = Library(raiz: a)

        try lib.mudarRaiz(para: b, mover: true)

        #expect(lib.contextoCurso == "Vai junto")
        #expect(DefinicoesPartilhadas.ler(raiz: b)?.contextoCurso == "Vai junto")
    }
}
