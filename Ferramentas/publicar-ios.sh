#!/bin/zsh
# Compila o Recap para iPhone e iPad e envia-o para o TestFlight (App Store Connect).
# Uso: RECAP_EQUIPA=<ID da equipa> Ferramentas/publicar-ios.sh            → versão da app atual
#      RECAP_EQUIPA=<ID da equipa> Ferramentas/publicar-ios.sh --versao 1.3
#
# Antes da primeira vez: a app pt.danielrodrigues.Recap.ios criada no App Store Connect, e uma das duas formas de
# entrar na conta:
#   - a conta Apple da equipa em Xcode → Definições → Contas (é o que o xcodebuild usa por defeito);
#   - ou uma chave da API do App Store Connect: RECAP_ASC_CHAVE=<.p8> RECAP_ASC_ID=<Key ID> RECAP_ASC_EMISSOR=<Issuer ID>.
set -euo pipefail
cd "${0:A:h}/.."

equipa=${RECAP_EQUIPA:?indica o ID da equipa da PILL: RECAP_EQUIPA=XXXXXXXXXX}
definicoes=("DEVELOPMENT_TEAM=$equipa" "CODE_SIGN_STYLE=Automatic")
[[ "${1:-}" == "--versao" ]] && definicoes+=("MARKETING_VERSION=${2:?indica a versão, por exemplo: --versao 1.3}")
# O TestFlight recusa um número de compilação repetido: a data e a hora nunca se repetem.
definicoes+=("CURRENT_PROJECT_VERSION=$(date +%Y%m%d%H%M)")

autenticacao=()
if [[ -n "${RECAP_ASC_CHAVE:-}" ]]; then
  autenticacao=(-authenticationKeyPath "$RECAP_ASC_CHAVE"
                -authenticationKeyID "${RECAP_ASC_ID:?falta RECAP_ASC_ID}"
                -authenticationKeyIssuerID "${RECAP_ASC_EMISSOR:?falta RECAP_ASC_EMISSOR}")
fi

arquivo=build/RecapIOS.xcarchive
rm -rf "$arquivo" build/RecapIOS-envio
registo=build/RecapIOS.log
xcodebuild -project Apontamentos.xcodeproj -scheme "Recap iOS" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$arquivo" -derivedDataPath build/DerivedData-ios \
  -allowProvisioningUpdates "${autenticacao[@]}" archive "${definicoes[@]}" > "$registo" 2>&1 || true
grep -E "error:|ARCHIVE" "$registo" || true
[[ -d "$arquivo" ]] || { echo "A compilação falhou (registo em $registo)." >&2; exit 1; }

opcoes=build/RecapIOS-opcoes.plist
cat > "$opcoes" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$equipa</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$arquivo" -exportOptionsPlist "$opcoes" -exportPath build/RecapIOS-envio \
  -allowProvisioningUpdates "${autenticacao[@]}" > "$registo" 2>&1 || true
grep -E "error:|EXPORT|Upload (succeeded|failed)" "$registo" || true
grep -q "EXPORT SUCCEEDED" "$registo" || { echo "O envio falhou (registo em $registo)." >&2; exit 1; }
echo "Enviado para o App Store Connect. A compilação aparece no TestFlight depois de processada (uns minutos)."
