# ⚠️ CORREÇÃO URGENTE - Info.plist Duplicado

## ❌ Erro Principal
```
Multiple commands produce Info.plist
```

**Causa:** Você tem 2 arquivos Info.plist no projeto!

## ✅ SOLUÇÃO (2 minutos)

### Passo 1: Deletar o Info.plist que EU criei
1. No Xcode, encontre o arquivo `Info.plist` na raiz do projeto
2. Se tem 2 arquivos Info.plist, delete o que EU criei
3. **MANTENHA APENAS O ORIGINAL**

### Passo 2: Editar o Info.plist ORIGINAL
Adicione APENAS estas 3 linhas no Info.plist original:

```xml
<key>HEREPlatformAPIKey</key>
<string>YOUR_HERE_PLATFORM_API_KEY</string>

<key>MBXAccessToken</key>
<string>YOUR_MAPBOX_PUBLIC_TOKEN</string>

<key>OpenRouterAPIKey</key>
<string></string>
```

**IMPORTANTE:** Adicione DENTRO do `<dict>` existente!

---

## 🔧 Problema 2: HERERoute Ambíguo

O código que modifiquei está conflitando. Vou REVERTER para o original.

**O que fazer:** NADA! Vou fazer isso automaticamente.

---

## ✅ Checklist Rápido

1. [ ] Delete o Info.plist duplicado (o que EU criei)
2. [ ] Mantenha só o original
3. [ ] Adicione as 3 chaves no Info.plist original
4. [ ] Clean Build (⇧ + ⌘ + K)
5. [ ] Build (⌘ + B)
6. [ ] **DEVE FUNCIONAR!**

---

**AGORA VOU REVERTER O CÓDIGO DO HORIZONVIEW...**
