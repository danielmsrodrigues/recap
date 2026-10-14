import Foundation

/// Professor ou aluno em cada segmento da transcrição, a partir da separação por vozes do SpeakerKit.
///
/// O SpeakerKit diz só "voz 0, voz 1…". Numa aula o professor é quem fala mais, por isso, em cada bloco
/// de ~5 min, a voz com mais tempo é a do professor e as outras são de alunos. Decidir por bloco evita
/// ter de reconhecer a mesma voz em blocos diferentes.
enum Oradores {
    /// Um intervalo em que uma voz fala (segundos, relativos ao início do bloco).
    struct Turno: Equatable, Sendable {
        var inicio: Double
        var fim: Double
        var voz: Int
    }

    struct Palavra: Equatable, Sendable {
        var texto: String
        var inicio: Double
        var fim: Double
    }

    /// Grupos de menos palavras do que isto juntam-se ao vizinho: uma troca de voz tão curta é mais
    /// provavelmente erro do alinhamento do que alguém a falar.
    static let palavrasMinimas = 3

    /// A voz com mais tempo de fala, se tiver pelo menos metade da fala do bloco. Sem uma voz claramente
    /// dominante (apresentações de alunos, um bloco final curto) não se decide: é melhor não marcar ninguém
    /// do que marcar o professor como aluno.
    static func vozPrincipal(_ turnos: [Turno]) -> Int? {
        var tempo: [Int: Double] = [:]
        for t in turnos { tempo[t.voz, default: 0] += t.fim - t.inicio }
        let total = tempo.values.reduce(0, +)
        // Empate: a voz de número mais baixo, para o resultado não variar de uma vez para outra.
        guard let principal = tempo.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }),
              total > 0, principal.value / total >= 0.5 else { return nil }
        return principal.key
    }

    /// Distância máxima (cosseno) para outra voz poder ser ainda o professor.
    static let limiarMesmaVoz: Float = 0.8

    /// As vozes do professor: a principal e as que estão mais perto dela do que de qualquer outra (e abaixo
    /// do limiar). O modelo às vezes parte a voz do professor em duas, sobretudo numa fala longa sem pausas;
    /// os alunos, mesmo parecidos entre si, ficam mais longe dele. Na dúvida fica professor: perder matéria
    /// dita pelo professor é pior do que deixar passar uma resposta de aluno, que o Claude ainda filtra pelo contexto.
    ///
    /// Sem uma terceira voz para comparar, a distância sozinha não chega (um aluno parecido ficava professor):
    /// exige-se também que a voz só fale colada ao professor, sem pausa, como acontece quando o modelo parte
    /// uma fala contínua. Um aluno a responder deixa sempre uma pausa.
    static func vozesDoProfessor(principal: Int, turnos: [Turno], distancia: (Int, Int) -> Float?) -> Set<Int> {
        let vozes = Set(turnos.map(\.voz))
        let doPrincipal = turnos.filter { $0.voz == principal }
        func colada(_ t: Turno) -> Bool {
            doPrincipal.contains { abs($0.fim - t.inicio) < 0.1 || abs(t.fim - $0.inicio) < 0.1 }
        }
        var professor: Set<Int> = [principal]
        for voz in vozes where voz != principal {
            guard let d = distancia(principal, voz), d < limiarMesmaVoz else { continue }
            let outras = vozes.subtracting([principal, voz])
            let ok = outras.isEmpty
                ? turnos.filter { $0.voz == voz }.allSatisfy(colada)
                : outras.allSatisfy { outra in distancia(voz, outra).map { d < $0 } ?? true }
            if ok { professor.insert(voz) }
        }
        return professor
    }

    /// A voz que mais se sobrepõe ao intervalo, ou nil se ninguém fala nele.
    static func voz(de inicio: Double, ate fim: Double, turnos: [Turno]) -> Int? {
        var sobreposicao: [Int: Double] = [:]
        for t in turnos {
            let s = min(fim, t.fim) - max(inicio, t.inicio)
            if s > 0 { sobreposicao[t.voz, default: 0] += s }
        }
        if let melhor = sobreposicao.max(by: { $0.value < $1.value }) { return melhor.key }
        // Palavras instantâneas (início = fim): conta a voz que está a falar nesse momento.
        return turnos.first { $0.inicio <= inicio && inicio <= $0.fim }?.voz
    }

    private typealias Grupo = (orador: Orador?, palavras: [Palavra])

    private static func juntarIguais(_ grupos: [Grupo]) -> [Grupo] {
        var saida: [Grupo] = []
        for g in grupos {
            if let ultimo = saida.last, ultimo.orador == g.orador { saida[saida.count - 1].palavras += g.palavras } else { saida.append(g) }
        }
        return saida
    }

    /// Marca cada segmento. Com as palavras, um segmento onde muda quem fala é partido em dois.
    static func marcar(_ segmentos: [(segmento: Segmento, palavras: [Palavra])], turnos: [Turno], professor: Set<Int>) -> [Segmento] {
        guard !turnos.isEmpty else { return segmentos.map(\.segmento) }
        func orador(_ voz: Int?) -> Orador? { voz.map { professor.contains($0) ? .professor : .aluno } }

        return segmentos.flatMap { segmento, palavras -> [Segmento] in
            var s = segmento
            guard palavras.count >= palavrasMinimas * 2 else {
                s.orador = orador(voz(de: s.inicio, ate: s.fim, turnos: turnos))
                return [s]
            }
            // Cada palavra com a sua voz; as que caem em silêncio ficam com a da palavra anterior.
            var etiquetas = palavras.map { orador(voz(de: $0.inicio, ate: $0.fim, turnos: turnos)) }
            if let primeira = etiquetas.first(where: { $0 != nil }) {
                var atual = primeira
                for i in etiquetas.indices {
                    if let e = etiquetas[i] { atual = e } else { etiquetas[i] = atual }
                }
            } else {
                s.orador = orador(voz(de: s.inicio, ate: s.fim, turnos: turnos))
                return [s]
            }
            // Grupos seguidos com a mesma voz; os muito curtos juntam-se ao anterior (ou ao seguinte, se for o primeiro).
            var grupos = juntarIguais(zip(etiquetas, palavras).map { (orador: $0, palavras: [$1]) })
            while grupos.count > 1, let i = grupos.firstIndex(where: { $0.palavras.count < palavrasMinimas }) {
                if i == 0 { grupos[1].palavras.insert(contentsOf: grupos[0].palavras, at: 0) } else { grupos[i - 1].palavras += grupos[i].palavras }
                grupos.remove(at: i)
                grupos = juntarIguais(grupos)
            }
            guard grupos.count > 1 else {
                s.orador = grupos.first?.orador
                return [s]
            }
            return grupos.map { g in
                Segmento(inicio: g.palavras.first?.inicio ?? s.inicio, fim: g.palavras.last?.fim ?? s.fim,
                         texto: g.palavras.map(\.texto).joined().trimmingCharacters(in: .whitespaces), orador: g.orador)
            }
        }
    }
}
