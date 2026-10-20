// Renderiza os apontamentos (Markdown + matemática) e permite editá-los como num processador de texto.
//
// A app chama:
//   renderMarkdown(texto, emStreaming, base)   mostra os apontamentos (base: de onde vêm as imagens da aula)
//   definirEdicao(true|false)            liga/desliga a edição direta
//   comando(nome, valor)                 negrito, títulos, listas, fórmula, desfazer…
//   obterMarkdown()                      devolve o documento editado em Markdown
//   perguntarSelecao()                   pergunta sobre o texto selecionado (menu de contexto da app)
//   procurarTexto(termo) / andarProcura(±1) / limparProcura()   procurar na página (⌘F)
//   irParaSeccao(indice)                 mostra o n-ésimo título e realça-o por instantes
// e recebe as mensagens "timestamp" (segundos), "alterado", "formato", "selecao" (há texto selecionado
// para perguntar), "perguntar" (o texto selecionado, em Markdown), "procura" ({total, atual}) e
// "seccao" ({ancora, texto}: clicou-se num link `[Título](#ancora)`).
(function () {
  "use strict";

  const enviar = (nome, valor) => {
    const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[nome];
    if (h) h.postMessage(valor);
  };
  const raiz = () => document.getElementById("conteudo");
  const escaparAtributo = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

  // MARK: Markdown → HTML

  // Tira a matemática antes do marked, para que _ * \ dentro das fórmulas não sejam lidos como Markdown.
  function protegerMatematica(src) {
    const formulas = [];
    const guardar = (tex, display) => {
      // Uma fórmula em bloco dentro de uma citação traz os "> " das linhas; não fazem parte do LaTeX.
      if (display) tex = tex.replace(/^[ \t]*(?:>[ \t]?)+/gm, "");
      formulas.push({ tex: tex.trim(), display });
      return "@@MATH" + (formulas.length - 1) + "@@";
    };
    const partes = src.split(/(```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\n]*`)/g);
    for (let i = 0; i < partes.length; i += 2) {
      partes[i] = partes[i]
        .replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) => guardar(tex, true))
        .replace(/\\\[([\s\S]+?)\\\]/g, (_, tex) => guardar(tex, true))
        .replace(/\\\(([\s\S]+?)\\\)/g, (_, tex) => guardar(tex, false))
        .replace(/(^|[^\\$])\$(?=\S)((?:\\\$|[^$\n])+?)\$(?!\d)/g,
          (_, antes, tex) => antes + guardar(tex, false));
    }
    return { texto: partes.join(""), formulas };
  }

  // Cada fórmula é renderizada uma vez: durante o streaming o documento inteiro volta a passar por aqui a cada
  // pedaço, e com centenas de fórmulas o KaTeX era o que mais custava.
  const katexCache = new Map();
  function katexHTML(tex, display) {
    const chave = (display ? "D" : "I") + tex;
    const feito = katexCache.get(chave);
    if (feito !== undefined) return feito;
    let html;
    try {
      html = katex.renderToString(tex, { displayMode: display, throwOnError: false, strict: "ignore", output: "html" });
    } catch (e) {
      html = '<span class="erro-math">' + escaparAtributo(tex) + "</span>";
    }
    if (katexCache.size > 5000) katexCache.clear();
    katexCache.set(chave, html);
    return html;
  }

  // Troca só os blocos de topo que mudaram: num stream só o último muda, e substituir o `innerHTML` inteiro
  // deitava fora o DOM todo (e as imagens já carregadas) a cada pedaço.
  function substituirBlocos(r, novo) {
    const antigos = Array.from(r.childNodes);
    const novos = Array.from(novo.childNodes);
    const comuns = Math.min(antigos.length, novos.length);
    let i = 0;
    while (i < comuns && antigos[i].isEqualNode(novos[i])) i++;
    for (let k = antigos.length - 1; k >= i; k--) antigos[k].remove();
    for (let k = i; k < novos.length; k++) r.appendChild(novos[k]);
  }

  // Cada fórmula fica num bloco atómico que guarda o LaTeX original (para editar e voltar a Markdown).
  function formulaHTML(tex, display) {
    return '<span class="math' + (display ? " math-bloco" : "") + '" contenteditable="false" data-tex="' +
      escaparAtributo(tex) + '" data-display="' + (display ? 1 : 0) + '">' + katexHTML(tex, display) + "</span>";
  }

  const reTimestamp = /\[((?:\d{1,2}:)?\d{1,3}:\d{2})\]/g;
  const segundos = (ts) => ts.split(":").reduce((acc, p) => acc * 60 + parseInt(p, 10), 0);

  // Percorre só os nós de texto fora de código, fórmulas e links.
  function ligarTimestamps(elemento) {
    const walker = document.createTreeWalker(elemento, NodeFilter.SHOW_TEXT, {
      acceptNode(no) {
        // Num fragmento ainda por entrar no documento, o texto de topo não tem elemento pai.
        const pai = no.parentElement;
        if (!pai) return NodeFilter.FILTER_SKIP;
        if (pai.closest("code, pre, .math, a")) return NodeFilter.FILTER_REJECT;
        reTimestamp.lastIndex = 0;
        return reTimestamp.test(no.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
      },
    });
    const nos = [];
    while (walker.nextNode()) nos.push(walker.currentNode);
    for (const no of nos) {
      const frag = document.createDocumentFragment();
      let ultimo = 0;
      const texto = no.nodeValue;
      reTimestamp.lastIndex = 0;
      let m;
      while ((m = reTimestamp.exec(texto)) !== null) {
        frag.appendChild(document.createTextNode(texto.slice(ultimo, m.index)));
        const a = document.createElement("a");
        a.className = "ts";
        a.href = "#";
        a.contentEditable = "false";
        a.dataset.t = String(segundos(m[1]));
        a.textContent = m[1];
        frag.appendChild(a);
        ultimo = m.index + m[0].length;
      }
      frag.appendChild(document.createTextNode(texto.slice(ultimo)));
      no.parentNode.replaceChild(frag, no);
    }
  }

  const abertas = new Set();
  // Um só ouvinte para todas as resoluções (os blocos podem ser reaproveitados entre renderizações).
  document.addEventListener("toggle", (ev) => {
    const d = ev.target;
    if (!(d instanceof HTMLDetailsElement) || !d.classList.contains("resolucao")) return;
    const indice = Array.prototype.indexOf.call(raiz().querySelectorAll("details.resolucao"), d);
    if (indice < 0) return;
    if (d.open) abertas.add(indice); else abertas.delete(indice);
  }, true);

  // Slides dentro dos apontamentos: `![legenda](slides-pdf/pagina-07.jpg)`, relativo à pasta da aula,
  // servido pela app em `base`. Um `slide:N` ainda por resolver (durante o streaming) fica só com a legenda.
  function ligarImagens(elemento, base) {
    for (const img of elemento.querySelectorAll("img")) {
      const src = img.getAttribute("src") || "";
      if (src.startsWith("slide:")) {
        const s = document.createElement("span");
        s.className = "slide-pendente";
        s.contentEditable = "false";
        s.textContent = img.alt || "Slide";
        s.dataset.marca = "![" + (img.alt || "") + "](" + src + ")";
        img.replaceWith(s);
        continue;
      }
      if (base && !/^[a-z][a-z0-9+.-]*:/i.test(src)) {
        // O marked já codifica o src (espaços → %20): descodificar antes de voltar a codificar.
        const relativo = src.split("/").map((p) => { try { return decodeURIComponent(p); } catch (e) { return p; } });
        img.dataset.src = relativo.join("/");
        img.src = base + relativo.map(encodeURIComponent).join("/");
      }
      img.classList.add("slide");
      const p = img.parentElement;
      if (p && p.tagName === "P" && p.children.length === 1 && !p.textContent.trim()) {
        p.classList.add("figura");
        if (img.alt) {
          const legenda = document.createElement("span");
          legenda.className = "legenda";
          legenda.contentEditable = "false";
          legenda.textContent = img.alt;
          p.appendChild(legenda);
        }
      }
    }
  }

  window.renderMarkdown = function (md, emStreaming, base) {
    const r = raiz();
    const perto = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
    const { texto, formulas } = protegerMatematica(md || "");
    let html = marked.parse(texto, { gfm: true, breaks: false });
    html = html.replace(/@@MATH(\d+)@@/g, (_, i) => formulaHTML(formulas[Number(i)].tex, formulas[Number(i)].display));
    // Monta-se tudo à parte e só depois entra no documento, para comparar com o que lá está.
    const novo = document.createElement("template");
    novo.innerHTML = html;
    const n = novo.content;
    ligarTimestamps(n);
    ligarImagens(n, base);
    // Explicações que o professor não deu: destacadas à parte das definições.
    let resolucoes = 0;
    for (const q of n.querySelectorAll("blockquote")) {
      const t = q.textContent.trim();
      if (t.startsWith("💡")) q.classList.add("extra");
      else if (t.startsWith("⭐")) q.classList.add("importante");
      else if (t.startsWith("⚠")) q.classList.add("erro-comum");
      // Resolução dos exercícios: escondida até o estudante a abrir (o estado sobrevive ao streaming).
      else if (/^Resolução\b/.test(t)) {
        const d = document.createElement("details");
        d.className = "resolucao";
        const indice = resolucoes++;
        if (abertas.has(indice)) d.open = true;
        const s = document.createElement("summary");
        s.textContent = "Ver resolução";
        q.replaceWith(d);
        d.append(s, q);
      }
    }
    // Links para secções dos apontamentos (`[Título](#ancora)`, nas respostas do painel das perguntas).
    for (const a of n.querySelectorAll('a[href^="#"]:not(.ts)')) {
      if (a.getAttribute("href").length < 2) continue;
      a.classList.add("seccao");
      a.title = "Ir para esta secção nos apontamentos";
    }
    substituirBlocos(r, n);
    alterado = false;
    esconderPerguntar();
    // O documento é outro: a procura em curso volta a ser feita, sem mexer no scroll.
    if (procura.termo) procurarTexto(procura.termo, true);
    if (emStreaming && perto) window.scrollTo(0, document.body.scrollHeight);
  };

  // MARK: HTML → Markdown

  let turndown = null;
  function conversor() {
    if (turndown) return turndown;
    turndown = new TurndownService({
      headingStyle: "atx", bulletListMarker: "-", codeBlockStyle: "fenced", emDelimiter: "*", strongDelimiter: "**",
    });
    turndown.use(turndownPluginGfm.gfm);
    turndown.addRule("itemLista", {
      filter: "li",
      replacement: (conteudo, no, opcoes) => {
        conteudo = conteudo.replace(/^\n+/, "").replace(/\n+$/, "\n").replace(/\n/gm, "\n   ");
        let prefixo = opcoes.bulletListMarker + " ";
        const pai = no.parentNode;
        if (pai.nodeName === "OL") {
          const inicio = Number(pai.getAttribute("start") || 1);
          prefixo = inicio + Array.prototype.indexOf.call(pai.children, no) + ". ";
        }
        return prefixo + conteudo + (no.nextSibling && !/\n$/.test(conteudo) ? "\n" : "");
      },
    });
    turndown.addRule("formula", {
      filter: (no) => no.nodeName === "SPAN" && no.classList.contains("math"),
      replacement: (_, no) => no.dataset.display === "1"
        ? "\n\n$$\n" + no.dataset.tex + "\n$$\n\n"
        : "$" + no.dataset.tex + "$",
    });
    turndown.addRule("timestamp", {
      filter: (no) => no.nodeName === "A" && no.classList.contains("ts"),
      replacement: (conteudo) => "[" + conteudo + "]",
    });
    // As imagens voltam ao caminho relativo à pasta da aula (o src aponta para a app).
    turndown.addRule("imagem", {
      filter: "img",
      replacement: (_, no) => "![" + (no.getAttribute("alt") || "") + "](" + (no.dataset.src || no.getAttribute("src") || "") + ")",
    });
    // O editor de fórmulas e as legendas dos slides (vêm do texto alternativo) não fazem parte do documento.
    turndown.remove((no) => no.id === "editor-formula" ||
      (no.nodeName === "SPAN" && no.classList.contains("legenda")));
    // Uma marca de slide que ficou por resolver volta tal como estava.
    turndown.addRule("slidePendente", {
      filter: (no) => no.nodeName === "SPAN" && no.classList.contains("slide-pendente"),
      replacement: (_, no) => no.dataset.marca || "",
    });
    return turndown;
  }

  window.obterMarkdown = function () {
    return conversor().turndown(raiz().innerHTML).replace(/\n{3,}/g, "\n\n").trim() + "\n";
  };

  // MARK: Edição

  let alterado = false;
  function marcarAlterado() {
    alterado = true;
    enviar("alterado", true);
  }

  // Histórico próprio de desfazer/refazer: as mudanças de bloco são feitas no DOM e o desfazer nativo não as vê.
  let historico = [], futuro = [], esperaEscrita = null;

  function posicaoCursor() {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount || !raiz().contains(sel.anchorNode)) return null;
    const r = document.createRange();
    r.selectNodeContents(raiz());
    r.setEnd(sel.anchorNode, sel.anchorOffset);
    return r.toString().length;
  }

  function porCursor(pos) {
    if (pos == null) return;
    const walker = document.createTreeWalker(raiz(), NodeFilter.SHOW_TEXT);
    let resto = pos, no;
    while ((no = walker.nextNode())) {
      if (resto <= no.nodeValue.length) {
        if (no.parentElement.closest('[contenteditable="false"]')) continue;
        const r = document.createRange();
        r.setStart(no, resto);
        r.collapse(true);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(r);
        return;
      }
      resto -= no.nodeValue.length;
    }
  }

  function guardarEstado() {
    clearTimeout(esperaEscrita);
    esperaEscrita = null;
    const html = raiz().innerHTML;
    if (historico.length && historico[historico.length - 1].html === html) return;
    historico.push({ html, cursor: posicaoCursor() });
    if (historico.length > 200) historico.shift();
    futuro = [];
  }

  function repor(estado) {
    raiz().innerHTML = estado.html;
    porCursor(estado.cursor);
    marcarAlterado();
    informarFormato();
  }

  function desfazer() {
    if (esperaEscrita) guardarEstado();
    if (historico.length < 2) return;
    futuro.push(historico.pop());
    repor(historico[historico.length - 1]);
  }

  function refazer() {
    if (!futuro.length) return;
    const e = futuro.pop();
    historico.push(e);
    repor(e);
  }

  window.definirEdicao = function (ligar) {
    const r = raiz();
    r.contentEditable = ligar ? "true" : "false";
    document.body.classList.toggle("editar", ligar);
    fecharEditorFormula(false);
    esconderPerguntar();
    alterado = false;
    historico = ligar ? [{ html: r.innerHTML, cursor: null }] : [];
    futuro = [];
    if (ligar) r.focus();
  };

  window.comando = function (nome, valor) {
    const r = raiz();
    if (r.contentEditable !== "true") return;
    r.focus();
    if (esperaEscrita) guardarEstado();
    switch (nome) {
      case "undo": desfazer(); return;
      case "redo": refazer(); return;
      case "formula": inserirFormula(valor === "bloco"); return;
      case "formatBlock": mudarBloco(valor); break;
      default: document.execCommand(nome, false, valor || null);
    }
    guardarEstado();
    marcarAlterado();
    informarFormato();
  };

  function blocoAtual() {
    const sel = window.getSelection();
    if (!sel || !sel.anchorNode) return null;
    const el = sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement;
    const b = el && el.closest("p, h1, h2, h3, h4, h5, h6, li");
    return b && raiz().contains(b) ? b : null;
  }

  // Normal / títulos / definição (citação). O formatBlock do WebKit parte os parágrafos nas fórmulas.
  function mudarBloco(tag) {
    const b = blocoAtual();
    if (!b) return;
    const cursor = posicaoCursor();
    const citacao = b.closest("blockquote");
    if (tag === "blockquote") {
      if (citacao) {
        while (citacao.firstChild) citacao.parentNode.insertBefore(citacao.firstChild, citacao);
        citacao.remove();
      } else {
        const bloco = b.tagName === "LI" ? b.closest("ul, ol") : b;
        const q = document.createElement("blockquote");
        bloco.parentNode.insertBefore(q, bloco);
        q.appendChild(bloco);
      }
    } else if (b.tagName !== "LI" && b.tagName.toLowerCase() !== tag) {
      const novo = document.createElement(tag);
      while (b.firstChild) novo.appendChild(b.firstChild);
      b.replaceWith(novo);
    }
    porCursor(cursor);
  }

  // Estado da seleção para a barra de formatação da app.
  function informarFormato() {
    if (raiz().contentEditable !== "true") return;
    const b = blocoAtual();
    let bloco = b ? b.tagName.toLowerCase() : "p";
    if (b && b.closest("blockquote")) bloco = "blockquote";
    // Só conta como negrito/itálico se estiver marcado no texto (um título é negrito por estilo, não por marcação).
    const sel = window.getSelection();
    const el = sel && sel.anchorNode ? (sel.anchorNode.nodeType === 1 ? sel.anchorNode : sel.anchorNode.parentElement) : null;
    const formato = {
      negrito: !!(el && el.closest("b, strong")) || (document.queryCommandState("bold") && !(b && /^H\d$/.test(b.tagName))),
      italico: !!(el && el.closest("i, em")) || document.queryCommandState("italic"),
      bloco: bloco,
    };
    const chave = JSON.stringify(formato);
    if (chave !== ultimoFormato) { ultimoFormato = chave; enviar("formato", formato); }
  }
  let ultimoFormato = "";
  document.addEventListener("selectionchange", informarFormato);

  document.addEventListener("input", (ev) => {
    if (!raiz().contains(ev.target)) return;
    marcarAlterado();
    clearTimeout(esperaEscrita);
    esperaEscrita = setTimeout(guardarEstado, 700);
  });

  document.addEventListener("keydown", (ev) => {
    if (raiz().contentEditable !== "true" || !ev.metaKey) return;
    const k = ev.key.toLowerCase();
    if (k === "z") { ev.preventDefault(); comando(ev.shiftKey ? "redo" : "undo"); }
    else if (k === "b") { ev.preventDefault(); comando("bold"); }
    else if (k === "i") { ev.preventDefault(); comando("italic"); }
  });

  // MARK: Fórmulas

  let formulaAtual = null;
  let formulaNova = false;

  function abrirEditorFormula(span, nova) {
    fecharEditorFormula(false);
    formulaAtual = span;
    formulaNova = nova;
    const caixa = document.createElement("div");
    caixa.id = "editor-formula";
    caixa.contentEditable = "false";
    caixa.innerHTML =
      '<div class="ef-titulo">Fórmula (LaTeX)</div>' +
      '<textarea spellcheck="false" rows="3"></textarea>' +
      '<label class="ef-bloco"><input type="checkbox"> Em linha própria</label>' +
      '<div class="ef-previa"></div>' +
      '<div class="ef-botoes"><button class="ef-cancelar">Cancelar</button><button class="ef-aplicar">Aplicar</button></div>';
    document.body.appendChild(caixa);
    const area = caixa.querySelector("textarea");
    const bloco = caixa.querySelector("input");
    const previa = caixa.querySelector(".ef-previa");
    area.value = span.dataset.tex || "";
    bloco.checked = span.dataset.display === "1";
    const atualizar = () => { previa.innerHTML = area.value.trim() ? katexHTML(area.value, bloco.checked) : "<em>Escreve a fórmula, por ex. \\frac{a}{b}</em>"; };
    area.addEventListener("input", atualizar);
    bloco.addEventListener("change", atualizar);
    area.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter" && (ev.metaKey || !ev.shiftKey)) { ev.preventDefault(); fecharEditorFormula(true); }
      if (ev.key === "Escape") { ev.preventDefault(); fecharEditorFormula(false); }
    });
    caixa.querySelector(".ef-aplicar").addEventListener("click", () => fecharEditorFormula(true));
    caixa.querySelector(".ef-cancelar").addEventListener("click", () => fecharEditorFormula(false));
    const r = span.getBoundingClientRect();
    caixa.style.top = Math.min(window.innerHeight - 260, r.bottom + 8) + window.scrollY + "px";
    caixa.style.left = Math.max(12, Math.min(window.innerWidth - 432, r.left)) + "px";
    atualizar();
    area.focus();
  }

  function fecharEditorFormula(aplicar) {
    const caixa = document.getElementById("editor-formula");
    if (!caixa) return;
    const span = formulaAtual;
    const tex = caixa.querySelector("textarea").value.trim();
    const bloco = caixa.querySelector("input").checked;
    caixa.remove();
    formulaAtual = null;
    if (!span) return;
    if (aplicar && tex) {
      span.dataset.tex = tex;
      span.dataset.display = bloco ? "1" : "0";
      span.classList.toggle("math-bloco", bloco);
      span.innerHTML = katexHTML(tex, bloco);
      guardarEstado();
      marcarAlterado();
    } else if (formulaNova) {
      span.remove();
    }
    formulaNova = false;
  }

  function inserirFormula(bloco) {
    const span = document.createElement("span");
    span.className = "math" + (bloco ? " math-bloco" : "");
    span.contentEditable = "false";
    span.dataset.tex = "";
    span.dataset.display = bloco ? "1" : "0";
    span.textContent = "□";
    const sel = window.getSelection();
    if (sel && sel.rangeCount && raiz().contains(sel.anchorNode)) {
      const range = sel.getRangeAt(0);
      range.deleteContents();
      range.insertNode(span);
      range.setStartAfter(span);
      range.collapse(true);
      sel.removeAllRanges();
      sel.addRange(range);
    } else {
      raiz().appendChild(span);
    }
    abrirEditorFormula(span, true);
  }

  document.addEventListener("dblclick", (ev) => {
    const span = ev.target.closest(".math");
    if (span && raiz().contentEditable === "true") { ev.preventDefault(); abrirEditorFormula(span, false); }
  });

  // MARK: Timestamps

  document.addEventListener("click", (ev) => {
    const a = ev.target.closest("a.ts");
    if (!a) return;
    ev.preventDefault();
    enviar("timestamp", Number(a.dataset.t));
  });

  // MARK: Secções

  document.addEventListener("click", (ev) => {
    const a = ev.target.closest("a.seccao");
    if (!a || raiz().contentEditable === "true") return;
    ev.preventDefault();
    let ancora = a.getAttribute("href").slice(1);
    try { ancora = decodeURIComponent(ancora); } catch (e) {}
    enviar("seccao", { ancora, texto: a.textContent });
  });

  const titulosDeTopo = () => raiz().querySelectorAll(":scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6");

  // A app resolve a âncora para a posição do título (é o mesmo n-ésimo título no Markdown).
  window.irParaSeccao = function (indice) {
    const h = titulosDeTopo()[indice];
    if (!h) return false;
    const mostrar = (suave) => h.scrollIntoView({ behavior: suave ? "smooth" : "auto", block: "start" });
    mostrar(true);
    // As imagens dos slides acima do título ainda a carregar empurravam-no para baixo do ecrã.
    const ate = Date.now() + 2000;
    for (const img of raiz().querySelectorAll("img")) {
      if (!img.complete) img.addEventListener("load", () => { if (Date.now() < ate) mostrar(false); }, { once: true });
    }
    h.classList.remove("seccao-realcada");
    void h.offsetWidth;
    h.classList.add("seccao-realcada");
    clearTimeout(h._realce);
    h._realce = setTimeout(() => h.classList.remove("seccao-realcada"), 2400);
    return true;
  };

  // MARK: Procurar na página

  // Realça todas as ocorrências sem mexer no documento (CSS Custom Highlight API: também serve a editar) e anda entre
  // elas. Sem distinguir maiúsculas nem acentos, como a pesquisa global.
  const procura = { termo: "", ranges: [], atual: -1 };
  const semAcentos = (s) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

  // O texto visível dos apontamentos já normalizado, com a origem (nó, posição, tamanho) de cada carácter.
  function textoProcuravel() {
    const nos = [], mapa = [];
    let texto = "", blocoAnterior = null;
    const walker = document.createTreeWalker(raiz(), NodeFilter.SHOW_TEXT, {
      acceptNode: (no) => no.parentElement.closest(".math, #editor-formula") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    while (walker.nextNode()) {
      const no = walker.currentNode;
      const bloco = no.parentElement.closest("p, li, h1, h2, h3, h4, h5, h6, td, th, pre, blockquote, summary, figcaption, main");
      // Uma ocorrência não atravessa parágrafos.
      if (bloco !== blocoAnterior && texto) { texto += "\n"; mapa.push(null); }
      blocoAnterior = bloco;
      const n = nos.push(no) - 1;
      let o = 0;
      for (const c of no.nodeValue) {
        if (/\s/.test(c)) {
          if (!texto.endsWith(" ")) { texto += " "; mapa.push({ n, o, l: c.length }); }
        } else {
          // Por unidade UTF-16 (um emoji ocupa duas), para o índice no texto ser o mesmo no mapa.
          const d = semAcentos(c);
          texto += d;
          for (let k = 0; k < d.length; k++) mapa.push({ n, o, l: c.length });
        }
        o += c.length;
      }
    }
    return { nos, mapa, texto };
  }

  function pintarProcura() {
    if (!(window.CSS && CSS.highlights && window.Highlight)) return;
    CSS.highlights.delete("procura");
    CSS.highlights.delete("procura-atual");
    if (!procura.ranges.length) return;
    CSS.highlights.set("procura", new Highlight(...procura.ranges));
    const atual = new Highlight(procura.ranges[procura.atual]);
    atual.priority = 1;
    CSS.highlights.set("procura-atual", atual);
  }

  function informarProcura() {
    enviar("procura", { total: procura.ranges.length, atual: procura.atual });
  }

  function mostrarAtual() {
    const range = procura.ranges[procura.atual];
    if (!range) return;
    // Uma ocorrência dentro de uma resolução fechada: abre-a.
    let d = range.startContainer.parentElement.closest("details");
    while (d) {
      d.open = true;
      d = d.parentElement && d.parentElement.closest("details");
    }
    const r = range.getBoundingClientRect();
    if (r.top < 70 || r.bottom > window.innerHeight - 50) {
      window.scrollTo({ top: window.scrollY + r.top - window.innerHeight / 3, behavior: "smooth" });
    }
  }

  // `manter`: o mesmo termo depois de o documento mudar; fica na mesma ocorrência e não faz scroll.
  window.procurarTexto = function (termo, manter) {
    const alvo = semAcentos(String(termo || "")).replace(/\s+/g, " ").trim();
    procura.termo = alvo ? termo : "";
    procura.ranges = [];
    if (alvo) {
      const { nos, mapa, texto } = textoProcuravel();
      let i = texto.indexOf(alvo);
      while (i !== -1 && procura.ranges.length < 2000) {
        const a = mapa[i], b = mapa[i + alvo.length - 1];
        if (a && b) {
          const range = document.createRange();
          range.setStart(nos[a.n], a.o);
          range.setEnd(nos[b.n], b.o + b.l);
          procura.ranges.push(range);
        }
        i = texto.indexOf(alvo, i + alvo.length);
      }
    }
    const total = procura.ranges.length;
    if (!total) procura.atual = -1;
    else if (manter) procura.atual = Math.min(Math.max(procura.atual, 0), total - 1);
    else {
      // A primeira ocorrência a partir do que está no ecrã.
      const i = procura.ranges.findIndex((r) => r.getBoundingClientRect().bottom > 0 && r.getClientRects().length);
      procura.atual = i === -1 ? 0 : i;
    }
    pintarProcura();
    informarProcura();
    if (!manter) mostrarAtual();
  };

  window.andarProcura = function (passo) {
    const total = procura.ranges.length;
    if (!total) return;
    procura.atual = (procura.atual + passo + total) % total;
    pintarProcura();
    informarProcura();
    mostrarAtual();
  };

  window.limparProcura = function () {
    procura.termo = "";
    procura.ranges = [];
    procura.atual = -1;
    pintarProcura();
  };

  // A editar, as posições mudam: a procura refaz-se pouco depois de cada alteração.
  let esperaProcura = null;
  document.addEventListener("input", () => {
    if (!procura.termo) return;
    clearTimeout(esperaProcura);
    esperaProcura = setTimeout(() => procurarTexto(procura.termo, true), 300);
  });

  // MARK: Perguntar sobre a seleção

  // A ler (não a editar), o texto selecionado ganha um botão "Perguntar" que o manda para o painel das perguntas.
  // Só onde a app o pede (`window.podePerguntar`, posto antes de a página carregar).
  let botaoPerguntar = null, textoPerguntar = "", haSelecao = false, aPremir = false, esperaSelecao = null;

  // O texto selecionado em Markdown (fórmulas em LaTeX, `[mm:ss]`), ou null se não for nos apontamentos.
  function selecaoAtual() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
    // Só a parte dentro dos apontamentos (⌘A ou um arrastar que sai da página apanham mais).
    const range = sel.getRangeAt(0).cloneRange();
    const r = raiz();
    if (!r.contains(range.commonAncestorContainer)) {
      if (!range.intersectsNode(r)) return null;
      if (!r.contains(range.startContainer)) range.setStart(r, 0);
      if (!r.contains(range.endContainer)) range.setEnd(r, r.childNodes.length);
    }
    const caixa = document.createElement("div");
    caixa.appendChild(range.cloneContents());
    // Um slide vale pela legenda (o caminho da imagem não diz nada).
    for (const img of caixa.querySelectorAll("img")) img.replaceWith("(" + (img.alt || "Slide") + ")");
    const texto = conversor().turndown(caixa.innerHTML).trim();
    return texto.length >= 2 ? { range, texto } : null;
  }

  function botao() {
    if (botaoPerguntar) return botaoPerguntar;
    const b = document.createElement("button");
    b.id = "perguntar-selecao";
    b.type = "button";
    b.title = "Perguntar sobre o texto selecionado";
    b.innerHTML = '<svg viewBox="0 0 16 16"><path d="M8 0l1.8 6.2L16 8l-6.2 1.8L8 16l-1.8-6.2L0 8l6.2-1.8z"/></svg>Perguntar';
    b.style.display = "none";
    // Sem isto o clique tirava a seleção antes de chegar ao botão.
    b.addEventListener("mousedown", (ev) => ev.preventDefault());
    b.addEventListener("click", (ev) => { ev.preventDefault(); perguntarSelecao(); });
    document.body.appendChild(b);
    botaoPerguntar = b;
    return b;
  }

  function informarSelecao(ha) {
    if (ha !== haSelecao) { haSelecao = ha; enviar("selecao", ha); }
  }

  function esconderPerguntar() {
    textoPerguntar = "";
    if (botaoPerguntar) botaoPerguntar.style.display = "none";
    informarSelecao(false);
  }

  function atualizarPerguntar() {
    if (!window.podePerguntar) return;
    const s = raiz().contentEditable === "true" || aPremir ? null : selecaoAtual();
    if (!s) { esconderPerguntar(); return; }
    textoPerguntar = s.texto;
    // Por baixo do fim da seleção, ou por cima se não couber.
    const rects = s.range.getClientRects();
    const r = rects.length ? rects[rects.length - 1] : s.range.getBoundingClientRect();
    const b = botao();
    b.style.display = "flex";
    const largura = b.offsetWidth, altura = b.offsetHeight;
    const topo = r.bottom + altura + 10 > window.innerHeight ? r.top - altura - 6 : r.bottom + 6;
    b.style.top = topo + window.scrollY + "px";
    b.style.left = Math.max(8, Math.min(window.innerWidth - largura - 8, r.right - largura)) + window.scrollX + "px";
    informarSelecao(true);
  }

  window.perguntarSelecao = function () {
    const s = selecaoAtual();
    const texto = s ? s.texto : textoPerguntar;
    if (!texto) return;
    enviar("perguntar", texto);
    window.getSelection().removeAllRanges();
    esconderPerguntar();
  };

  document.addEventListener("selectionchange", () => {
    clearTimeout(esperaSelecao);
    esperaSelecao = setTimeout(atualizarPerguntar, 200);
  });
  // Enquanto se arrasta a seleção o botão não aparece (o menu de contexto, com o botão direito, mantém-na).
  document.addEventListener("mousedown", (ev) => {
    if (ev.button !== 0 || ev.ctrlKey || (botaoPerguntar && botaoPerguntar.contains(ev.target))) return;
    aPremir = true;
    esconderPerguntar();
  });
  // Com o botão direito o WebKit seleciona a palavra antes de abrir o menu: a app tem de o saber já.
  document.addEventListener("contextmenu", () => {
    clearTimeout(esperaSelecao);
    atualizarPerguntar();
  });
  window.addEventListener("resize", () => { if (textoPerguntar) atualizarPerguntar(); });
  document.addEventListener("mouseup", () => {
    if (!aPremir) return;
    aPremir = false;
    setTimeout(atualizarPerguntar, 0);
  });
})();
