import Foundation

/// A língua em que o Claude escreve os apontamentos, as respostas, os exercícios, as ligações e a ficha da cadeira.
/// A interface da app continua em português.
enum LinguaApontamentos: String, CaseIterable, Identifiable, Sendable {
    case ptPT = "pt-PT", ptBR = "pt-BR", es, en

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .ptPT: "Português de Portugal"
        case .ptBR: "Português do Brasil"
        case .es: "Espanhol"
        case .en: "Inglês"
        }
    }

    /// Como aparece a meio de uma frase dos prompts.
    var nomeNoPrompt: String {
        switch self {
        case .ptPT: "português europeu (PT-PT)"
        case .ptBR: "português do Brasil (PT-BR)"
        case .es: "espanhol de Espanha"
        case .en: "inglês"
        }
    }

    /// O código da língua, para a comparar com a das aulas.
    var codigo: String {
        switch self {
        case .ptPT, .ptBR: "pt"
        case .es: "es"
        case .en: "en"
        }
    }

    var locale: Locale {
        switch self {
        case .ptPT: Locale(identifier: "pt_PT")
        case .ptBR: Locale(identifier: "pt_BR")
        case .es: Locale(identifier: "es_ES")
        case .en: Locale(identifier: "en_GB")
        }
    }

    /// As regras de língua para os prompts (`{{regras_lingua}}`), em tópicos. Em PT-PT, as de sempre.
    var regras: String {
        var regras: [String]
        switch self {
        case .ptPT:
            regras = [
                #"Escreve tudo em português europeu (PT-PT), nunca em português do Brasil: "ficheiro" (não "arquivo"), "ecrã" (não "tela"), "utilizador" (não "usuário"), "equipa" (não "time"), "registo", "facto", "secção", "objeto", "ótimo", "contacto", "controlo", "guardar"."#,
                #"Usa a terminologia portuguesa: "valor próprio" e "vetor próprio" (não "autovalor"/"autovetor"), "derivada parcial", "descida do gradiente", "variável aleatória", "valor esperado", "desvio padrão", "função de custo", "receitas" (não "ingressos"), "análise SWOT"."#,
                #"Mantém em inglês os termos que se usam assim em português ("overfitting", "batch", "dataset", "learning rate"), com a tradução entre parênteses na primeira vez, se ajudar."#,
            ]
        case .ptBR:
            regras = [
                #"Escreve tudo em português do Brasil (PT-BR): "arquivo", "tela", "usuário", "equipe", "registro", "fato", "seção", "objeto", "contato", "controle", "salvar"."#,
                #"Usa a terminologia brasileira: "autovalor" e "autovetor", "derivada parcial", "gradiente descendente", "variável aleatória", "valor esperado", "desvio padrão", "função de custo", "receitas", "análise SWOT"."#,
                #"Mantém em inglês os termos que se usam assim em português ("overfitting", "batch", "dataset", "learning rate"), com a tradução entre parênteses na primeira vez, se ajudar."#,
            ]
        case .es:
            regras = [
                "Escreve tudo em espanhol de Espanha, embora estas instruções estejam em português.",
                #"Usa a terminologia espanhola: "autovalor", "derivada parcial", "descenso del gradiente", "variable aleatoria", "esperanza", "desviación típica", "ingresos"."#,
                #"Mantém em inglês os termos que se usam assim em espanhol ("overfitting", "batch", "dataset", "learning rate")."#,
            ]
        case .en:
            regras = [
                "Escreve tudo em inglês, embora estas instruções estejam em português.",
                #"Usa a terminologia inglesa padrão: "eigenvalue", "partial derivative", "gradient descent", "random variable", "expected value", "standard deviation", "revenue"."#,
            ]
        }
        if let rotulos = RotulosApontamentos.instrucao(self) { regras.append(rotulos) }
        return regras.map { "- " + $0 }.joined(separator: "\n")
    }

    /// A secção do glossário (`{{seccao_glossario}}`): de tradução quando a aula é noutra língua;
    /// na mesma língua dos apontamentos, só os termos com o significado.
    func seccaoGlossario(aulas idioma: IdiomaAula) -> String {
        let r = { RotulosApontamentos.rotulo($0, self) }
        let logistica = #"(não os da logística, como "época de exames")"#
        guard idioma.rawValue != codigo else {
            return """
            ## \(r("Glossário"))
            | \(r("Termo")) | \(r("Significado")) |
            |---|---|
            Os termos técnicos da matéria que apareceram na aula, cada um com uma definição curta \(logistica).
            """
        }
        let de = locale.localizedString(forLanguageCode: idioma.rawValue) ?? idioma.nomeNoPrompt
        let para = locale.localizedString(forLanguageCode: codigo) ?? nomeNoPrompt
        return """
        ## \(r("Glossário")) (\(de) → \(para))
        | \(r("Original")) | \(para.prefix(1).uppercased() + para.dropFirst()) | \(r("Nota")) |
        |---|---|---|
        Os termos técnicos da matéria que apareceram na aula \(logistica).
        """
    }
}

/// Os títulos e rótulos fixos que os prompts pedem em português, nas outras línguas dos apontamentos.
/// A app lê alguns deles nos apontamentos ("Sobre a cadeira", "Resumo", "Resolução"), por isso a tradução
/// pedida ao Claude é sempre a desta tabela, e a leitura aceita-as todas (a mesma pasta pode misturar línguas).
enum RotulosApontamentos {
    private static let tabela: [(pt: String, br: String?, es: String, en: String)] = [
        ("Resumo", nil, "Resumen", "Summary"),
        ("Sobre a cadeira", "Sobre a disciplina", "Sobre la asignatura", "About the course"),
        ("Glossário", nil, "Glosario", "Glossary"),
        ("Original", nil, "Original", "Original"),
        ("Termo", nil, "Término", "Term"),
        ("Significado", nil, "Significado", "Meaning"),
        ("Nota", nil, "Nota", "Note"),
        ("Dúvidas / pontos ambíguos", nil, "Dudas / puntos ambiguos", "Open questions"),
        ("Perguntas de revisão", nil, "Preguntas de repaso", "Review questions"),
        ("Resposta", nil, "Respuesta", "Answer"),
        ("Em palavras simples", nil, "En palabras sencillas", "In simple terms"),
        ("Definição", nil, "Definición", "Definition"),
        ("Exemplo", nil, "Ejemplo", "Example"),
        ("Importante", nil, "Importante", "Important"),
        ("Explicação extra", nil, "Explicación extra", "Extra explanation"),
        ("Erro comum", nil, "Error común", "Common mistake"),
        ("inferido", nil, "inferido", "inferred"),
        ("por confirmar", nil, "por confirmar", "to be confirmed"),
        ("Só mencionado", nil, "Solo mencionado", "Only mentioned"),
        ("Exercícios", nil, "Ejercicios", "Exercises"),
        ("Exercício", nil, "Ejercicio", "Exercise"),
        ("Matéria da aula", nil, "Materia de la clase", "Covered in class"),
        ("Resolução", nil, "Resolución", "Solution"),
        ("Resultado", nil, "Resultado", "Result"),
        ("Aula", nil, "Clase", "Lecture"),
    ]

    /// O rótulo `pt` (tal como está na tabela) na língua dos apontamentos.
    static func rotulo(_ pt: String, _ lingua: LinguaApontamentos) -> String {
        guard let linha = tabela.first(where: { $0.pt == pt }) else { return pt }
        switch lingua {
        case .ptPT: return linha.pt
        case .ptBR: return linha.br ?? linha.pt
        case .es: return linha.es
        case .en: return linha.en
        }
    }

    /// O rótulo em todas as línguas, para o reconhecer nos apontamentos.
    static func todas(_ pt: String) -> [String] {
        var vistas = Set<String>()
        return LinguaApontamentos.allCases.map { rotulo(pt, $0) }.filter { vistas.insert($0).inserted }
    }

    /// Para o prompt: como se escrevem os rótulos pedidos em português. nil em PT-PT (não há nada a traduzir).
    static func instrucao(_ lingua: LinguaApontamentos) -> String? {
        let pares = tabela.map { ($0.pt, rotulo($0.pt, lingua)) }.filter { $0.0 != $0.1 }
        guard !pares.isEmpty else { return nil }
        let lista = pares.map { "\"\($0.0)\" → \"\($0.1)\"" }.joined(separator: ", ")
        return "Os títulos e os rótulos que estas instruções indicam em português escrevem-se assim: \(lista). "
            + "Os outros (Teorema, Propriedade, Fácil/Médio/Difícil, as secções da ficha…) traduzem-se da mesma maneira."
    }
}
