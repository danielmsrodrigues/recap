# Guía de estudio nos apontamentos — design

Data: 24 out 2026 · Pedido pelo Daniel · Estado: aprovado (com as respostas à revisão), falta o plano

## Porquê

O Daniel passa os apontamentos para o papel e estuda por eles para o exame. Os apontamentos misturam três fontes sem as distinguir: o que a professora disse, o que os slides mostram e explicações do Claude. Além disso, ignoram a fonte oficial mais completa, a **Guía de estudio** da cadeira (as da VIU têm índice por secções, definições e as tabelas que a professora remete para lá, por exemplo "los límites están en la guía de estudios").

A regra, por cada conceito:

1. **Base:** slides + guía (material oficial). A definição principal vem daqui.
2. **Por cima:** o que a professora explicou na aula (exemplos, intuições), com [mm:ss].
3. **Divergência** professora ↔ guía: as duas versões lado a lado, identificadas ("Según la profesora" / "Según la guía"), sem as juntar. Por baixo, uma linha **"Para estudar:"** diz qual usar, para o Daniel nunca ter de escolher sozinho: por defeito a guía; a da professora quando ela disse que a guía está errada ou desatualizada, ou que no exame conta o que ela disse (decisão do Daniel a 24 out: "não quero ficar confuso entre ter de escolher").
4. **Conhecimento externo** só para resolver uma dúvida ou um ponto ambíguo, sempre marcado "Ext.", nunca misturado com a aula.

Sucesso: ao ler uma linha dos apontamentos, o Daniel sabe sempre de onde ela vem (aula, slide, guía ou externo), e o que a guía diz sobre a matéria da aula está lá, com a página para ir confirmar.

## Objetivos, não-objetivos, anti-objetivos

- **Objetivos:** usar a guía nos apontamentos de cada aula, marcar a fonte de cada definição, mostrar as divergências e passar os 💡 a "Ext." (ou a 📘 Guía, quando a guía explica).
- **Não-objetivos:** usar a guía no chat, nos exercícios ou nas ligações entre aulas (fica para depois); regenerar sozinha as aulas que já existem; suportar mais do que uma guía por cadeira.
- **Anti-objetivos** (falha mesmo que funcione):
  - A guía a desenvolver temas que a professora **só mencionou** (as caixas 👀). Foi o problema que deu origem ao #23/#24: matéria não dada a ocupar espaço.
  - Páginas ou secções da guía inventadas.
  - Os apontamentos a duplicar de tamanho com cópias da guía. A guía entra resumida, só no que falta.
  - Conhecimento externo sem marca, ou misturado numa frase da aula.

## Decisões tomadas

### Um só PDF por cadeira

O `programa.pdf` que já existe (`FichaCadeira.programaPDF`) é, nas cadeiras do Daniel, a Guía de estudio (Fundamentos: 66 páginas, índice 1.1–6.4; Probabilidade: 20 páginas). Fica o mesmo ficheiro e o mesmo sítio para o juntar (menu "Programa" da `FichaCadeiraView`), que passa a chamar-se **"Guía de estudio"** ("Abrir a guía", "Juntar guía…"). Continua a alimentar a ficha "Sobre a cadeira" como hoje.

### Formato nos apontamentos

Exemplo na língua dos apontamentos do Daniel (espanhol):

```
### Clases de empresa [18:28]
> **Definición — Empresa con fines de lucro.** <texto> *(Guía 1.3, p. 7)*

- Los dueños reinvierten una parte para que la empresa crezca [28:10].

| Según la profesora [01:12] | Según la guía (1.2, p. 5) |
|---|---|
| "Toda empresa es con ánimo de lucro." | Ánimo de lucro "en la mayoría de los casos". |

> 📘 **Guía (1.3, p. 8):** lo que la guía dice sobre este tema y no se dijo en clase.

- **Procedimientos:** los definidos para los registros… 📘 *Guía (5.1, p. 48): …*
- **Estratégico:** donde se formulan las estrategias. 💡 *Ext.: …*
```

- **Fonte da definição:** no fim do bloco `> **Definição — …**`, *(Slide N)* ou *(Guía <secção>, p. N)*, ou as duas.
- **O que o professor explicou:** texto normal com [mm:ss], como hoje.
- **Divergência:** tabela de duas colunas, "Según la profesora [mm:ss]" | "Según la guía (<secção>, p. N)", logo a seguir ao conceito. Só para dados concretos (um número, uma definição, uma classificação), não para diferenças de palavras. Substitui a regra atual "segue o slide e regista a diferença em Dúvidas" quando a outra fonte é a guía. Slide ↔ fala continua como hoje.
- **📘 Guía (caixa):** `> 📘 **Guía (<secção>, p. N):** …` com o que a guía diz sobre um tema **dado nesta aula** e que não foi dito. Curto: o que falta, não uma cópia. Nova classe CSS `guia` em `notes.js`/`notes.css` (cor própria, distinta de definição/⚠️/⭐/👀/💡; ecrã, escuro e PDF).
- **📘 Guía (na linha):** `📘 *Guía (p. N): …*` no fim de uma linha cujo termo ficou vago e a guía explica (ver passo das 💡).
- **💡 Ext.:** conhecimento externo, só quando nem a aula nem a guía resolvem. Na linha: `💡 *Ext.: …*`; em bloco: `> 💡 **Ext.:** …` (substitui "Explicação extra"). Em "Dúvidas / pontos ambíguos", a resolução externa de um ponto leva **Ext.:** à frente.
- **Temas 👀:** a guía **não** os desenvolve. A caixa pode acabar com a referência: `→ Guía 2.5, p. 18`.
- **Rótulos traduzidos** em `RotulosApontamentos`: "Guia" (pt) / "Guía" (es) / "Study guide" (en); "Ext." igual em todas; "Segundo o professor/a professora" / "Según la profesora/el profesor" / "According to the lecturer" (o género segue a regra que já existe no prompt).
- **Páginas:** "p. N" é o número **impresso** na página da guía (o que o Daniel vê ao abrir o PDF e no índice), não o índice do PDF.

### Pipeline

1. **Índice da guía (uma vez por cadeira, quando a guía entra ou muda):**
   - Texto de cada página tirado localmente com PDFKit (sem custo).
   - Índice de secções `[{id: "2.4", titulo, paginaInicio, paginaFim}]` (páginas impressas, mais o desvio para a página do PDF), guardado em `~/Aulas/<cadeira>/guia.json` junto com o hash do PDF. Reaproveitar o hash que `FichaCadeira.hashDoPrograma` já calcula.
   - Primeiro tentar sem o Claude (o índice das guías VIU é texto "2.4. Título ........ 18"). Se não der, um pedido curto ao Claude, com esforço baixo, sobre o texto das primeiras páginas. A escolha do método fica para quem constrói. O resultado tem de ter páginas que existem.
2. **Secções da aula (por aula, antes de gerar):** pedido curto ao Claude, com esforço baixo e sem slides, com o índice e a transcrição. Devolve três listas de secções: as que a aula **explicou**, as que a professora **remeteu para a guía** e as que só **mencionou**. Cerca de 30 s. Se falhar, gera sem guía, com aviso.
3. **Geração:** `ContextoAula` ganha `guia: [SeccaoGuia]` (id, título, páginas, texto com marcas `[p. N]` por página), das secções explicadas e remetidas, com a categoria de cada uma. As mencionadas entram só como lista "id título p. N" (para a referência na caixa 👀). `NotesGenerator.materiais` junta-as como texto. O prompt por defeito ganha as regras de fontes e formato acima (e o hash do prompt atual vai para `PromptStore.versoesAntigas`).
4. **Passo das 💡 (`ExplicacoesExtra`):** recebe também as secções explicadas. Para cada linha vaga devolve `{linha, fonte: "guia"|"ext", pagina?, explicacao}`. A app escreve `📘 *Guía (p. N): …*` ou `💡 *Ext.: …*`.
5. **Verificação local** depois da geração e do passo das 💡: cada "p. N" e cada secção citadas têm de pertencer às secções enviadas. Uma citação fora delas fica marcada *(página por confirmar)* e conta para um aviso no job. Não se apaga texto.

Sem guía na cadeira, tudo funciona como hoje, exceto 💡 → "Ext.".

### Custo e tempo

Por aula: mais um pedido curto (cerca de 30 s) e alguns milhares de tokens de entrada na geração (uma secção da guía de Fundamentos tem cerca de 1–3 mil palavras). Uma vez por cadeira: o índice. Tudo com a subscrição. Pela API seria pago à parte, com a estimativa que a app já mostra.

### Decisões do Daniel depois da revisão do design

1. **Remetido para a guía** ("eso está en la guía, no lo vamos a leer", "ahí tienen una tabla"): terceira categoria, além de explicado e mencionado. O conteúdo da guía sobre isso entra numa caixa 📘, **com as tabelas completas**, porque a professora mandou estudar por lá. A regra "a guía entra resumida" não se aplica a esta categoria. A seleção devolve três listas: explicadas, remetidas, mencionadas. As explicadas e as remetidas levam o texto.
2. **Partes de uma secção que não foram tocadas** (secção 1.1 com 7 pilares, dos quais a professora deu 3): os que ela deu ganham 📘 com o que a guía acrescenta. Os outros ficam numa só linha no fim do tema: `📘 *La guía también trata: … (p. N)*`. Sem desenvolvimento.
3. **Texto do Claude sem fonte:**
   - "Em palavras simples", o glossário e as respostas das perguntas de revisão ficam como estão: reformulam o que já está nos apontamentos.
   - A explicação da notação e o "porquê" de um passo que o professor não disse passam a levar **Ext.** (`💡 *Ext.: …*`). Se o professor ou a guía os disseram, não levam marca.

### Decisões de quem escreveu o design (para o Daniel confirmar ao ler)

- **Slide ↔ guía:** quando os dois dão a definição, o bloco usa o texto da guía e cita as duas fontes, *(Slide N · Guía 2.4, p. 18)*. Se diferirem num dado concreto, aparece uma tabela "Según el slide N" | "Según la guía (…, p. N)", com as mesmas regras da divergência professora ↔ guía.
- **Guías só com resumo e leituras** (Probabilidade: um parágrafo por Tema e depois "Lectura obligatoria", "Enlaces de interés", "Bibliografía recomendada"): o parágrafo entra como qualquer secção. As leituras obrigatórias de um tema dado ficam numa linha no fim da caixa 📘 desse tema ("Lectura obligatoria: Peña, cap. 3"). Os enlaces e a bibliografia recomendada ficam de fora (já vão para a ficha).
- **Factos verificados nas guías reais:** a página impressa é a do PDF menos 1 nas duas guías (calcular, não fixar); o índice de Fundamentos repete o id "6.2" (a identidade de uma secção é id + título + página); várias secções começam na mesma página.

## Restrições

- Os apontamentos continuam em Markdown, com as regras do prompt atual (👀, timestamps, "Sobre a cadeira", slides…).
- O PDF da guía pode ter até `Disco.tamanhoMaximoPDF` (24 MB). Nunca se envia o PDF inteiro em cada aula, só o texto das secções.
- Não mexer em apontamentos já gerados.
- Testes: unitários para o índice, a seleção (leitura da resposta), a montagem do pedido, a escrita 📘/Ext. e a verificação de páginas; teste de integração (`APONTAMENTOS_AULA`) com a Aula 1 de Fundamentos.

## Deixado a quem constrói

- Como tirar o índice (texto do índice, outline do PDF ou Claude) e como achar o desvio entre a página impressa e a do PDF.
- O formato exato do pedido de seleção e de `guia.json`.
- A cor da caixa 📘.
- Como mostrar o progresso dos passos novos no job ("A escolher secções da guía…").
