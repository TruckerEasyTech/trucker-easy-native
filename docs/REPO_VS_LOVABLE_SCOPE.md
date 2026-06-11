# O que é deste repo vs Lovable

Mensagem típica do Lovable: *“Fora do scope deste repo (não posso fazer daqui)…”* — isto mapeia **quem faz o quê**.

| Item | Quem faz | Onde |
|------|----------|------|
| `VALHALLA_SERVER_URL` / HTTPS produção | **Tu + EC2** | `Config/TruckerEasy.secrets.xcconfig` + deploy `backend/valhalla-production/` |
| Auth motorista no app | **Este repo (iOS)** | Perfil → Fleet & Dispatch (`ServicesDriverAuthManager.swift`) |
| Anon JWT `eyJ…` no app | **Este repo** | `SUPABASE_ANON_KEY` no `TruckerEasy.secrets.xcconfig` (já ligado ao `usowafvqawbunyhmfscx`) |
| Botão App Store / TestFlight real | **Este repo** | `APP_STORE_URL` / `TESTFLIGHT_URL` no xcconfig → botão em `SubscriptionView` |
| Preços site ↔ IAP | **Alinhar manualmente** | Site Lovable + App Store Connect; ver `docs/PRECOS_SITE_E_IAP.md` |
| Universal Links (AASA) | **Lovable publica ficheiro** | Copiar `website-public/.well-known/apple-app-site-association` |
| Associated Domains no app | **Este repo** | `trucker easy app.entitlements` (TEAMID `5K8B4JY4WT`) |
| Dispatch web → Supabase | **Lovable** | `/auth`, `/dispatch` + checklist `docs/LOVABLE_DISPATCH_VALIDACAO.md` |
| Ops dashboard `/ops` | **Lovable** (copiar `ops-dashboard/`) | Separado do marketing |

---

## TEAM ID e bundle (Apple)

| Campo | Valor |
|-------|--------|
| **DEVELOPMENT_TEAM** | `5K8B4JY4WT` |
| **Bundle ID** | `com.thais.truckereasy.trucker-easy-app` |
| **appID no AASA** | `5K8B4JY4WT.com.thais.truckereasy.trucker-easy-app` |

Se mudares o Team ID no Xcode, **atualiza** `website-public/.well-known/apple-app-site-association`.

---

## Passos rápidos (tu)

1. **Valhalla:** quando `curl https://valhalla.truckereasy.com/status` → 200, o `secrets.xcconfig` já tenta HTTPS primeiro via `VALHALLA_SERVER_URLS`.
2. **TestFlight:** quando tiveres link → `TESTFLIGHT_URL = https:||testflight.apple.com/join/XXXX` no xcconfig.
3. **App Store:** após aprovação → `APP_STORE_URL = https:||apps.apple.com/app/idXXXX`.
4. **AASA no site:** ver `docs/LOVABLE_PUBLICAR_AASA.md`.
5. **Lovable:** só variáveis `VITE_SUPABASE_*` + publicar AASA + preços conforme `PRECOS_SITE_E_IAP.md`.
