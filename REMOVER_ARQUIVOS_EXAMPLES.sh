#!/bin/bash

#
# Script para REMOVER FISICAMENTE arquivos de Examples
# que estão causando conflito de build
#
# ATENÇÃO: Este script DELETE arquivos permanentemente!
# Execute apenas se tiver certeza.
#
# Uso: chmod +x REMOVER_ARQUIVOS_EXAMPLES.sh && ./REMOVER_ARQUIVOS_EXAMPLES.sh
#

echo "═══════════════════════════════════════════════════════"
echo "⚠️  REMOVER ARQUIVOS DE EXAMPLES DO MAPBOXMAPS"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Este script vai DELETAR fisicamente os arquivos:"
echo "  - AppDelegate.swift"
echo "  - ExamplesRootView.swift"
echo "  - StyleOverridesModel.swift"
echo "  - SearchView.swift"
echo ""
echo "ATENÇÃO: Esta ação é IRREVERSÍVEL!"
echo ""

read -p "Tem certeza que deseja continuar? (digite 'SIM' para confirmar): " confirmacao

if [ "$confirmacao" != "SIM" ]; then
    echo "❌ Operação cancelada."
    exit 1
fi

echo ""
echo "🗑️  Removendo arquivos..."

# Lista de arquivos para remover
ARQUIVOS=(
    "AppDelegate.swift"
    "ExamplesRootView.swift"
    "StyleOverridesModel.swift"
    "SearchView.swift"
    "Example.swift"
    "ExampleTableViewController.swift"
    "SwiftUIRoot.swift"
    "SwiftUIWrapper.swift"
    "UseCasesRoot.swift"
    "ExamplesSettingsView.swift"
)

REMOVIDOS=0
NAO_ENCONTRADOS=0

for arquivo in "${ARQUIVOS[@]}"; do
    # Procura o arquivo recursivamente
    encontrados=$(find . -name "$arquivo" -type f 2>/dev/null | grep -v ".build" | grep -v "DerivedData")
    
    if [ -n "$encontrados" ]; then
        while IFS= read -r caminho; do
            echo "  🗑️  Removendo: $caminho"
            rm -f "$caminho"
            REMOVIDOS=$((REMOVIDOS + 1))
        done <<< "$encontrados"
    else
        echo "  ⚠️  Não encontrado: $arquivo"
        NAO_ENCONTRADOS=$((NAO_ENCONTRADOS + 1))
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ Arquivos removidos com sucesso!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Total removidos: $REMOVIDOS"
echo "Não encontrados: $NAO_ENCONTRADOS"
echo ""
echo "Agora execute:"
echo ""
echo "1. Feche o Xcode:"
echo "   killall Xcode"
echo ""
echo "2. Limpe DerivedData:"
echo "   rm -rf ~/Library/Developer/Xcode/DerivedData/trucker_easy_app*"
echo ""
echo "3. Reabra o Xcode e compile!"
echo ""
