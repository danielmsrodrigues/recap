#if os(macOS)
import Foundation

/// Passa o curso da raiz (o formato antigo, com as cadeiras diretamente na pasta das aulas) para a sua pasta em
/// `_recap/cursos/`, ao lado dos outros. Só corre quando se carrega no botão.
///
/// Se parar a meio, nada fica invisível: as cadeiras por mover continuam no curso da raiz, as movidas já estão no curso
/// novo, e `_recap/conversao.json` guarda o destino para se poder continuar. `_recap` nunca se move, por isso a pasta
/// continua a ser reconhecida como a pasta das aulas.
enum ConversorCurso {
    struct Registo: Codable, Equatable, Sendable {
        /// O nome da pasta do curso, em `_recap/cursos`.
        var destino: String
        var nome: String
    }

    static func urlRegisto(raiz: URL) -> URL {
        raiz.appending(path: Disco.pastaSistema).appending(path: "conversao.json")
    }

    /// A conversão que ficou por acabar, se houver.
    static func registo(raiz: URL) -> Registo? {
        try? Disco.ler(Registo.self, de: urlRegisto(raiz: raiz))
    }

    /// Faz a conversão, ou continua a que ficou a meio. Devolve o que não se pôde mudar porque já existia no destino
    /// (caminhos relativos à raiz); nesse caso, fica por acabar. Fora do fio principal: são muitas mudanças coordenadas.
    static func converter(raiz: URL, nome: String, preferencias: DefinicoesPartilhadas,
                          captacoes: URL = CaptacaoGuardada.raizPorDefeito,
                          mover: (URL, URL) throws -> Void = moverCoordenado) throws -> [String] {
        let fm = FileManager.default
        guard !Disco.porDescarregar(Disco.urlCurso(raiz)) else { throw ErroCurso.aChegar(nome) }
        let registo: Registo
        if let existente = Self.registo(raiz: raiz) {
            registo = existente
        } else {
            registo = Registo(destino: Disco.nomeDePasta(nome), nome: nome)
            let pasta = Disco.urlCursos(raiz: raiz).appending(path: registo.destino, directoryHint: .isDirectory)
            guard !fm.fileExists(atPath: pasta.path) else { throw ErroCurso.jaExiste(nome) }
            try fm.createDirectory(at: raiz.appending(path: Disco.pastaSistema), withIntermediateDirectories: true)
            try Disco.escrever(registo, em: urlRegisto(raiz: raiz))
        }
        let destino = Disco.urlCursos(raiz: raiz).appending(path: registo.destino, directoryHint: .isDirectory)
        try fm.createDirectory(at: destino, withIntermediateDirectories: true)

        // O curso fica com o que a raiz tinha (o estado, a data), e com o nome escolhido.
        var meta = Disco.lerCurso(raiz)
        meta.nome = registo.nome
        try Disco.escreverCurso(meta, em: destino)
        // Numa continuação, as preferências já lá estão, e podem até ter sido mudadas no curso novo.
        if !fm.fileExists(atPath: DefinicoesPartilhadas.url(raiz: destino).path) {
            try DefinicoesPartilhadas.escrever(preferencias, raiz: destino)
        }

        var ficaram: [String] = []
        for cadeira in cadeiras(em: raiz) {
            let alvo = destino.appending(path: cadeira.lastPathComponent, directoryHint: .isDirectory)
            if fm.fileExists(atPath: alvo.path) {
                // Pastas iguais juntam-se; um ficheiro que já existe no destino não é substituído e fica onde está.
                ficaram += try PastaICloud.mudar(de: cadeira, para: alvo).map { "\(cadeira.lastPathComponent)/\($0)" }
            } else {
                try mover(cadeira, alvo)
            }
        }

        // Sem isto, uma aula captada por transcrever ficava sem a pasta da aula (ver `CaptacaoGuardada.pendentes`).
        CaptacaoGuardada.realojar(em: captacoes) { antiga in
            let nova = destino.appending(path: antiga.deletingLastPathComponent().lastPathComponent, directoryHint: .isDirectory)
                .appending(path: antiga.lastPathComponent, directoryHint: .isDirectory)
            return fm.fileExists(atPath: nova.path) ? nova : nil
        }

        guard ficaram.isEmpty else { return ficaram }
        // O nome da raiz passou para o curso: sem isto, a raiz continuava a contar como um curso, vazio.
        try? fm.removeItem(at: Disco.urlCurso(raiz))
        try fm.removeItem(at: urlRegisto(raiz: raiz))
        return []
    }

    /// As pastas da raiz, menos a do sistema. Os ficheiros soltos e o que está escondido ficam onde estão.
    private static func cadeiras(em raiz: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: raiz, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { $0.lastPathComponent != Disco.pastaSistema && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Muda uma pasta de sítio avisando o iCloud Drive: é uma mudança de nome, sem voltar a enviar o que lá está.
    static func moverCoordenado(_ origem: URL, para destino: URL) throws {
        var erro: NSError?
        var resultado: Result<Void, any Error> = .success(())
        let coordenador = NSFileCoordinator()
        coordenador.coordinate(writingItemAt: origem, options: .forMoving, writingItemAt: destino, options: .forReplacing, error: &erro) { o, d in
            resultado = Result {
                coordenador.item(at: o, willMoveTo: d)
                try FileManager.default.moveItem(at: o, to: d)
                coordenador.item(at: o, didMoveTo: d)
            }
        }
        if let erro { throw erro }
        try resultado.get()
    }
}
#endif
