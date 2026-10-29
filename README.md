# Recap

App para Mac que transforma aulas em apontamentos de estudo em português (PT-PT). Transcreve a aula com o Whisper, no próprio Mac, e o Claude escreve os apontamentos com fórmulas em LaTeX, glossário, dúvidas e perguntas de revisão.

- **Fontes:** um vídeo da aula, ou o som de uma aula ao vivo ou de uma gravação a tocar no browser ("Transcrever em direto").
- **Slides:** apanha os slides do vídeo ou da janela da aula. Também aceita os PDFs dos slides do professor, um ou mais por aula.
- **Estudo:**
  - perguntas à aula, num painel ao lado dos apontamentos;
  - exercícios extra, com a resolução escondida;
  - ligações entre as aulas da cadeira;
  - procura em todas as aulas.
- **Exportação:** apontamentos em PDF (para o Freeform, iPad…) ou em Markdown.
- **iPad e iPhone:** tudo o que é estudo, com as aulas sincronizadas pelo iCloud Drive (ver abaixo). A gravação e a transcrição ficam no Mac.

As aulas ficam em `~/Aulas/<cadeira>/<data>_<título>/`, em ficheiros normais. A pasta muda-se em Definições → Aulas (por exemplo para o iCloud Drive). Nada é enviado para lado nenhum além do pedido ao Claude.

## Requisitos

- Mac com chip Apple (M1 ou mais recente) e macOS 26 ou mais recente.
- Conta Claude Pro ou Max. Os apontamentos contam para os limites da subscrição, sem custos extra. Em alternativa, uma chave da API da Anthropic (Definições → Geração).

## Instalar

Abre o **Terminal** (está em Aplicações → Utilitários), cola esta linha e carrega em Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/danielmsrodrigues/recap/main/instalar.sh | bash
```

O script instala o Recap em Aplicações e, se ainda não o tiveres, o Claude Code. Depois abre a app.

Na primeira abertura, a janela **Preparar o Recap** guia os três passos que faltam, cada um com o seu botão:

1. **Iniciar sessão no Claude:** abre o Terminal; fazes login no browser com a tua conta.
2. **Descarregar o modelo de transcrição:** cerca de 1,5 GB, só uma vez.
3. **Autorizar a gravação de ecrã:** só para transcrever em direto. Depois de autorizar, volta a abrir o Recap.

**Atualizações:** o Recap procura versões novas ao abrir (uma vez por dia) e pergunta se queres atualizar; fecha, atualiza-se e volta a abrir. Também está em **Recap → Procurar atualizações…**.

<details>
<summary>Instalar sem o Terminal</summary>

1. Em [Releases](../../releases), descarrega o `Recap.zip` da versão mais recente, abre-o e arrasta o Recap para Aplicações.
2. Da primeira vez, o macOS diz que não consegue verificar o programador, porque a app não está registada na Apple. Clica em OK, vai a Definições do Sistema → Privacidade e Segurança, carrega em **Abrir na mesma** e confirma.
3. Instala o Claude Code com o [instalador oficial](https://claude.com/claude-code). O resto faz-se na janela Preparar o Recap.

</details>

## Como usar

- **Vídeo de uma aula:** arrasta o vídeo (.mp4, .mov) para a janela, ou usa **+ → Importar vídeo…**.
- **Aula ao vivo ou gravação no browser:** usa **+ → Transcrever em direto…** e escolhe a janela da aula.
  - Para os slides saírem, a janela da aula tem de estar à vista, por exemplo noutro monitor.
  - O Recap termina sozinho ao fim de 3 minutos de silêncio.
- **PDFs dos slides do professor:** dentro da aula, abre o menu **Slides do professor** (podes juntar vários; o Claude usa só as páginas dadas nessa aula).
- **Sobre a cadeira:** a primeira linha de cada cadeira na barra lateral. Junta numa ficha a avaliação, as datas, o programa e os avisos de todas as aulas, e vai crescendo a cada aula. Para começar já com o essencial, junta o programa da cadeira em PDF no menu **Programa**.
- **Revisão:** o ponto azul na barra lateral marca as aulas por rever. Marca-as como revistas no botão do canto superior direito.

## No iPad e no iPhone

No iPad e no iPhone fazes tudo o que é estudo:

- lês e editas os apontamentos, com as fórmulas;
- vês os slides, os PDFs do professor e a transcrição;
- tens a ficha da cadeira, as ligações e a procura em todas as aulas;
- marcas as aulas como revistas;
- perguntas à aula, pedes exercícios e guardas as respostas em PDF.

Gravar e transcrever continua a ser só no Mac.

1. **No Mac, põe as aulas no iCloud Drive:** em Definições → Aulas, escolhe uma pasta do iCloud Drive (por exemplo `iCloud Drive/Aulas`) e deixa o Recap movê-las.
2. **Instala o Recap no iPad ou no iPhone pelo TestFlight:** pede o convite a quem publica.
3. **Na primeira abertura, escolhe essa mesma pasta:** o Recap lembra-se dela.

As perguntas à aula, os exercícios e as ligações vão para o **Recap do Mac**, que responde com o Claude Code e a tua subscrição, sem custos extra:

- O Mac tem de estar ligado, com o Recap aberto. Para não adormecer quando está ligado à corrente, desliga a pausa automática em Definições do Sistema → Bateria → Opções.
- A resposta demora alguns segundos a mais do que no Mac: vai e volta pelo iCloud.
- Se o Mac não responder, o iPad avisa. Em alternativa, em Definições (⚙︎) escolhe "API da Anthropic" e guarda uma chave, que fica só nesse dispositivo.
- No Mac, a opção está em Definições → Claude → "Responder às perguntas feitas no iPad e no iPhone".

Se editares os mesmos apontamentos em dois dispositivos sem rede, fica a versão mais recente. A outra é guardada na pasta da aula, como `apontamentos.conflito-<data>.md`. As perguntas feitas nos dois juntam-se numa só conversa.

## Compilar a partir do código

Precisas do Xcode 26 ou mais recente.

```bash
git clone https://github.com/danielmsrodrigues/recap.git
cd recap
open Apontamentos.xcodeproj
```

O projeto assina com o certificado "Apple Development: Sérgio Ferreira (7T6235VJN6)", que não vais ter. No Xcode, em Signing & Capabilities do alvo Apontamentos, muda para **Sign to Run Locally**.

As versões publicadas têm de ser assinadas sempre com esse certificado: o Recap só aceita uma atualização assinada pelo mesmo certificado da versão instalada. Quem publica importa-o no Acesso a Porta-chaves a partir do `.p12` (com a chave privada) e confirma com `security find-identity -v -p codesigning`.

O `Ferramentas/publicar.sh` compila a versão final e instala-a em /Applications. Com `--github 1.3`, também a publica como release (as apps instaladas atualizam-se a partir daí).

A app do iPad e do iPhone é o alvo **Recap iOS** do mesmo projeto. Partilha com o Mac o código do estudo; o que é só do iOS está em `Apontamentos iOS/`. Para a correr no simulador, escolhe o esquema "Recap iOS".

Para enviar uma versão para o TestFlight, a app `pt.danielrodrigues.Recap.ios` tem de existir no App Store Connect. Depois corre:

```bash
RECAP_EQUIPA=<ID da equipa> Ferramentas/publicar-ios.sh --versao 1.3
```

O script entra na conta da equipa de uma de duas formas: pela conta configurada em Xcode → Definições → Contas, ou por uma chave da API do App Store Connect (`RECAP_ASC_CHAVE`, `RECAP_ASC_ID`, `RECAP_ASC_EMISSOR`).

## Licenças de terceiros

Inclui o [KaTeX](https://katex.org), o [marked](https://marked.js.org) e o [Turndown](https://github.com/mixmark-io/turndown), todos com licença MIT; as licenças estão em `Web/`. A transcrição usa o [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT).
