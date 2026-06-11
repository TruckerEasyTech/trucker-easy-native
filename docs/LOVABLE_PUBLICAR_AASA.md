# Publicar Universal Links no truckereasy.com (Lovable)

Ficheiro no repo: [`website-public/.well-known/apple-app-site-association`](../website-public/.well-known/apple-app-site-association)

**appID:** `5K8B4JY4WT.com.thais.truckereasy.trucker-easy-app`

---

## 1. No Lovable

1. Cria a pasta **`public/.well-known/`** no projeto (se não existir).
2. Copia o conteúdo do ficheiro acima para  
   `public/.well-known/apple-app-site-association`  
   (sem extensão `.json`).
3. Faz **Publish** / deploy.

O URL final tem de responder:

`https://truckereasy.com/.well-known/apple-app-site-association`

Também recomendado em `www`:

`https://www.truckereasy.com/.well-known/apple-app-site-association`

---

## 2. Validar

```bash
curl -sI "https://truckereasy.com/.well-known/apple-app-site-association"
curl -s "https://truckereasy.com/.well-known/apple-app-site-association"
```

- HTTP **200**
- `Content-Type: application/json` (ou `application/pkcs7-mime` em alguns hosts)
- Corpo JSON com `appID` correcto

Ferramenta Apple: [App Search Validation Tool](https://search.developer.apple.com/appsearch-validation-tool)

---

## 3. Rotas suportadas (app iOS)

| URL exemplo | Efeito |
|-------------|--------|
| `https://truckereasy.com/dispatch/open?loadId=…&lat=…&lng=…&address=…` | Abre carga no app |
| `truckereasy://dispatch?loadId=…&lat=…&lng=…&address=…` | Custom scheme (já funciona) |

O app tem **Associated Domains** em `trucker easy app.entitlements`:

- `applinks:truckereasy.com`
- `applinks:www.truckereasy.com`

Reinstala o app no iPhone após mudar entitlements.

---

## 4. Gerar link no portal dispatch (Lovable)

```text
https://truckereasy.com/dispatch/open?loadId=LOAD_ID&lat=29.76&lng=-95.37&address=Houston%2C%20TX&loadNumber=TE-001
```

Botão no site: **“Open in TruckerEasy app”**
