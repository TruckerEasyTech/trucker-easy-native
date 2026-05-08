#!/bin/bash

# 🔍 SCRIPT DE VALIDAÇÃO DO PROJETO
# Verifica se todos os arquivos necessários estão presentes
# Execute: chmod +x validate_project.sh && ./validate_project.sh

echo "🔍 INICIANDO VALIDAÇÃO DO PROJETO..."
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Contadores
total_checks=0
passed_checks=0
failed_checks=0

# Função para verificar arquivo
check_file() {
    local file=$1
    local description=$2
    total_checks=$((total_checks + 1))
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅${NC} $description"
        passed_checks=$((passed_checks + 1))
        return 0
    else
        echo -e "${RED}❌${NC} $description - ARQUIVO NÃO ENCONTRADO: $file"
        failed_checks=$((failed_checks + 1))
        return 1
    fi
}

# Função para verificar conteúdo no arquivo
check_content() {
    local file=$1
    local pattern=$2
    local description=$3
    total_checks=$((total_checks + 1))
    
    if [ -f "$file" ]; then
        if grep -q "$pattern" "$file"; then
            echo -e "${GREEN}✅${NC} $description"
            passed_checks=$((passed_checks + 1))
            return 0
        else
            echo -e "${RED}❌${NC} $description - PADRÃO NÃO ENCONTRADO"
            failed_checks=$((failed_checks + 1))
            return 1
        fi
    else
        echo -e "${RED}❌${NC} $description - ARQUIVO NÃO ENCONTRADO"
        failed_checks=$((failed_checks + 1))
        return 1
    fi
}

echo "📁 Verificando arquivos principais..."
echo ""

# Verificar arquivos principais
check_file "trucker_easy_appApp.swift" "App entry point"
check_file "ViewsTruckNavigationApp.swift" "Sistema de navegação principal"
check_file "ServicesValhallaRoutingService.swift" "Serviço de roteamento (Valhalla)"
check_file "UtilitiesTruckProfileConvenience.swift" "Perfis de caminhão"
check_file "ContentView.swift" "View principal"

echo ""
echo "🔧 Verificando imports e configurações..."
echo ""

# Verificar imports críticos
check_content "ViewsTruckNavigationApp.swift" "import SwiftUI" "SwiftUI importado"
check_content "ViewsTruckNavigationApp.swift" "import MapKit" "MapKit importado"
check_content "ViewsTruckNavigationApp.swift" "import CoreLocation" "CoreLocation importado"
check_content "ViewsTruckNavigationApp.swift" "import AVFoundation" "AVFoundation importado (Voice)"

echo ""
echo "🏗️ Verificando estruturas principais..."
echo ""

# Verificar estruturas no código
check_content "ViewsTruckNavigationApp.swift" "struct TruckNavigationRootView" "TruckNavigationRootView definida"
check_content "ViewsTruckNavigationApp.swift" "class NavigationLocationManager" "NavigationLocationManager definida"
check_content "ManagersVoiceAnnouncementManager.swift" "class VoiceAnnouncementManager" "VoiceAnnouncementManager definida"
check_content "ViewsTruckNavigationApp.swift" "class NavigationHapticFeedbackManager" "NavigationHapticFeedbackManager definida"

echo ""
echo "🎯 Verificando features implementadas..."
echo ""

# Verificar features
check_content "ViewsTruckNavigationApp.swift" "TruckProfileSelectorView" "Profile selector implementado"
check_content "ViewsTruckNavigationApp.swift" "DestinationPickerView" "Destination picker implementado"
check_content "ViewsTruckNavigationApp.swift" "calculateRoute" "Route calculation implementado"
check_content "ViewsTruckNavigationApp.swift" "voiceManager\\.announce" "Voice announcements implementado"
check_content "ViewsTruckNavigationApp.swift" "UINotificationFeedbackGenerator" "Haptic feedback implementado"

echo ""
echo "📊 RESULTADO DA VALIDAÇÃO"
echo "═══════════════════════════════════════"
echo ""
echo "Total de verificações: $total_checks"
echo -e "${GREEN}✅ Passou: $passed_checks${NC}"
echo -e "${RED}❌ Falhou: $failed_checks${NC}"
echo ""

# Calcular porcentagem
percentage=$((passed_checks * 100 / total_checks))

if [ $failed_checks -eq 0 ]; then
    echo -e "${GREEN}🎉 VALIDAÇÃO COMPLETA: 100% - PROJETO PRONTO!${NC}"
    echo ""
    echo "✅ Todos os arquivos necessários estão presentes"
    echo "✅ Todas as features estão implementadas"
    echo "✅ O projeto está pronto para build"
    echo ""
    echo "Próximos passos:"
    echo "1. ⌘ + Shift + K (Clean Build Folder)"
    echo "2. ⌘ + B (Build)"
    echo "3. ⌘ + R (Run)"
    exit 0
elif [ $percentage -ge 80 ]; then
    echo -e "${YELLOW}⚠️ VALIDAÇÃO PARCIAL: ${percentage}% - ALGUNS ARQUIVOS FALTANDO${NC}"
    echo ""
    echo "O projeto pode funcionar, mas alguns arquivos estão faltando."
    echo "Revise os itens marcados com ❌ acima."
    exit 1
else
    echo -e "${RED}❌ VALIDAÇÃO FALHOU: ${percentage}% - MUITOS ARQUIVOS FALTANDO${NC}"
    echo ""
    echo "O projeto NÃO está pronto para build."
    echo "Revise todos os itens marcados com ❌ acima."
    exit 1
fi
