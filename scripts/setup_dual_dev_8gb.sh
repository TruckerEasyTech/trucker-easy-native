#!/bin/zsh
# Cursor + Xcode no Mac 8GB — uma vez só. Não precisa fechar nenhum dos dois.
set -euo pipefail

DESKTOP="$HOME/Desktop/trucker easy app"
DEV_ROOT="$HOME/Developer/trucker-easy-app"
DD="$HOME/Developer/DerivedData"

echo "=== Setup Cursor + Xcode (8GB) ==="

mkdir -p "$HOME/Developer" "$DD"

# 1) Projeto fora do iCloud Desktop (symlink mantém o caminho antigo)
if [[ -d "$DESKTOP" && ! -L "$DESKTOP" ]]; then
  if pgrep -x fileproviderd >/dev/null && [[ "$(ps -p "$(pgrep -x fileproviderd)" -o state= 2>/dev/null)" == "T" ]]; then
    killall -CONT fileproviderd 2>/dev/null || true
    sleep 2
  fi
  echo "→ Movendo projeto para $DEV_ROOT (fora do iCloud)…"
  if mv "$DESKTOP" "$DEV_ROOT" 2>/dev/null; then
    ln -sf "$DEV_ROOT" "$DESKTOP"
    echo "   OK — symlink em Desktop/trucker easy app"
  else
    echo "   AVISO: move falhou (iCloud ocupado). Rode este script de novo após reiniciar o Mac."
    echo "   Enquanto isso: DerivedData e exclusões do Cursor já ajudam."
  fi
elif [[ -L "$DESKTOP" ]]; then
  echo "→ Symlink Desktop já existe."
elif [[ -d "$DEV_ROOT" ]]; then
  ln -sf "$DEV_ROOT" "$DESKTOP" 2>/dev/null || true
  echo "→ Projeto já em ~/Developer."
else
  echo "→ Projeto não encontrado em Desktop; nada a mover."
fi

# 2) Xcode: DerivedData fora do iCloud
defaults write com.apple.dt.Xcode IDECustomDerivedDataLocation "$DD"
defaults write com.apple.dt.Xcode IDECustomDerivedDataLocationStyle Custom
defaults write com.apple.dt.Xcode IDEBuildOperationMaxNumberOfConcurrentCompileTasks 2 2>/dev/null || true
echo "→ Xcode DerivedData → $DD"

# 3) iCloud: parar de sincronizar lixo do backend Python na nuvem
if command -v brctl >/dev/null 2>&1 && [[ -d "$DEV_ROOT/backend" ]]; then
  brctl evict "$DEV_ROOT/backend" 2>/dev/null || true
fi

# 4) fileproviderd — retomar se estiver pausado (SOS anterior)
killall -CONT fileproviderd 2>/dev/null || true

# 5) Limpar DerivedData local se voltou a aparecer
rm -rf "$DEV_ROOT"/.derivedData* 2>/dev/null || true

echo ""
echo "=== Pronto ==="
echo "• Cursor + Xcode podem ficar abertos juntos"
echo "• Builds: prefira ⌘B no Xcode (evite xcodebuild em background enquanto o agente corre)"
echo "• Feche simuladores extras e Chrome se voltar a travar"
echo "• SOS no Desktop: SOS-Mac-TruckerEasy.command"
