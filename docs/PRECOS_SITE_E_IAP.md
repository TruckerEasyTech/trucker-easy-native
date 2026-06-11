# Preços — site truckereasy.com ↔ App Store (IAP)

## Planos de produto

| Plano | Site / App | App Store Connect |
|-------|------------|-------------------|
| Free | Rota de carro via MapKit, mapa básico | Sem IAP |
| Standard | Rota de caminhão Valhalla + evitar pedágios + DOT/HOS | `com.truckereasy.standard.monthly`, `com.truckereasy.standard.annual` |
| Premium | Route Easy / Fuel Smart + IA + wellness/logbook/scale monitoring | `com.truckereasy.premium.monthly`, `com.truckereasy.premium.annual` |

Os IDs antigos `com.truckereasy.monthly` e `com.truckereasy.annual` continuam aceitos pelo app como Premium durante a transição.

Fonte única de marketing no **app** (fallback quando StoreKit ainda não carregou):

`AppDistributionConfig.MarketingPrice` em `UtilitiesAppDistributionConfig.swift`

| Plano | Site (Lovable) | App (marketing) | App Store Connect |
|-------|----------------|-----------------|-------------------|
| Mensal | **$19.99**/mês | $19.99 | `com.truckereasy.monthly` |
| Anual | **$169.99**/ano | $169.99 | `com.truckereasy.annual` |
| Equivalente mensal anual | $14.16/mês | $14.16 | (calculado StoreKit ou fallback) |
| Poupança anual vs 12× mensal | Save **$69.89** | $69.89 | Confirmar no ASC |
| Trial | **3 dias** grátis | 3 dias | Intro offer no ASC |

---

## Corrigir no Lovable

Se o site ainda mostrar **$169.90** ou poupança **$69.98**, alterar para **$169.99** / **$69.89** para bater certo com a home actual e o app.

---

## No App Store Connect

1. Subscriptions → criar grupo TruckerEasy Pro  
2. Produtos: `com.truckereasy.monthly`, `com.truckereasy.annual`  
3. Preços USD alinhados à tabela  
4. Introductory offer: 3 days free trial (se aplicável na tua região)

O ecrã **Manage Plan** no app usa preços **reais** do StoreKit quando disponíveis; strings fixas no Road Talk / fallback usam a tabela acima.

---

## Botão “Download” no site

Quando tiveres link:

- **TestFlight:** `TESTFLIGHT_URL` no `TruckerEasy.secrets.xcconfig`  
- **App Store:** `APP_STORE_URL` no mesmo ficheiro  

No site Lovable, o botão “Notify Me” pode passar a:

- `href` = mesmo URL do TestFlight/App Store, ou  
- manter waitlist até haver build pública

O app mostra botão **Download on the App Store** / **Join TestFlight** em Subscription quando o URL estiver preenchido no xcconfig.
