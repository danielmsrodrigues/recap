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

## Licenças de terceiros

Inclui o [KaTeX](https://katex.org), o [marked](https://marked.js.org) e o [Turndown](https://github.com/mixmark-io/turndown), todos com licença MIT; as licenças estão em `Web/`. A transcrição usa o [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT).
