import Foundation

/// O que o iPhone e o iPad mostram em Hoje, Por rever e Cadeiras: as aulas por rever, a próxima a rever depois de
/// marcar uma, as mais recentes, e a sigla e a cor de cada cadeira.
enum Revisao {
    /// Com apontamentos e ainda não revistas, as mais recentes primeiro (uma aula sem apontamentos não tem o que rever).
    static func porRever(_ cadeiras: [Cadeira]) -> [Aula] {
        cadeiras.flatMap(\.aulas).filter { $0.temApontamentos && !$0.meta.revista }.sorted { $0.meta.data > $1.meta.data }
    }

    /// Depois de marcar `aula` como revista: a mais recente das outras por rever.
    static func proxima(depoisDe aula: Aula, em cadeiras: [Cadeira]) -> Aula? {
        porRever(cadeiras).first { $0.pasta != aula.pasta }
    }

    static func recentes(_ cadeiras: [Cadeira], limite: Int = 5) -> [Aula] {
        Array(cadeiras.flatMap(\.aulas).sorted { $0.meta.data > $1.meta.data }.prefix(limite))
    }

    /// Palavras que não contam para a sigla ("Fundamentos de Empresas e Economia" → FE).
    private static let ligacoes: Set<String> = ["de", "do", "da", "dos", "das", "e", "y", "i", "o", "a", "os", "as", "el", "la",
                                                "los", "las", "del", "em", "en", "no", "na", "para", "of", "and", "the", "to"]

    /// Duas letras: as iniciais das duas primeiras palavras que contam, ou as duas primeiras letras de uma só.
    static func sigla(_ nome: String) -> String {
        let palavras = nome.split(whereSeparator: \.isWhitespace).map(String.init)
        let contam = palavras.filter { !ligacoes.contains($0.lowercased()) }
        let usadas = contam.isEmpty ? palavras : contam
        guard let primeira = usadas.first else { return "?" }
        if usadas.count == 1 { return String(primeira.prefix(2)).uppercased() }
        return (String(primeira.prefix(1)) + String(usadas[1].prefix(1))).uppercased()
    }

    /// Matizes (0–1) que não se confundem uns com os outros: azul, verde, âmbar, roxo, vermelho, turquesa, lima, anil.
    private static let paleta: [Double] = [215, 140, 45, 285, 350, 180, 100, 255].map { $0 / 360 }

    /// O matiz de cada cadeira. Cada uma parte de uma cor tirada do nome (a mesma em todos os aparelhos) e, se
    /// essa já for de outra, fica com a seguinte livre: duas cadeiras nunca ficam da mesma cor (até 8).
    static func matizes(_ nomes: [String]) -> [String: Double] {
        var livres = Array(paleta.indices)
        var resultado: [String: Double] = [:]
        for nome in Set(nomes).sorted() {
            var h: UInt64 = 5381
            for u in nome.lowercased().unicodeScalars { h = (h &* 33) &+ UInt64(u.value) }
            let preferido = Int(h % UInt64(paleta.count))
            // Mais de 8 cadeiras: as cores repetem-se a partir daqui.
            if livres.isEmpty { resultado[nome] = paleta[preferido]; continue }
            let i = livres.first { $0 >= preferido } ?? livres[0]
            livres.removeAll { $0 == i }
            resultado[nome] = paleta[i]
        }
        return resultado
    }
}

/// Os apontamentos de uma aula partidos pelos títulos `##`, para as secções que abrem e fecham no iPhone e no iPad.
enum SeccoesApontamentos {
    struct Seccao: Equatable, Hashable {
        var titulo: String
        var corpo: String
    }

    struct Partidos: Equatable {
        /// O `#` do início (o tema da aula).
        var titulo: String?
        /// A secção "Resumo" (em qualquer língua dos apontamentos), à parte.
        var resumo: String?
        /// As outras secções, pela ordem. O texto antes do primeiro `##` fica numa secção sem título.
        var seccoes: [Seccao]
    }

    static func partir(_ markdown: String) -> Partidos {
        let resumos = Set(RotulosApontamentos.todas("Resumo").map { $0.lowercased() })
        var titulo: String?
        var atual: (titulo: String, linhas: [String]) = ("", [])
        var resumo: String?
        var seccoes: [Seccao] = []
        var emCodigo = false

        func fechar() {
            let corpo = atual.linhas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if resumos.contains(atual.titulo.lowercased()) {
                resumo = corpo
            } else if !atual.titulo.isEmpty || !corpo.isEmpty {
                seccoes.append(Seccao(titulo: atual.titulo, corpo: corpo))
            }
        }

        for linha in markdown.components(separatedBy: "\n") {
            let aparada = linha.trimmingCharacters(in: .whitespaces)
            if aparada.hasPrefix("```") || aparada.hasPrefix("~~~") { emCodigo.toggle() }
            if !emCodigo, linha.hasPrefix("## ") {
                fechar()
                atual = (semTempo(String(linha.dropFirst(3))), [])
            } else if !emCodigo, linha.hasPrefix("# "), titulo == nil, seccoes.isEmpty, atual.titulo.isEmpty {
                titulo = semTempo(String(linha.dropFirst(2)))
            } else {
                atual.linhas.append(linha)
            }
        }
        fechar()
        return Partidos(titulo: titulo, resumo: resumo, seccoes: seccoes)
    }

    /// "Tipos de números [04:12]" → "Tipos de números": o momento da aula fica no texto da secção.
    private static func semTempo(_ titulo: String) -> String {
        titulo.replacingOccurrences(of: #"\s*\[\d{1,2}:\d{2}(:\d{2})?\]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
