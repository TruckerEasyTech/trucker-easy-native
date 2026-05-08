#!/bin/bash

# 🔧 Script de Correção Automática do Erro Info.plist
# Execute: chmod +x fix_build.sh && ./fix_build.sh
#
# Este script limpa caches e fornece diagnóstico do problema
# Correções de código já foram aplicadas em:
# - AppDelegate.swift (comentado)
# - ExamplesRootView.swift (comentado)

echo "═══════════════════════════════════════════════════════"
echo "🔧 CORREÇÃO DO ERRO: Multiple commands produce Info.plist"
echo "═══════════════════════════════════════════════════════"
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 0. Status das correções
echo -e "${BOLD}📋 STATUS DAS CORREÇÕES DE CÓDIGO:${NC}"
echo -e "${GREEN}✅ AppDelegate.swift - COMENTADO${NC}"
echo -e "${GREEN}✅ ExamplesRootView.swift - COMENTADO${NC}"
echo -e "${GREEN}✅ trucker_easy_appApp.swift - ATIVO (único @main)${NC}"
echo ""
echo "Agora vamos limpar caches e fazer diagnóstico..."
echo ""
sleep 2

# 1. Fechar Xcode
echo "📱 Fechando Xcode..."
killall Xcode 2>/dev/null
sleep 2

# 2. Limpar DerivedData
echo "🧹 Limpando DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/trucker_easy_app* 2>/dev/null
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex 2>/dev/null
echo -e "${GREEN}✅ DerivedData limpo${NC}"

# 3. Limpar build artifacts locais
echo "🧹 Limpando build artifacts..."
rm -rf .build 2>/dev/null
rm -rf build 2>/dev/null
echo -e "${GREEN}✅ Build artifacts removidos${NC}"

# 4. Limpar caches do Swift Package Manager
echo "🧹 Limpando caches SPM..."
rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null
echo -e "${GREEN}✅ Caches SPM limpos${NC}"

# 5. Verificar Info.plist
echo ""
echo "🔍 Procurando arquivos Info.plist no projeto..."
PLIST_FILES=$(find . -name "Info.plist" -type f 2>/dev/null | grep -v ".build" | grep -v "DerivedData" | grep -v "Pods")

if [ -z "$PLIST_FILES" ]; then
    echo -e "${YELLOW}⚠️  Nenhum Info.plist encontrado${NC}"
else
    echo -e "${YELLOW}Arquivos encontrados:${NC}"
    echo "$PLIST_FILES"
    
    COUNT=$(echo "$PLIST_FILES" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 1 ]; then
        echo -e "${RED}⚠️  ATENÇÃO: Múltiplos Info.plist encontrados!${NC}"
        echo "Você precisa manter apenas um Info.plist no target principal."
    fi
fi

# 6. Verificar arquivos @main
echo ""
echo "🔍 Procurando arquivos com @main..."
MAIN_FILES=$(grep -r "@main" . --include="*.swift" 2>/dev/null | grep -v ".build" | grep -v "DerivedData" | grep -v "//.*@main")

if [ -z "$MAIN_FILES" ]; then
    echo -e "${YELLOW}⚠️  Nenhum @main encontrado${NC}"
else
    echo -e "${GREEN}Arquivos com @main:${NC}"
    echo "$MAIN_FILES"
    
    COUNT=$(echo "$MAIN_FILES" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 1 ]; then
        echo -e "${RED}⚠️  ATENÇÃO: Múltiplos @main encontrados!${NC}"
        echo "Deve haver apenas UM arquivo com @main (trucker_easy_appApp.swift)"
    fi
fi

# 7. Verificar SceneDelegate
echo ""
echo "🔍 Procurando SceneDelegate..."
SCENE_DELEGATE=$(grep -r "class SceneDelegate" . --include="*.swift" 2>/dev/null | grep -v ".build" | grep -v "DerivedData" | grep -v "//.*SceneDelegate")

if [ -z "$SCENE_DELEGATE" ]; then
    echo -e "${GREEN}✅ Nenhum SceneDelegate ativo encontrado${NC}"
else
    echo -e "${YELLOW}⚠️  SceneDelegate encontrado:${NC}"
    echo "$SCENE_DELEGATE"
    echo "SceneDelegate pode causar conflitos se Info.plist ainda referenciá-lo."
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "📋 PRÓXIMOS PASSOS MANUAIS NO XCODE:"
echo "═══════════════════════════════════════════════════════"
echo ""
echo -e "${BOLD}${RED}PASSO CRÍTICO - NÃO PULE ISTO:${NC}"
echo ""
echo "1. Abra o projeto no Xcode:"
echo "   open 'trucker easy app.xcodeproj'"
echo ""
echo "2. Clique no PROJETO (ícone azul) → Target 'trucker easy app'"
echo ""
echo "3. Vá para Build Phases → Copy Bundle Resources"
echo -e "   ${RED}${BOLD}REMOVA 'Info.plist' se estiver na lista${NC}"
echo "   (Selecione Info.plist e clique no botão '-')"
echo ""
echo "4. Verifique se há apenas UM target na lista"
echo "   Se houver 'Examples' ou 'MapboxExamples', DELETE-OS"
echo ""
echo "5. Product → Clean Build Folder (Shift+Cmd+K)"
echo ""
echo "6. Product → Build (Cmd+B)"
echo ""
echo "═══════════════════════════════════════════════════════"
echo ""
echo -e "${YELLOW}📖 Para mais detalhes, leia: EXECUTE_AGORA.md${NC}"
echo ""

# Perguntar se quer abrir o Xcode
echo ""
read -p "Deseja abrir o Xcode agora? (s/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[SsYy]$ ]]; then
    echo "🚀 Abrindo Xcode..."
    open "trucker easy app.xcodeproj" 2>/dev/null || open *.xcodeproj 2>/dev/null || echo -e "${RED}Erro: Projeto não encontrado${NC}"
else
    echo "✅ Script finalizado. Execute 'open trucker\ easy\ app.xcodeproj' quando estiver pronto."
fi

echo ""
echo -e "${GREEN}✅ Limpeza concluída!${NC}"
