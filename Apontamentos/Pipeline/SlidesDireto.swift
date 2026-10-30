import Foundation

/// Os slides de uma aula captada em direto. Se se mudou de janela a meio, as imagens estão em troços (ver
/// `GravadorFrames.novoTroco`): a zona do slide é outra em cada janela, por isso cada troço é extraído à parte
/// e os slides juntam-se depois, pela ordem do tempo.
enum SlidesDireto {
    static func extrair(_ frames: URL, com extrator: SlideExtractor, para pastaAula: URL,
                        progresso: @escaping @Sendable (Double) -> Void) async throws -> [Slide] {
        let trocos = FontePasta.trocos(frames)
        guard trocos.count > 1 else {
            return try await extrator.extrair(de: FontePasta(pasta: frames), para: pastaAula, progresso: progresso)
        }
        let temporaria = FileManager.default.temporaryDirectory.appending(path: "Recap-trocos-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaria) }
        var partes: [URL] = []
        for (i, troco) in trocos.enumerated() {
            let parte = temporaria.appending(path: "\(i + 1)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: parte, withIntermediateDirectories: true)
            let n = Double(trocos.count)
            _ = try await extrator.extrair(de: FontePasta(pasta: troco), para: parte) { p in progresso((Double(i) + p) / n) }
            partes.append(parte)
        }
        return try juntar(partes, em: pastaAula)
    }

    /// Junta os slides extraídos em cada pasta de `partes` (com `slides/` e `slides.json`) nos da aula,
    /// numerados de seguida.
    static func juntar(_ partes: [URL], em pastaAula: URL) throws -> [Slide] {
        let destino = pastaAula.appending(path: Disco.pastaSlides, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        var slides: [Slide] = []
        for parte in partes {
            for s in (Disco.lerSlides(parte) ?? []).sorted(by: { $0.inicio < $1.inicio }) {
                let nome = JuntarAulas.nomeSlide(slides.count + 1, inicio: s.inicio)
                try FileManager.default.copyItem(at: Disco.urlSlide(s, em: parte), to: destino.appending(path: nome))
                slides.append(Slide(ficheiro: nome, inicio: s.inicio, fim: s.fim, reaparicoes: s.reaparicoes))
            }
        }
        try Disco.escreverSlides(slides, em: pastaAula)
        return slides
    }
}
