import Foundation

enum EstadoCurso: String, Sendable {
    case aDecorrer = "a_decorrer"
    case concluido
}

/// Conteúdo de `_recap/curso.json`. Tudo opcional: um curso sem este ficheiro (ou com ele ainda por descarregar) continua a ser um curso.
struct CursoMeta: Codable, Hashable, Sendable {
    /// O nome a mostrar. Sem ele, o da pasta. Mudar de nome não mexe na pasta (ver `Biblioteca`).
    var nome: String?
    /// Vai pelo `rawValue`: um estado que esta versão não conheça lê-se como "a decorrer", mas não se perde.
    var estado: String?
    var concluidoEm: Date?

    init(nome: String? = nil) {
        self.nome = nome
    }

    var estadoCurso: EstadoCurso {
        get { estado.flatMap(EstadoCurso.init) ?? .aDecorrer }
        set { estado = newValue.rawValue }
    }
}

/// Um curso é o que antes era a pasta das aulas: dentro dele, `_recap/` e as pastas das cadeiras, no formato de sempre.
/// Os cursos novos ficam em `<pasta das aulas>/_recap/cursos/<pasta>/`, que as versões anteriores ignoram. As cadeiras
/// que estão diretamente na pasta das aulas são o curso da raiz, no formato antigo.
struct Curso: Identifiable, Hashable, Sendable {
    /// O id do curso da raiz. Os outros têm o nome da pasta deles.
    static let idDaRaiz = ""

    let id: String
    let pasta: URL
    var meta: CursoMeta

    var naRaiz: Bool { id == Self.idDaRaiz }

    var nome: String {
        if let n = meta.nome?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return naRaiz ? "O meu curso" : id
    }

    var concluido: Bool { meta.estadoCurso == .concluido }
}

/// O que o catálogo mostra de cada curso. Vem de ler as pastas, por isso calcula-se fora do fio principal.
struct ResumoCurso: Equatable, Sendable {
    var cadeiras: Int
    var aulas: Int
    var porRever: Int
    var ultimaAula: Date?
}

extension Disco {
    /// Dentro de `_recap` da pasta das aulas, cada pasta é um curso.
    static let pastaCursos = "cursos"
    static let cursoJSON = "curso.json"

    static func urlCursos(raiz: URL) -> URL {
        raiz.appending(path: pastaSistema).appending(path: pastaCursos, directoryHint: .isDirectory)
    }

    static func urlCurso(_ pasta: URL) -> URL {
        pasta.appending(path: pastaSistema).appending(path: cursoJSON)
    }

    static func lerCurso(_ pasta: URL) -> CursoMeta {
        (try? ler(CursoMeta.self, de: urlCurso(pasta))) ?? CursoMeta()
    }

    static func escreverCurso(_ meta: CursoMeta, em pasta: URL) throws {
        try FileManager.default.createDirectory(at: pasta.appending(path: pastaSistema), withIntermediateDirectories: true)
        try escrever(meta, em: urlCurso(pasta))
    }
}
