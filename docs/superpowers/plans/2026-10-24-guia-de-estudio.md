# Guía de estudio nos apontamentos — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** os apontamentos de cada aula usam as secções da Guía de estudio da cadeira como base e marcam a fonte de cada coisa (Slide, Guía com página, professor com [mm:ss], Ext.).

**Architecture:** a guía (o `programa.pdf` que já existe) é lida localmente com PDFKit e o seu índice fica em `guia.json`. Por aula, um pedido curto escolhe as secções (explicadas, remetidas, mencionadas). O texto delas entra no pedido dos apontamentos e no passo das 💡. No fim, uma verificação local marca as páginas citadas que não pertencem às secções enviadas.

**Tech Stack:** Swift 6, SwiftUI, PDFKit, Swift Testing, `Web/notes.js` e `notes.css` (WKWebView).

**Spec:** `docs/superpowers/specs/2026-10-24-guia-de-estudio-design.md`

## Global Constraints

- Nada muda nos apontamentos já gerados.
- Sem guía na cadeira, a geração fica igual à de hoje, exceto 💡 → "Ext.".
- Nunca se envia o PDF inteiro da guía: só texto de secções, no máximo `GuiaDaAula.maxCaracteres = 60_000` caracteres por aula.
- "p. N" é sempre a página **impressa** (página do PDF, contada a partir de 1, menos `desvio`).
- Rótulos nos apontamentos (pt → es → en): "Guia" → "Guía" → "Study guide"; "Ext." igual nas três.
- O pedido de seleção usa esforço `.low`. O passo das 💡 continua com `.medium`.
- Qualquer falha da guía (índice ilegível, seleção falhada) gera sem guía e mostra `job.aviso`. Nunca impede a geração.
- Cada mudança a `prompt_sistema_default.md` põe o hash anterior em `PromptStore.versoesAntigas`.
- Os testes correm com `xcodebuild test -project Apontamentos.xcodeproj -scheme Apontamentos -destination 'platform=macOS'`.

## Review Focus

1. **Guía trocada por outra:** `guia.json` antigo com outro hash → refaz o índice (teste em Task 1).
2. **PDF sem texto ou com um índice que não se lê** (digitalizado): `GuiaEstudo.indice` devolve nil e a aula gera sem guía, com aviso (testes em Task 1 e Task 7).
3. **A seleção devolve números que não existem, repetidos ou listas vazias:** ignorados. Vazio → sem bloco da guía (teste em Task 2).
4. **Aula de apresentação que toca todos os temas** (Aula 1 de Fundamentos): o texto passa de 60 000 caracteres → as secções a mais descem para "mencionadas" pela ordem do índice, sem cortar uma secção a meio (teste em Task 3).
5. **Id de secção repetido** ("6.2" duas vezes em Fundamentos): a seleção é por posição na lista (S1, S2…), não por id (teste em Task 2).

---

### Task 1: Ler a guía e o índice (`GuiaEstudo`)

**Files:**
- Create: `Apontamentos/Services/GuiaEstudo.swift`
- Test: `ApontamentosTests/GuiaEstudoTests.swift`

**Interfaces:**
- Produces:
  - `struct SeccaoGuia: Codable, Equatable, Sendable { var id: String; var titulo: String; var paginaInicio: Int; var paginaFim: Int }`. As páginas são impressas e inclusivas. Um "Tema N" tem `id == "N"`.
  - `struct IndiceGuia: Codable, Equatable, Sendable { var hash: String; var desvio: Int; var seccoes: [SeccaoGuia] }`
  - `enum GuiaEstudo` com:
    - `static let ficheiro = "guia.json"`
    - `static func paginas(_ pdf: PDFDocument) -> [String]`: o texto de cada página, por ordem.
    - `static func indice(paginas: [String], hash: String) -> IndiceGuia?`
    - `static func texto(_ s: SeccaoGuia, indice: IndiceGuia, paginas: [String]) -> String`: o texto das páginas da secção, cada página precedida de `[p. N]`.
    - `static func carregar(cadeira: URL) -> (indice: IndiceGuia, paginas: [String])?`: usa `FichaCadeira.urlPrograma` e `FichaCadeira.hashDoPrograma`. Lê `guia.json` se o hash bater; senão, refaz o índice e grava-o. nil sem PDF ou sem índice.

- [ ] **Step 1: Write the failing tests**

Fixture: texto de páginas imitando a guía de Fundamentos. Página 1 (PDF): capa. Página 2: "Índice" com estas linhas:
`"Tema 1. La empresa y la actividad empresarial ........ 4"`, `"    1.1. Fundamentos de las empresas ........ 5"`, `"    1.2. Principios de la actividad empresarial ........ 5"`, `"    1.3. Clase de empresas ........ 7"`, `"Tema 2. Gestión Empresarial ........ 14"`, `"    6.2. El proceso ........ 52"`, `"    6.2. Técnicas ........ 60"`.
Página 5 (PDF) contém "La empresa y la actividad empresarial". Página 6 contém "1.1. Fundamentos de las empresas". Total de 66 páginas (o resto vazio).

```swift
@Test func leOIndiceEODesvio() throws {
    let i = try #require(GuiaEstudo.indice(paginas: fixture, hash: "h"))
    #expect(i.desvio == 1)
    #expect(i.seccoes.map(\.id) == ["1", "1.1", "1.2", "1.3", "2", "6.2", "6.2"])
    #expect(i.seccoes[1] == SeccaoGuia(id: "1.1", titulo: "Fundamentos de las empresas", paginaInicio: 5, paginaFim: 5))
    #expect(i.seccoes[3].paginaFim == 13)                     // até à véspera do Tema 2
    #expect(i.seccoes.last?.paginaFim == 65)                  // última página impressa (66 − 1)
}
@Test func semIndiceDevolveNil() { #expect(GuiaEstudo.indice(paginas: ["", "texto sem índice"], hash: "h") == nil) }
@Test func textoComPaginasImpressas() throws {
    let i = try #require(GuiaEstudo.indice(paginas: fixture, hash: "h"))
    let t = GuiaEstudo.texto(i.seccoes[1], indice: i, paginas: fixture)
    #expect(t.hasPrefix("[p. 5]\n"))
    #expect(t.contains("1.1. Fundamentos de las empresas"))
}
@Test func refazOIndiceQuandoAGuiaMuda() throws { /* pasta temporária com programa.pdf (PDF de 2 páginas feito com PDFKit) e guia.json com hash "antigo" → carregar() devolve um índice com o hash atual e reescreve guia.json */ }
```

Mais um teste com `.enabled(if: env["APONTAMENTOS_GUIA"] != nil)`: abre o PDF real e espera `desvio == 1` e um índice com "2.4" e "Estructuras organizativas".

- [ ] **Step 2: Run them and see them fail** (`-only-testing:ApontamentosTests/GuiaEstudoTests`). Expected: não compila (`GuiaEstudo` não existe).

- [ ] **Step 3: Implement `GuiaEstudo`**

- Linhas do índice: `^\s*(?:Tema\s+(\d+)|(\d+(?:\.\d+)+))\.?\s+(.+?)\s*\.{3,}\s*(\d+)\s*$`, procuradas só nas primeiras 6 páginas.
- `paginaFim` = início da secção seguinte − 1. Se a seguinte começar na mesma página, fica igual a `paginaInicio`. A última vai até `paginas.count - desvio`.
- `desvio` = a moda, entre as secções, de (página do PDF, a contar de 1, onde o título aparece depois do índice) − `paginaInicio`. nil se nenhuma secção for encontrada.

- [ ] **Step 4: Run the tests and see them pass**
- [ ] **Step 5: Commit** — `git commit -m "Guía: ler o índice e o texto das secções"`

---

### Task 2: Escolher as secções da aula (`SeccoesDaAula`)

**Files:**
- Create: `Apontamentos/Services/SeccoesDaAula.swift`
- Test: `ApontamentosTests/SeccoesDaAulaTests.swift`

**Interfaces:**
- Consumes: `IndiceGuia`, `SeccaoGuia` (Task 1); `NotesGenerator.gerar(sistema:conteudo:aoRecomecar:aoReceber:aoRepetir:)`; `Transcricao.textoComTimestamps`.
- Produces:
  - `struct SelecaoGuia: Equatable, Sendable { var explicadas: [Int]; var remetidas: [Int]; var mencionadas: [Int] }`: posições em `indice.seccoes`, a contar de 0. Sem repetidos, e cada posição numa só lista (prioridade: remetidas > explicadas > mencionadas).
  - `enum SeccoesDaAula` com `static let sistema: String`, `static func pedido(_ indice: IndiceGuia, transcricao: Transcricao) -> String`, `static func daResposta(_ texto: String, total: Int) -> SelecaoGuia` e `static func escolher(_ indice: IndiceGuia, transcricao: Transcricao, gerador: NotesGenerator) async throws -> SelecaoGuia` (força `esforco = .low` e `maxTokens = 2_000`).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pedidoNumeraAsSeccoes() {
    let p = SeccoesDaAula.pedido(indiceFixture, transcricao: transcricaoFixture)
    #expect(p.contains("S1: 1 La empresa y la actividad empresarial (p. 4–4)"))
    #expect(p.contains("S6: 6.2 El proceso (p. 52–59)"))
    #expect(p.contains("<transcricao>"))
}
@Test func leAResposta() {
    let r = SeccoesDaAula.daResposta(#"```json {"explicadas":["S2","S3"],"remetidas":["S3", 4],"mencionadas":["S9","S5","S5"]} ```"#, total: 7)
    #expect(r == SelecaoGuia(explicadas: [1], remetidas: [2, 3], mencionadas: [4]))
}
@Test func respostaInvalidaFicaVazia() { #expect(SeccoesDaAula.daResposta("não sei", total: 7) == SelecaoGuia(explicadas: [], remetidas: [], mencionadas: [])) }
@Test func promptDefineAsTresCategorias() {
    #expect(SeccoesDaAula.sistema.contains("remetidas"))
    #expect(SeccoesDaAula.sistema.contains("no lo vamos a leer"))
}
```

Números "S3" e 4 são da lista numerada a partir de 1 (S1 = posição 0). As chaves aceitam-se traduzidas, como em `ExplicacoesExtra.daResposta`.

- [ ] **Step 2: Run them and see them fail**
- [ ] **Step 3: Implement**

O texto de `sistema` diz:
- **explicadas:** o professor deu a matéria da secção na aula.
- **remetidas:** o professor mandou estudar pela guía ("eso está en la guía", "no lo vamos a leer", "ahí tienen una tabla").
- **mencionadas:** só nomeou a secção ou disse que se vai ver.
- Responde só JSON `{"explicadas":["S…"],"remetidas":[…],"mencionadas":[…]}`, e de fora fica o que não foi tocado.

- [ ] **Step 4: Run the tests and see them pass**
- [ ] **Step 5: Commit** — `git commit -m "Guía: escolher as secções de cada aula"`

---

### Task 3: A guía no pedido dos apontamentos e as regras de fontes no prompt

**Files:**
- Modify: `Apontamentos/Services/NotesGenerator.swift` (`ContextoAula`, `materiais`)
- Modify: `Apontamentos/Resources/prompt_sistema_default.md`
- Modify: `Apontamentos/Services/PromptStore.swift` (hash anterior)
- Modify: `Apontamentos/Services/LinguaApontamentos.swift` (`RotulosApontamentos.tabela`)
- Test: `ApontamentosTests/GuiaNoPedidoTests.swift`, `ApontamentosTests/MelhoriasApontamentosTests.swift`

**Interfaces:**
- Consumes: Tasks 1 e 2.
- Produces:
  - `struct GuiaDaAula: Sendable, Equatable` com `enum Categoria: String, Sendable { case explicada, remetida }`, `struct Parte: Sendable, Equatable { var seccao: SeccaoGuia; var categoria: Categoria; var texto: String }`, `var partes: [Parte]`, `var mencionadas: [SeccaoGuia]`, `static let maxCaracteres = 60_000` e `static func montar(_ indice: IndiceGuia, paginas: [String], selecao: SelecaoGuia) -> GuiaDaAula?` (nil se não houver partes nem mencionadas).
  - `ContextoAula.guia: GuiaDaAula? = nil`.
  - `var paginasPermitidas: Set<Int>` (todas as páginas das partes e das mencionadas), para a Task 6.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func montarRespeitaOLimite() { /* partes com textos de 25 000 caracteres em 3 secções explicadas → 2 ficam em partes, a 3.ª passa para mencionadas */ }
@Test func materiaisComGuia() {
    // ContextoAula com guia de 1 parte remetida (1.3, p. 7–13) e 1 mencionada (2.5, p. 18)
    let texto = /* blocos .texto de NotesGenerator.materiais(ctx) juntos */
    #expect(texto.contains("Guía de estudio da cadeira"))
    #expect(texto.contains("<seccao id=\"1.3\" titulo=\"Clase de empresas\" paginas=\"7–13\" categoria=\"remetida\">"))
    #expect(texto.contains("2.5 Clases frecuentes de estructuras organizativas (p. 18)"))
}
@Test func materiaisSemGuiaComoAntes() { /* ctx.guia == nil → nenhum bloco contém "Guía de estudio" */ }
@Test func promptTemAsRegrasDeFontes() {
    let p = PromptStore.original
    #expect(p.contains("`> 📘 **Guia (<secção>, p. N):** ...`"))
    #expect(p.contains("| Segundo o professor [mm:ss] | Segundo a guia (<secção>, p. N) |"))
    #expect(p.contains("`💡 *Ext.: ...*`"))
    #expect(p.contains("Guia também trata"))
    #expect(p.contains("Lectura obligatoria"))
    #expect(!p.contains("Explicação extra"))
}
@Test func rotulos() {
    #expect(RotulosApontamentos.rotulo("Guia", .es) == "Guía")
    #expect(RotulosApontamentos.rotulo("Guia", .en) == "Study guide")
}
```

Em `MelhoriasApontamentosTests.explicaOQueOProfessorDeixouVago`, o texto esperado passa a `💡 *Ext.: <o que quer dizer na prática>*`.

- [ ] **Step 2: Run them and see them fail**
- [ ] **Step 3: Implement**

- `montar` percorre explicadas e remetidas pela ordem do índice e junta partes até `maxCaracteres`. As que não cabem passam para mencionadas.
- `materiais` acrescenta, depois dos PDFs do professor e antes das capturas, um bloco de texto que começa por "Guía de estudio da cadeira (material oficial)". Tem as partes em `<seccao …>…</seccao>` e as mencionadas numa lista "id título (p. N)".
- Mudanças no prompt (secções "Slides", "Explicar para quem está a aprender" e "Fidelidade", na mesma voz do resto):
  - Fontes por conceito: base = slides e guía. A definição cita *(Slide N)*, *(Guia <secção>, p. N)* ou as duas. O que o professor explicou vai por cima, com [mm:ss].
  - Tabela `| Segundo o professor [mm:ss] | Segundo a guia (<secção>, p. N) |` só para dados concretos. A tabela slide ↔ guía tem as colunas "Segundo o slide N" | "Segundo a guia (…)".
  - Caixa `> 📘 **Guia (<secção>, p. N):** ...`: curta para as secções explicadas, completa (com as tabelas) para as remetidas. As partes de uma secção explicada que o professor não tocou ficam numa linha `📘 *Guia também trata: … (p. N)*`.
  - Guías com um resumo e leituras por tema (Probabilidade): as "Lectura obligatoria" de um tema dado ficam numa linha no fim da caixa 📘 desse tema. Os enlaces e a bibliografia recomendada ficam de fora.
  - A guía nunca desenvolve as caixas 👀. A caixa pode acabar com `→ Guia <secção>, p. N`.
  - Só se citam páginas das secções recebidas.
  - `💡 *Ext.: ...*` / `> 💡 **Ext.:** ...` substituem "Explicação extra", só quando nem a aula nem a guía resolvem. A notação e o "porquê" de um passo que o professor não disse levam Ext. "Em palavras simples", o glossário e as respostas de revisão não levam marca.
  - Em "Dúvidas / pontos ambíguos", a resolução externa leva **Ext.:**.
  - A regra "Se a fala contradisser um slide… segue o slide" fica para slide ↔ fala.
- `RotulosApontamentos.tabela`: tira ("Explicação extra"…). Acrescenta ("Guia", nil, "Guía", "Study guide"), ("Segundo o professor", nil, "Según el profesor", "According to the lecturer"), ("Segundo a guia", nil, "Según la guía", "According to the study guide") e ("Segundo o slide", nil, "Según el slide", "According to slide"). A forma feminina já é tratada pela regra de género do prompt.
- `PromptStore.versoesAntigas`: o SHA-256 do prompt antes desta task.

- [ ] **Step 4: Run all the tests and see them pass** (o conjunto inteiro, porque `LinguaApontamentosTests` lê o prompt)
- [ ] **Step 5: Commit** — `git commit -m "Apontamentos: a guía no pedido e as regras de fontes"`

---

### Task 4: Caixa 📘 no ecrã e nome "Guía de estudio" no menu

**Files:**
- Modify: `Web/notes.js` (classes dos blockquotes), `Web/notes.css` (variáveis de cor em `:root`, no escuro e em `html.impressao`)
- Modify: `Apontamentos/Views/FichaCadeiraView.swift:54-61` (textos do menu)
- Test: `ApontamentosTests/NotesWebTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func caixaGuia() async throws {
    let pagina = try await Pagina.carregar()
    try await pagina.render("> 📘 **Guía (1.3, p. 7):** x\n\n> 👀 **Solo mencionado:** y")
    let r = try await pagina.web.evaluateJavaScript("[...document.querySelectorAll('blockquote')].map(q => q.className)") as? [String]
    #expect(r == ["guia", "mencionado"])
}
```

- [ ] **Step 2: Run it and see it fail**
- [ ] **Step 3: Implement**
  - `notes.js`: `t.startsWith("📘")` → `guia`.
  - `notes.css`: `--guia` e `--fundo-guia` em azul-esverdeado (claro `#0f8a8a` / `#e8f6f6`, escuro `#4cc7c7` / `#1b3132`) e `blockquote.guia`.
  - Menu: "Guía de estudio", "Abrir a guía", "Trocar a guía…", "Remover a guía", "Juntar a guía de estudio (PDF)…".
- [ ] **Step 4: Run it, see it pass, and look at it in the browser** (claro e escuro, como no #24)
- [ ] **Step 5: Commit** — `git commit -m "Apontamentos: caixa 📘 da guía e menu Guía de estudio"`

---

### Task 5: Passo das 💡 com a guía (📘 ou Ext.)

**Files:**
- Modify: `Apontamentos/Services/ExplicacoesExtra.swift`
- Test: `ApontamentosTests/ExplicacoesExtraTests.swift`

**Interfaces:**
- Consumes: `GuiaDaAula` (Task 3); `RotulosApontamentos.rotulo("Guia", lingua)`.
- Produces:
  - `ExplicacoesExtra.Explicacao` ganha `var fonte: Fonte = .ext`, com `enum Fonte: Equatable, Sendable { case ext, guia(pagina: Int?) }`.
  - `static func pedido(_ md: String, lingua: LinguaApontamentos, guia: GuiaDaAula?) -> String`
  - `static func aplicar(_ itens: [Explicacao], em md: String, lingua: LinguaApontamentos) -> String`
  - `static func rever(_ md: String, lingua: LinguaApontamentos, guia: GuiaDaAula?, gerador: NotesGenerator, aoRepetir:) async throws -> ResultadoApontamentos`

- [ ] **Step 1: Write/update the failing tests**
  - `aplicar` com `fonte: .guia(pagina: 48)` e `lingua: .es` → a linha acaba em `📘 *Guía (p. 48): Son las reglas…*`. Com `.ext` → `💡 *Ext.: Es la dirección…*`. Os testes atuais passam a esperar `💡 *Ext.: …*`.
  - `daResposta` lê `{"linha":4,"fonte":"guia","pagina":48,"explicacao":"…"}` e `{"linha":"L9","fonte":"ext","explicacao":"…"}`. Sem `fonte`, ou com outro valor, conta como `.ext`.
  - `pedido(md, lingua: .es, guia: g)` contém `<seccao id="5.1"` e "Só usa Ext. quando a guía não explica". Com `guia: nil`, não tem `<seccao`.
  - `aplicar` também não mexe em linhas que já têm `📘`.
- [ ] **Step 2: Run them and see them fail**
- [ ] **Step 3: Implement.** No JSON, `fonte` e `pagina` têm nomes fixos, lidos antes da heurística de "primeiro número / primeira string". O `sistema` pede primeiro a guía, com a página, e só depois Ext.
- [ ] **Step 4: Run them and see them pass**
- [ ] **Step 5: Commit** — `git commit -m "Explicações: 📘 da guía antes de Ext."`

---

### Task 6: Verificar as páginas citadas (`CitacoesGuia`)

**Files:**
- Create: `Apontamentos/Services/CitacoesGuia.swift`
- Test: `ApontamentosTests/CitacoesGuiaTests.swift`

**Interfaces:**
- Consumes: `GuiaDaAula.paginasPermitidas` (Task 3); `RotulosApontamentos.todas("Guia")`.
- Produces: `enum CitacoesGuia { static func verificar(_ md: String, paginas: Set<Int>) -> (markdown: String, invalidas: Int) }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func marcaPaginasForaDasSeccoes() {
    let md = "> 📘 **Guía (1.3, p. 7):** a\n- x 📘 *Guía (p. 99): b*\n- *(Guía 2.4, p. 18)*\n- Pág. 99 de otra cosa"
    let r = CitacoesGuia.verificar(md, paginas: [7, 8, 18])
    #expect(r.invalidas == 1)
    #expect(r.markdown.contains("(p. 99, página por confirmar)"))
    #expect(r.markdown.hasSuffix("- Pág. 99 de otra cosa"))   // fora de uma citação da guía: não mexe
}
@Test func intervalosContamComoValidos() { #expect(CitacoesGuia.verificar("(Guía 1.3, p. 7–8)", paginas: [7, 8]).invalidas == 0) }
```

- [ ] **Step 2: Run them and see them fail**
- [ ] **Step 3: Implement.** Só olha para "p. N" ou "p. N–M" dentro dos parênteses que vêm a seguir a um rótulo Guia, em qualquer língua (`RotulosApontamentos.todas("Guia")`). Uma página inválida passa a "p. N, página por confirmar".
- [ ] **Step 4: Run them and see them pass**
- [ ] **Step 5: Commit** — `git commit -m "Guía: marcar páginas citadas que não foram enviadas"`

---

### Task 7: Ligar tudo no pipeline e testar com a Aula 1

**Files:**
- Modify: `Apontamentos/Pipeline/PipelineRunner.swift` (`gerarApontamentos`)
- Modify: `ApontamentosTests/IntegracaoTests.swift` (`IntegracaoApontamentosTests`: guía opcional por `APONTAMENTOS_GUIA`)

**Interfaces:**
- Consumes: tudo o que vem antes. `library.cadeira(nome:)?.pasta` para a pasta da cadeira.

- [ ] **Step 1: Wire it** em `gerarApontamentos`, antes de `gerador.gerar`:
  1. `GuiaEstudo.carregar(cadeira:)`. nil com PDF presente → `job.aviso = "Não consegui ler o índice da guía; os apontamentos saem sem ela."`
  2. `job.atualizar(.apontamentos, progresso: nil, detalhe: "A escolher as secções da guía…")` → `SeccoesDaAula.escolher(...)` → `GuiaDaAula.montar(...)` → `contexto.guia`. Se falhar (exceto cancelamento), aviso e continua sem guía.

  Depois da geração:
  3. `ExplicacoesExtra.rever(semSobre, lingua:, guia: contexto.guia, gerador: revisor)`.
  4. Se houver guía, `CitacoesGuia.verificar(semSobre, paginas: guia.paginasPermitidas)`. Com `invalidas > 0`, `job.aviso = "N páginas da guía citadas não foram enviadas ao Claude: estão marcadas «página por confirmar»."`
  5. Os tokens do pedido de seleção somam-se à geração (`Geracao.somar`).
- [ ] **Step 2: Integration test.** `IntegracaoApontamentosTests.geraApontamentos`: com `APONTAMENTOS_GUIA=<pdf>`, monta a guía (índice + seleção + `montar`) e passa-a no contexto. Espera "📘" no resultado e `CitacoesGuia.verificar(...).invalidas == 0`.
- [ ] **Step 3: Run the whole suite** → `** TEST SUCCEEDED **`
- [ ] **Step 4: Run the integration** com a Aula 1 de Fundamentos e a guía real, com a saída no scratchpad. Ver à mão:
  - definições com *(Guía …, p. N)*;
  - a tabela de divergência para "toda empresa es con ánimo de lucro" [01:12];
  - 📘 completo para os límites de tamanho (remetidos);
  - caixas 👀 sem desenvolvimento;
  - 💡 só com "Ext.:".
- [ ] **Step 5: Commit** — `git commit -m "Pipeline: guía de estudio nos apontamentos"`
