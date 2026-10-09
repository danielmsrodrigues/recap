#!/bin/zsh
# Compila a versão final do Recap, instala-a em /Applications e (com --github vX.Y) publica-a como release.
# Uso: Ferramentas/publicar.sh            → só compila e instala
#      Ferramentas/publicar.sh --github 1.0 → também cria a release v1.0 no GitHub com o Recap.zip
set -euo pipefail
cd "${0:A:h}/.."

xcodebuild -project Apontamentos.xcodeproj -scheme Apontamentos -configuration Release \
  -derivedDataPath build/DerivedData build | grep -E "error|BUILD" || true
app=build/DerivedData/Build/Products/Release/Recap.app
codesign --verify --deep --strict "$app"

osascript -e 'tell application "Recap" to quit' 2>/dev/null || true
sleep 1
ditto "$app" /Applications/Recap.app
echo "Instalado em /Applications/Recap.app"

if [[ "${1:-}" == "--github" ]]; then
  versao="v${2:?indica a versão, por exemplo: --github 1.0}"
  zip=build/Recap.zip
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  gh release create "$versao" "$zip" --title "Recap $versao" --notes "Descarrega o Recap.zip, abre-o e arrasta o Recap para Aplicações. Instruções no README."
fi
