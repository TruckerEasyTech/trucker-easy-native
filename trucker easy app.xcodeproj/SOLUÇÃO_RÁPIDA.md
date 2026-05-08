
# 🎯 SOLUÇÃO RÁPIDA - 3 Passos

## ⚡ Passo 1: Terminal (30 segundos)

Abra o Terminal e cole isto:

```bash
# Fecha Xcode
killall Xcode 2>/dev/null

# Limpa cache de build
rm -rf ~/Library/Developer/Xcode/DerivedData/trucker_easy_app*

echo "✅ Cache limpo! Agora vá para o Passo 2"
```

---

## ⚡ Passo 2: Xcode - Remover Info.plist (1 minuto)

1. Abra o Xcode
2. No painel esquerdo, clique no **ícone AZUL** (projeto)
3. Na lista que aparece, clique em **"trucker easy app"** (abaixo de TARGETS)
4. Clique na aba **"Build Phases"** (no topo)
5. Clique em **"Copy Bundle Resources"** para expandir
6. **PROCURE por "Info.plist"**
7. Se encontrar → **Selecione** → **Clique no botão "-"** (menos) à esquerda

```
┌─────────────────────────────────────┐
│ ○ ● ●  Xcode                        │
├─────────────────────────────────────┤
│ PROJECT                             │
│   trucker easy app                  │ ← Clique aqui PRIMEIRO
│                                     │
│ TARGETS                             │
│ ▼ trucker easy app                  │ ← Depois aqui
│   Examples                          │ ← DELETE se existir
│                                     │
│ [General] [Build Phases] ...        │
│            ↑                        │
│       Clique aqui                   │
│                                     │
│ ▼ Copy Bundle Resources             │
│   - Info.plist          ← REMOVA!  │
│   - Assets.xcassets                 │
│   - ...                             │
└─────────────────────────────────────┘
```

---

## ⚡ Passo 3: Build (10 segundos)

No Xcode:

1. Menu **Product** → **Clean Build Folder** (ou Shift+Cmd+K)
2. Menu **Product** → **Build** (ou Cmd+B)

---

## ✅ DEVE FUNCIONAR!

Se funcionar, você verá:
```
Build Succeeded
```

Se ainda falhar, vá para **SOLUÇÃO AVANÇADA** abaixo.

---

---

# 🔧 SOLUÇÃO AVANÇADA (se Passo 2 não resolveu)

## Passo Extra A: Deletar Targets Duplicados

1. Na mesma tela do Passo 2
2. Veja a lista de **TARGETS**
3. Se houver **"Examples"** ou **"MapboxExamples"**:
   - Clique no target "Examples"
   - Pressione **Delete** (tecla)
   - Confirme a remoção

---

## Passo Extra B: Remover SceneDelegate do Info.plist

1. No Project Navigator, encontre **Info.plist**
2. Clique para abrir
3. Procure por **"Application Scene Manifest"**
4. Se existir → **Clique com botão direito** → **Delete**

Ou edite como XML:

```bash
# Abra o Info.plist em editor de texto
cd "caminho/do/projeto"
open -a TextEdit "trucker easy app/Info.plist"
```

DELETE esta seção completa:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
    <key>UISceneConfigurations</key>
    <dict>
        <!-- DELETE TUDO DENTRO DAQUI -->
    </dict>
</dict>
```

Salve e compile novamente.

---

## Passo Extra C: Verificar @main Duplicado

Execute no Terminal:

```bash
cd "caminho/do/projeto"
grep -r "@main" . --include="*.swift" | grep -v "//" | grep -v ".build"
```

**Deve aparecer APENAS:**
```
./trucker_easy_appApp.swift:@main
```

Se aparecer mais de um:
1. Abra cada arquivo listado
2. Remova ou comente o `@main` (exceto em trucker_easy_appApp.swift)

---

## Passo Extra D: Script Automático

Se preferir automatizar, execute:

```bash
cd "caminho/do/projeto"
chmod +x fix_build.sh
./fix_build.sh
```

Depois siga as instruções na tela.

---

---

# 🆘 AINDA NÃO FUNCIONA?

Envie estas informações:

```bash
# 1. Quantos Info.plist?
find . -name "Info.plist" -type f | grep -v DerivedData | grep -v .build

# 2. Quantos @main?
grep -r "@main" . --include="*.swift" | grep -v "//" | grep -v .build

# 3. Log completo do erro
# (copie TUDO que aparece no Xcode quando dá erro)
```

---

# 📊 Checklist de Verificação

Antes de compilar, certifique-se:

- [ ] Executou limpeza do DerivedData (Passo 1)
- [ ] Removeu Info.plist de Copy Bundle Resources (Passo 2)
- [ ] Apenas UM target "trucker easy app" existe
- [ ] Deletou targets "Examples" se existiam
- [ ] Apenas trucker_easy_appApp.swift tem `@main`
- [ ] AppDelegate.swift tem `@main` comentado
- [ ] SceneDelegate está comentado ou removido
- [ ] Fez Clean Build Folder

Se TODOS estiverem marcados e ainda falhar, o problema pode estar no arquivo `.xcodeproj` corrompido.

---

# 🚀 Solução de Último Recurso

Se NADA funcionar:

```bash
# 1. Feche o Xcode
killall Xcode

# 2. Renomeie o projeto antigo
mv "trucker easy app.xcodeproj" "trucker easy app.xcodeproj.backup"

# 3. Deixe o Xcode recriar automaticamente
# (Isto pode exigir reconfiguração de alguns settings)
```

Depois:
1. Abra o Xcode
2. File → New → Project → iOS App
3. Arraste todos os arquivos `.swift` para o novo projeto
4. Configure Info.plist novamente

**ATENÇÃO:** Isso é drástico e deve ser último recurso!

---

**Data:** 30/03/2026  
**Arquivos corrigidos:** AppDelegate.swift, ExamplesRootView.swift  
**Scripts criados:** fix_build.sh  
**Guias:** FIX_BUILD_ERROR.md, CORREÇÕES_APLICADAS.md
