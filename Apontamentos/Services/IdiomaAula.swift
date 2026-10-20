import Foundation

/// A língua em que as aulas são dadas. O Whisper transcreve nessa língua; os apontamentos saem sempre em PT-PT.
enum IdiomaAula: String, CaseIterable, Identifiable, Sendable {
    case espanhol = "es", portugues = "pt", ingles = "en", frances = "fr", italiano = "it", alemao = "de"

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .espanhol: "Espanhol"
        case .portugues: "Português"
        case .ingles: "Inglês"
        case .frances: "Francês"
        case .italiano: "Italiano"
        case .alemao: "Alemão"
        }
    }

    /// Como aparece a meio de uma frase dos prompts ("transcrição em espanhol").
    var nomeNoPrompt: String { nome.lowercased() }

    /// Do código guardado em `transcricao.json`; um código desconhecido conta como espanhol (as aulas antigas).
    init(codigo: String) { self = IdiomaAula(rawValue: codigo) ?? .espanhol }

    /// A palavra "Glossário" na língua da aula, para o prompt do Whisper.
    var glossario: String {
        switch self {
        case .espanhol: "Glosario"
        case .portugues: "Glossário"
        case .ingles: "Glossary"
        case .frances: "Glossaire"
        case .italiano: "Glossario"
        case .alemao: "Glossar"
        }
    }

    /// Frases que o Whisper inventa em silêncio nesta língua (créditos de legendas, despedidas de vídeos).
    var alucinacoes: [String] {
        switch self {
        case .espanhol: ["amara.org", "subtítulos realizados por", "subtitulado por", "subtítulos por la comunidad", "¡suscríbete", "gracias por ver el video"]
        case .portugues: ["amara.org", "legendas pela comunidade", "legendado por", "obrigado por assistir", "inscreva-se", "inscrevam-se"]
        case .ingles: ["amara.org", "subtitles by", "thanks for watching", "thank you for watching", "subscribe to"]
        case .frances: ["amara.org", "sous-titres réalisés par", "sous-titrage", "merci d'avoir regardé", "abonnez-vous"]
        case .italiano: ["amara.org", "sottotitoli creati da", "sottotitoli a cura di", "grazie per aver guardato", "iscriviti"]
        case .alemao: ["amara.org", "untertitel von", "untertitelung", "danke fürs zuschauen", "abonniert"]
        }
    }

    /// Segmentos que, sozinhos, costumam ser o Whisper a preencher silêncio.
    var sozinhosEmSilencio: Set<String> {
        let comuns: Set<String> = ["...", "…"]
        switch self {
        case .espanhol: return comuns.union(["gracias.", "gracias", "¡gracias!", "gracias!"])
        case .portugues: return comuns.union(["obrigado.", "obrigado", "obrigada.", "obrigada"])
        case .ingles: return comuns.union(["thank you.", "thank you", "thanks.", "thanks"])
        case .frances: return comuns.union(["merci.", "merci"])
        case .italiano: return comuns.union(["grazie.", "grazie"])
        case .alemao: return comuns.union(["danke.", "danke"])
        }
    }
}

/// O curso e a língua do utilizador, metidos nos prompts no lugar de `{{contexto}}` e `{{idioma}}`.
/// Assim os prompts servem qualquer curso, e o prompt editável mantém-se legível.
enum ContextoCurso {
    static func aplicar(_ texto: String, idioma: IdiomaAula, contexto: String) -> String {
        texto.replacingOccurrences(of: "{{contexto}}", with: frase(contexto))
            .replacingOccurrences(of: "{{idioma}}", with: idioma.nomeNoPrompt)
    }

    /// "As aulas são de <o que o utilizador escreveu>." ou, sem nada escrito, uma frase genérica.
    static func frase(_ contexto: String) -> String {
        let c = contexto.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return c.isEmpty ? "As aulas são de um curso universitário." : "As aulas são de \(c)."
    }
}
