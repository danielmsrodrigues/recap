# Estudar para o exame: "Não estou a perceber", "Sai no exame" e Perguntar à cadeira

Pedido do Daniel (30 out 2026), três funcionalidades, por esta ordem (da mais simples para a maior). Cada uma é um PR.
Nada se compila nem testa durante uma aula a ser gravada.

## 1. "Não estou a perceber" (PR 1)

Durante a captação em direto, um botão guarda o segundo da aula. Os apontamentos explicam melhor esse momento.

- **Modelo:** `AulaMeta.naoPercebi: [Double]?` (segundos da aula, já à velocidade da aula), com `decodeIfPresent`.
  Teste em `DiscoTests` (meta antiga abre) e um de ida e volta.
- **Sessão:** `SessaoDireto.marcarNaoPercebi()`.
  - Usa `gravador.segundos * velocidade` (não o valor da cache de 500 ms).
  - Guarda logo com `Disco.lerMeta`/`escreverMeta`, sem `recarregar()`.
  - Guarda também `marcasNaoPercebi` em memória, para o contador.
  - Teste com `CaptacaoFalsa` (como em `MudarJanelaTests`): com a sessão ativa, a marca fica no `aula.json`; sem sessão não faz nada.
- **Interface:**
  - Botão "Não estou a perceber" (`questionmark.circle`) em `DiretoView.emCurso`, com o número de marcas.
  - Item igual em `DiretoMenu`, na barra de menus, porque durante a aula a janela à frente é o browser.
- **Geração:** `ContextoAula.naoPercebi` vem de `aula.meta`. `NotesGenerator.conteudo()` acrescenta o pedido:
  - Para cada `[mm:ss]`, uma caixa `> 🤔 **Não percebeste aqui [mm:ss]:** …`, na secção desse momento.
  - A caixa explica mais devagar, com um exemplo, e na língua dos apontamentos.
  - Teste: com momentos, o pedido tem-nos e a caixa; sem momentos, não tem nada.
  - Se o Claude não cumprir de forma fiável, passa a uma segunda passagem como `ExplicacoesExtra`.
- **Na aula:** marcas laranja na `LinhaCapitulos`, nos minutos marcados; clicar leva à transcrição nesse momento.
  As caixas 🤔 ficam nos apontamentos (Mac, iPad e iPhone).

## 2. "Sai no exame" (PR 2)

O que o professor disse que entra no exame, por cadeira, com o minuto.

- **Serviço `PistasExame`**, copiado de `ExplicacoesExtra`:
  - Uma passagem própria sobre a transcrição com tempos.
  - Pede JSON `[{"tempo":"mm:ss","citacao":"…","descricao":"…"}]` e lê-o com tolerância, do primeiro `[` ao último `]`.
  - Grava em `<aula>/exame.json` (`Disco.lerPistasExame`/`escreverPistasExame`).
  - Testes: ler a resposta (chaves traduzidas, lixo à volta, lista vazia), o pedido e a gravação.
- **Pipeline:** corre a seguir à passagem dos 💡, com o mesmo tratamento de avisos e de `geracao.somar`.
- **Aulas antigas:** "Procurar nas aulas anteriores" corre a passagem nas aulas sem `exame.json`, pela fila, uma de cada vez.
- **Mac:** "Sai no exame" (`star`) na barra lateral.
  - A lista do meio mostra as pistas por cadeira: a descrição, a citação e "Aula N · mm:ss".
  - Clicar abre a aula nesse momento (`DestinoAula(separador: .transcricao, tempo:)`).
- **iPad:** o mesmo item na barra lateral.
- **iPhone:** uma secção "Sai no exame" em `CadeiraView`.

## 3. Perguntar à cadeira (PR 3)

O painel de perguntas, mas sobre todas as aulas de uma cadeira.

- **`Estudo`:** `Tipo.perguntaCadeira`, com a chave na pasta da cadeira e o histórico em `<cadeira>/perguntas-cadeira.json`.
  - O `Library.ler` só lê como aulas as subpastas com `aula.json`, por isso este ficheiro não interfere.
- **Contexto** (o Claude não lê ficheiros, porque usa `--tools ""`: vai tudo no pedido):
  - A ficha (`sobre.md`).
  - O índice da guia.
  - Os apontamentos de cada aula com os `[mm:ss]` e o prefixo da aula, até um limite de caracteres. As mais antigas resumem-se à lista de secções quando não cabem.
  - As últimas 8 perguntas e respostas.
- **Citações:** o Claude escreve `[Aula 3 · 12:34](#<prefixo-da-aula>@754)`.
  - `LigacaoSeccao` passa a aceitar `@segundos`.
  - `Estudo.destino` dá `DestinoAula(pasta:, separador: .transcricao, tempo: 754)`.
  - Testes: o pedido (ordem, limite, prefixos) e a resolução das ligações.
- **Mac:** em "Sobre a cadeira", um painel à direita como o Estudo da aula (`PerguntasCadeiraView`, com `NotesWebView` em modo conversa).
- **iPhone e iPad:** "Perguntar à cadeira" ao lado de "Sobre a cadeira".
  - Sem API, vai pelo Mac: um novo tipo em `PedidoMac`/`PonteMac`, resolvido para a pasta da cadeira.

## 4. Progresso do programa (PR 4), só com guia

Aparece só nas cadeiras com guia de estudo (`programa.pdf`, com índice em `guia.json`). Sem guia, não aparece nada.

- **Dados:** as secções que cada aula explicou, mandou estudar ou só mencionou (`SeccoesDaAula`, já guardadas por aula).
  Cada tema do índice fica "Visto", "Em curso" (só mencionado ou mandado estudar) ou "Por ver".
  Testes com um índice e três aulas.
- **Onde:** "Sobre a cadeira", com "Vistos N de M temas" e a lista por tema, cada um com as aulas onde apareceu.
  Os temas "Por ver" são os que vão ter de ser estudados só pela guia.

## 5. Perguntar durante a aula (PR 5)

Durante a captação, uma caixa de perguntas sobre o que já foi dito.

- **Contexto:** a transcrição em direto até ao momento, os slides já captados e a ficha da cadeira.
- **Onde:**
  - A janela "Em direto", com o campo e as respostas.
  - No fim, as perguntas passam para o painel Perguntas da aula.
- **Liga-se ao "Não estou a perceber":** perguntar marca também esse momento.
- **Custo:** corre pelo Claude Code, sem custo extra.
  Confirmar que a captação não se ressente: o pedido corre noutro processo, com prioridade baixa.

## 6. O livro da cadeira (PR 6)

Um PDF por cadeira com tudo para estudar sem ecrã. Fica em "Sobre a cadeira" → Partilhar → "Livro da cadeira (PDF)…".

- **Conteúdo:** a capa, o índice, a ficha e todas as aulas por ordem (os apontamentos), e o glossário no fim.
- **Como se faz:** reaproveita o PDF que já se faz por aula, juntando os PDFs.
  Os `[mm:ss]` ficam em texto, porque num livro impresso não servem de ligação.

## 7. Ouvir o resumo (PR 7)

No iPhone e no iPad, "Ouvir" lê em voz alta o resumo e as secções de uma aula, com a voz do sistema (`AVSpeechSynthesizer`).

- **Texto limpo, sem ler símbolos:**
  - Tira o markdown: `*`, `_`, `#`, `>`, as crases, as aspas, as barras das tabelas e as ligações (fica só o texto).
  - Tira os `[mm:ss]` e os emojis das caixas.
  - Os títulos passam a frases com pausa, e as listas a frases.
  - Testes com markdown real dos apontamentos: o texto falado não tem nenhum destes símbolos.
- **Voz:** na língua dos apontamentos (espanhol para a VIU).
- **Controlos:** pausa, avançar uma secção e velocidade. Continua a tocar com o ecrã bloqueado (sessão de áudio).

## Fica de fora

Perguntas para o professor (não vale a pena) e o widget do iPhone (para já não).

## Custos

Tudo corre no Mac pelo Claude Code, por isso não há custo extra. Só o iPhone ou o iPad com a API do Claude ligada é que a usam, que é paga.
