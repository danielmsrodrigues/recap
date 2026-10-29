import Foundation

/// O mesmo ficheiro mudado em dois dispositivos antes de o iCloud os pôr de acordo (por exemplo, apontamentos
/// editados no iPad sem rede e no Mac ao mesmo tempo): o iCloud guarda as duas versões e escolhe uma à sorte.
/// Aqui decide-se de forma previsível e sem perder nada.
enum ConflitosICloud {
    /// Fica a versão mais recente; cada uma das outras é guardada ao lado (`apontamentos.conflito-2026-10-29-1150.md`).
    /// Devolve as cópias criadas (vazio sem conflito).
    @discardableResult
    static func resolver(_ url: URL) -> [URL] {
        guard let conflitos = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflitos.isEmpty,
              let atual = NSFileVersion.currentVersionOfItem(at: url) else { return [] }
        let versoes = ([atual] + conflitos).sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        var copias: [URL] = []
        var erro: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &erro) { url in
            // As cópias primeiro: a versão atual ainda está no sítio se não for a que fica.
            for v in versoes.dropFirst() {
                let destino = nomeCopia(url, data: v.modificationDate ?? .now)
                if (try? FileManager.default.copyItem(at: v === atual ? url : v.url, to: destino)) != nil { copias.append(destino) }
            }
            if versoes[0] !== atual { _ = try? versoes[0].replaceItem(at: url) }
            for c in conflitos { c.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return copias
    }

    /// As perguntas não se perdem nem se copiam: as duas conversas juntam-se numa só (`perguntas.json`).
    static func resolverPerguntas(_ pasta: URL) {
        let url = pasta.appending(path: Disco.perguntasJSON)
        guard let conflitos = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflitos.isEmpty else { return }
        var erro: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &erro) { url in
            let conversas = ([url] + conflitos.map(\.url)).map { origem in
                (try? Data(contentsOf: origem)).flatMap { try? Disco.decoder.decode([PerguntaAula].self, from: $0) } ?? []
            }
            if let dados = try? Disco.encoder.encode(juntar(conversas)) { try? dados.write(to: url, options: .atomic) }
            for c in conflitos { c.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }

    /// Todas as perguntas das várias versões, uma vez cada, pela ordem em que foram feitas.
    static func juntar(_ conversas: [[PerguntaAula]]) -> [PerguntaAula] {
        var vistas = Set<UUID>()
        return conversas.joined().filter { vistas.insert($0.id).inserted }.sorted { $0.data < $1.data }
    }

    /// `apontamentos.md` → `apontamentos.conflito-2026-10-29-1150.md` (com " (2)"… se já existir).
    static func nomeCopia(_ url: URL, data: Date) -> URL {
        let quando = data.formatted(Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
            timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        let nome = "\(url.deletingPathExtension().lastPathComponent).conflito-\(quando)"
        let pasta = url.deletingLastPathComponent()
        var candidato = pasta.appending(path: "\(nome).\(url.pathExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidato.path) {
            candidato = pasta.appending(path: "\(nome) (\(n)).\(url.pathExtension)")
            n += 1
        }
        return candidato
    }
}
