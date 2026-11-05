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

/// A pasta das aulas, com os cursos que tem. Não há base de dados: o que há de cursos lê-se das pastas.
@MainActor @Observable
final class Biblioteca {
    private(set) var raiz: URL
    /// O curso aberto neste aparelho.
    private(set) var ativo: ServicosCurso

    init(raiz: URL, definicoes: Definicoes) {
        self.raiz = raiz
        ativo = ServicosCurso(library: Library(raiz: raiz, preferenciasDeRecurso: definicoes.preferenciasAntigas),
                              definicoes: definicoes)
    }

    /// As pastas dos cursos, para quem tem de ver todos (os pedidos do iPad e do iPhone).
    var raizesDosCursos: [URL] { [ativo.library.raiz] }

    /// O curso a que pertence um caminho (a pasta de uma aula, ou a do próprio curso). nil se não for de nenhum: usar
    /// outro curso no lugar dele daria o glossário e a língua errados sem erro nenhum.
    func servicos(de pasta: URL) -> ServicosCurso? {
        pasta.mesmoCaminho(raiz) || pasta.estaDentro(de: raiz) ? ativo : nil
    }

    /// Passa a usar outra pasta das aulas. Com `mover`, vai tudo o que está na atual.
    func mudarRaiz(para nova: URL, mover: Bool) throws {
        try ativo.library.mudarRaiz(para: nova, mover: mover)
        raiz = ativo.library.raiz
    }
}
