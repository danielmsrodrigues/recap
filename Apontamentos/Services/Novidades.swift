import Foundation

/// O que veio com cada versão, para "Sobre o Recap" e para o "O que há de novo" que aparece depois de uma
/// atualização. A versão nova entra no início da lista antes de se publicar (as notas servem também à release).
enum Novidades {
    struct Versao: Identifiable, Equatable, Sendable {
        var numero: String
        var data: String
        var itens: [String]
        var id: String { numero }
    }

    static let todas: [Versao] = [
        Versao(numero: "1.14", data: "30 de outubro de 2026", itens: [
            "\"Não estou a perceber\" durante a transcrição em direto (tecla N): marca o bocado até carregares em \"Já percebi\", e os apontamentos explicam essa parte com mais calma.",
            "\"Sai no exame\": o que o professor disse que entra no exame, por cadeira, com a frase e o minuto da aula.",
            "Perguntar à cadeira inteira, em \"Sobre a cadeira\" (no Mac): as respostas levam à aula e ao minuto.",
            "Progresso do programa em \"Sobre a cadeira\", quando há guia de estudo: os temas vistos, a meio e por ver.",
            "Livro da cadeira em PDF (no Mac): os apontamentos de todas as aulas, com índice e glossário.",
            "Ouvir a aula no iPhone e no iPad, com o ecrã bloqueado, sem ler asteriscos nem outros sinais.",
            "\"Sobre o Recap\" com as novidades de cada versão.",
            "Mac mais perto do design: barra lateral em cartão, apontamentos sem folha à volta e um botão de painel para mostrar ou esconder o Estudo.",
        ]),
        Versao(numero: "1.13", data: "30 de outubro de 2026", itens: [
            "Calendário das aulas: o mês inteiro no Mac e no iPad, e no iPhone um ponto por aula em cada dia com as aulas do dia escolhido por baixo.",
            "A interface diz \"Guia de estudo\" em português.",
            "No iPhone, o separador Hoje tem a casa como ícone.",
        ]),
        Versao(numero: "1.12", data: "30 de outubro de 2026", itens: [
            "Mac redesenhado em três colunas, como o Notas e o Mail: as listas e as cadeiras, as aulas e a aula.",
            "Barra de capítulos por cima da aula, com as secções dos apontamentos ao longo da aula e uma marca por slide.",
            "Início com as aulas por rever e o Transcrever em direto à mão.",
            "Pesquisa em todas as aulas no topo da lista, e cada aula diz se está por rever ou revista.",
            "Cor de cada cadeira escolhida à mão, e o título da aula nova sugerido a partir da anterior (\"Aula 4\").",
            "Outros materiais do professor além dos PDFs (apresentações, folhas de cálculo, documentos).",
            "iPhone e iPad redesenhados, com o painel Estudo ao lado da aula.",
            "Logótipo novo.",
        ]),
    ]

    /// A versão desta app (`CFBundleShortVersionString`).
    static var atual: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// As versões depois de `ultimaVista` até à atual, da mais recente para a mais antiga. Na primeira vez (sem
    /// `ultimaVista`) não há nada: quem instala agora não precisa da lista de tudo o que mudou antes.
    static func porVer(_ lista: [Versao] = todas, ultimaVista: String?, atual: String = atual) -> [Versao] {
        guard let ultimaVista else { return [] }
        return lista.filter { menor(ultimaVista, $0.numero) && !menor(atual, $0.numero) }
    }

    /// "1.9" < "1.12": compara número a número, e não como texto.
    static func menor(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p < q }
        }
        return false
    }

    /// A chave das Definições com a última versão cujas novidades já se viram.
    static let chaveUltimaVista = "ultimaVersaoVista"
}
