import Foundation

/// As ligações (`ligacoes.json`, caminhos relativos à raiz) e o registo da ficha da cadeira (`sobre.json`, pelo nome da
/// pasta da aula) guardam nomes de pastas. Quando uma aula ou uma cadeira muda de nome, acompanham-no: senão as
/// ligações pareciam desatualizadas (e refaziam-se com o Claude) e a aula voltava a ser juntada à ficha.
enum Renomear {
    /// Depois de mover `antiga` para `nova` (uma aula ou uma cadeira, dentro de `raiz`).
    static func atualizarChaves(de antiga: URL, para nova: URL, raiz: URL) {
        // Com os caminhos resolvidos: a raiz e as pastas podem vir por caminhos diferentes (/var e /private/var).
        let base = raiz.resolvingSymlinksInPath().path + "/"
        // A pasta antiga já não existe (e um caminho que não existe não se resolve): resolve-se a pasta de cima.
        let relativo = { (u: URL) -> String? in
            let c = u.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: u.lastPathComponent).path
            return c.hasPrefix(base) ? String(c.dropFirst(base.count)) : nil
        }
        guard let de = relativo(antiga), let para = relativo(nova), de != para else { return }
        let trocar = { (c: String) -> String in
            c == de ? para : c.hasPrefix(de + "/") ? para + c.dropFirst(de.count) : c
        }
        for ficheiro in ficheirosLigacoes(raiz) {
            let pasta = ficheiro.deletingLastPathComponent()
            guard var l = Disco.lerLigacoes(pasta) else { continue }
            let antes = l
            for i in l.ligacoes.indices { l.ligacoes[i].aula = trocar(l.ligacoes[i].aula) }
            for i in l.temas.indices { l.temas[i].aulas = l.temas[i].aulas.map(trocar) }
            l.assinaturas = l.assinaturas.map { Dictionary($0.map { (trocar($0.key), $0.value) }) { a, _ in a } }
            if l != antes { try? Disco.escreverLigacoes(l, em: pasta) }
        }
        // Uma aula que mudou de nome na mesma cadeira: o registo da ficha passa para o nome novo.
        let cadeira = antiga.deletingLastPathComponent()
        guard de.contains("/"), cadeira.resolvingSymlinksInPath() == nova.deletingLastPathComponent().resolvingSymlinksInPath(),
              var registo = try? FichaCadeira.registoParaAlterar(cadeira) else { return }
        let (n1, n2) = (antiga.lastPathComponent, nova.lastPathComponent)
        guard registo.aulas[n1] != nil || registo.migradas.contains(n1) else { return }
        if let h = registo.aulas.removeValue(forKey: n1) { registo.aulas[n2] = h }
        if registo.migradas.remove(n1) != nil { registo.migradas.insert(n2) }
        try? FichaCadeira.escreverRegisto(registo, em: cadeira)
    }

    private static func ficheirosLigacoes(_ raiz: URL) -> [URL] {
        let fm = FileManager.default
        let cadeiras = (try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return cadeiras.flatMap { c in
            ((try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                .map { $0.appending(path: Disco.ligacoesJSON) }
                .filter { fm.fileExists(atPath: $0.path) }
        }
    }
}
