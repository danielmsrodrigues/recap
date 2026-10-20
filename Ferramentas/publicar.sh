#!/bin/zsh
# Compila a versão final do Recap e instala-a em /Applications (para testar antes de fundir).
# As releases fazem-se sozinhas: cada merge no main publica uma versão nova (.github/workflows/publicar.yml).
# Uso: Ferramentas/publicar.sh            → compila e instala
#      Ferramentas/publicar.sh --github 1.0 → à mão, se o GitHub Actions estiver em baixo: cria a release v1.0
set -euo pipefail
cd "${0:A:h}/.."

# A versão da app é a da release: é por ela que o Recap sabe se há uma atualização.
versao_app=()
[[ "${1:-}" == "--github" ]] && versao_app=("MARKETING_VERSION=${2:?indica a versão, por exemplo: --github 1.2}")

xcodebuild -project Apontamentos.xcodeproj -scheme Apontamentos -configuration Release \
  -derivedDataPath build/DerivedData build "${versao_app[@]}" | grep -E "error|BUILD" || true
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

# A cópia compilada ficava registada como mais uma app no macOS e aparecia no Spotlight ao lado da de /Applications.
rm -rf "$app"
