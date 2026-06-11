#!/bin/zsh
# Corrige pedidos infinitos de senha GitHub no Xcode (credencial errada no Keychain).
set -euo pipefail

echo "=== Fix GitHub no Xcode ==="

# Remove credencial antiga TruckerEasyTech (senha errada/expirada)
security delete-internet-password -s github.com -a TruckerEasyTech 2>/dev/null && \
  echo "✓ Credencial antiga removida do Keychain" || \
  echo "• Nenhuma credencial TruckerEasyTech no Keychain"

defaults write com.apple.dt.Xcode IDESourceControlFetchBackgroundUpdates -bool NO
defaults write com.apple.dt.Xcode IDESourceControlEnableGitHubSSHKeys -bool NO

echo ""
echo "Mapbox (SwiftPM) é PÚBLICO — não precisa senha."
echo ""
echo "No Xcode AGORA:"
echo "  1. Clique CANCEL em qualquer janela de senha GitHub"
echo "  2. Xcode → Settings → Accounts → remova contas GitHub que não usa"
echo "  3. File → Packages → Reset Package Caches"
echo "  4. File → Packages → Resolve Package Versions"
echo ""
echo "Só precisa login GitHub quando for dar PUSH no repo TruckerEasyTech."
echo "Aí: Settings → Accounts → + → GitHub → Personal Access Token (não senha normal)."
