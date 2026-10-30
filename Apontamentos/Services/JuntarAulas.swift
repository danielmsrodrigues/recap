import Foundation

/// Junta duas gravações da mesma aula (o professor parou a gravação no intervalo, por exemplo) numa só.
/// A `primeira` fica com tudo: a transcrição da `segunda` entra a seguir, com os tempos deslocados pela duração
/// da primeira, e o mesmo para os slides; os PDFs e os outros materiais do professor juntam-se aos que já lá estão. A pasta da segunda
/// não é tocada (quem chama manda-a para o Lixo), e os apontamentos têm de ser gerados de novo.
enum JuntarAulas {
    enum Erro: LocalizedError {
        case semTranscricao(String)

        var errorDescription: String? {
            switch self {
            case .semTranscricao(let titulo): "\"\(titulo)\" ainda não tem transcrição. Espera que acabe de ser transcrita."
            }
        }
    }

    static func juntar(_ segunda: URL, a primeira: URL) throws {
        let meta1 = try Disco.lerMeta(primeira), meta2 = try Disco.lerMeta(segunda)
        guard let t1 = Disco.lerTranscricao(primeira) else { throw Erro.semTranscricao(meta1.titulo) }
        guard let t2 = Disco.lerTranscricao(segunda) else { throw Erro.semTranscricao(meta2.titulo) }
        let desvio = duracao(t1)

        // O tamanho primeiro: é o único passo que pode recusar (o resto são cópias), e assim nada fica meio junto.
        // Um PDF que já está na primeira (o mesmo nas duas partes) não é copiado: não conta duas vezes.
        let pdfs1 = Disco.pdfsProfessor(primeira, nomes: [:]).map { $0.url(em: primeira) }
        let pdfs2Novos = Disco.pdfsProfessor(segunda, nomes: [:]).map { $0.url(em: segunda) }.filter { p in
            !pdfs1.contains { FileManager.default.contentsEqual(atPath: $0.path, andPath: p.path) }
        }
        let bytesPDFsNovos = pdfs2Novos.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let total = Disco.tamanhoPDFsProfessor(em: primeira) + bytesPDFsNovos + Materiais.tamanho(em: primeira) + Materiais.tamanho(em: segunda)
        guard total <= Disco.tamanhoMaximoPDF else {
            throw NSError(domain: "Recap", code: 42, userInfo: [NSLocalizedDescriptionKey:
                "Juntas, as duas aulas ficavam com \(total / 1_048_576) MB de PDFs e materiais do professor; o máximo é \(Disco.tamanhoMaximoPDF / 1_048_576) MB. Tira algum PDF ou material de uma delas e tenta de novo."])
        }
        try Materiais.copiar(de: segunda, para: primeira)

        var nomes = meta1.nomesPDFs ?? [:]
        let pdfs2 = Disco.pdfsProfessor(segunda, nomes: meta2.nomesPDFs ?? [:])
        let juntados = try Disco.juntarPDFsProfessor(pdfs2.map { $0.url(em: segunda) }, em: primeira)
        for pdf in juntados {
            // `juntarPDFsProfessor` guarda o nome do ficheiro de origem ("slides-professor.pdf"); o original é o da segunda aula.
            let original = pdfs2.first { $0.ficheiro == pdf.nome }?.nome
            nomes[pdf.ficheiro] = original ?? pdf.nome
        }

        if let slides2 = Disco.lerSlides(segunda) {
            var slides = Disco.lerSlides(primeira) ?? []
            let pastaSlides = primeira.appending(path: Disco.pastaSlides, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: pastaSlides, withIntermediateDirectories: true)
            for s in slides2 {
                let inicio = s.inicio + desvio
                let nome = Disco.pastaLivre(nomeSlide(slides.count + 1, inicio: inicio), em: pastaSlides).lastPathComponent
                try FileManager.default.copyItem(at: Disco.urlSlide(s, em: segunda), to: pastaSlides.appending(path: nome))
                slides.append(Slide(ficheiro: nome, inicio: inicio, fim: s.fim + desvio, reaparicoes: s.reaparicoes.map { $0 + desvio }))
            }
            try Disco.escreverSlides(slides, em: primeira)
        }

        var t = t1
        t.segmentos += t2.segmentos.map { s in
            var s = s
            s.inicio += desvio
            s.fim += desvio
            return s
        }
        t.duracao = desvio + duracao(t2)
        try Disco.escreverTranscricao(t, em: primeira)

        var meta = meta1
        meta.duracao = t.duracao
        meta.geracoes += meta2.geracoes
        meta.nomesPDFs = nomes.isEmpty ? nil : nomes
        meta.revista = false
        try Disco.escreverMeta(meta, em: primeira)
    }

    /// A duração gravada ou, numa transcrição sem ela, o fim do último segmento.
    private static func duracao(_ t: Transcricao) -> Double {
        t.duracao > 0 ? t.duracao : (t.segmentos.map(\.fim).max() ?? 0)
    }

    /// Como o `SlideExtractor` os nomeia: `slide_07_52-10.jpg`.
    private static func nomeSlide(_ n: Int, inicio: Double) -> String {
        String(format: "slide_%02d_%@.jpg", n, Timestamp.format(inicio).replacingOccurrences(of: ":", with: "-"))
    }
}
