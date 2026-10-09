#!/bin/bash
# Instala (ou atualiza) o Recap e o Claude Code num Mac. Uso, no Terminal:
#   curl -fsSL https://raw.githubusercontent.com/danielmsrodrigues/recap/main/instalar.sh | bash
set -euo pipefail

ZIP_URL="${RECAP_ZIP_URL:-https://github.com/danielmsrodrigues/recap/releases/latest/download/Recap.zip}"
DESTINO="${RECAP_DESTINO:-/Applications}"

echo "→ A verificar o Mac…"
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "O Recap precisa de um Mac com chip Apple (M1 ou mais recente)." >&2
  exit 1
fi
versao=$(sw_vers -productVersion)
if (( ${versao%%.*} < 26 )); then
  echo "O Recap precisa do macOS 26 ou mais recente (tens o $versao). Atualiza em Definições do Sistema → Geral → Atualização de software." >&2
  exit 1
fi

echo "→ A descarregar o Recap…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "$ZIP_URL" -o "$tmp/Recap.zip"
ditto -x -k "$tmp/Recap.zip" "$tmp"
codesign --verify --deep --strict "$tmp/Recap.app"

echo "→ A instalar em $DESTINO…"
osascript -e 'tell application "Recap" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DESTINO/Recap.app"
ditto "$tmp/Recap.app" "$DESTINO/Recap.app"

# O Claude Code escreve os apontamentos com a conta Claude (Pro ou Max) de quem usa a app.
claude_ok=false
for c in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude "$HOME/.claude/local/claude" "$HOME/.npm-global/bin/claude"; do
  [[ -x "$c" ]] && claude_ok=true
done
if ! $claude_ok; then
  echo "→ A instalar o Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo
echo "✓ Recap instalado. A abrir…"
echo "  Na primeira abertura, a janela \"Preparar o Recap\" ajuda a iniciar sessão no Claude e a descarregar o modelo de transcrição."
[[ -n "${RECAP_NAO_ABRIR:-}" ]] || open "$DESTINO/Recap.app"
