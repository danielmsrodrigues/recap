import CryptoKit
import Foundation

/// As notas das ligações nos apontamentos ("🔗 Aprofundado na Aula 2… → [Fiscalidade]"), por baixo do título da secção
/// de que falam. Não as escreve o Claude ao fazer os apontamentos: a app tira-as e volta a pô-las sempre que as
/// ligações da cadeira mudam (`Estudo.aplicarNotas`), sem gerar os apontamentos de novo.
enum NotasLigacoes {
    /// Uma linha que começa assim é uma nota da app (é por isto que se reconhece para a tirar).
    static let marca = "> 🔗 "

    struct Nota: Equatable, Sendable {
        /// Âncora da secção destes apontamentos por baixo da qual fica a nota.
        var seccao: String
        var texto: String
        /// Link para a outra aula (`#<aula>/<secção>`) e o texto do link.
        var link: String
        var tituloLink: String
    }

    /// Os apontamentos sem as notas das ligações (e sem a linha em branco que a app pôs antes de cada uma).
    static func tirar(_ md: String) -> String {
        var linhas: [String] = []
        for linha in md.components(separatedBy: "\n") {
            if linha.hasPrefix(marca) {
                if linhas.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { linhas.removeLast() }
            } else {
                linhas.append(linha)
            }
        }
        return linhas.joined(separator: "\n")
    }

    /// Os apontamentos com estas notas, e só estas, por baixo dos títulos das suas secções (ou do slide logo a seguir
    /// ao título). Notas de secções que já não existem ficam de fora. Pôr as mesmas notas duas vezes não muda nada.
    static func por(_ notas: [Nota], em md: String) -> String {
        let limpo = tirar(md)
        let seccoes = Seccoes.lista(limpo)
        var porLinha: [Int: [Nota]] = [:]
        for nota in notas {
            guard let s = Seccoes.resolver(LigacaoSeccao(ancora: nota.seccao, texto: ""), em: seccoes) else { continue }
            porLinha[s.linha, default: []].append(nota)
        }
        var linhas = limpo.components(separatedBy: "\n")
        // De baixo para cima, para as linhas acrescentadas não mudarem a posição dos títulos seguintes.
        for (linha, notas) in porLinha.sorted(by: { $0.key > $1.key }) {
            var depois = linha + 1
            if depois < linhas.count, linhas[depois].hasPrefix("![") { depois += 1 }
            var bloco: [String] = []
            for nota in notas {
                let texto = nota.texto.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                bloco += ["", marca + texto + " → [\(nota.tituloLink)](\(nota.link))"]
            }
            if depois < linhas.count, !linhas[depois].trimmingCharacters(in: .whitespaces).isEmpty { bloco.append("") }
            linhas.insert(contentsOf: bloco, at: depois)
        }
        return linhas.joined(separator: "\n")
    }

    /// O que conta para saber se os apontamentos mudaram: sem as notas das ligações nem linhas em branco
    /// (pôr as notas não pode fazer as ligações parecerem desatualizadas).
    static func assinatura(_ md: String) -> String {
        let texto = tirar(md).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        return SHA256.hash(data: Data(texto.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
