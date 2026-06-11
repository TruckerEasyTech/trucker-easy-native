# Lotus.ai Cortex — viabilidade técnica (legado)

> **Produção atual:** usar [`LOTUS_PARTNER_PREMIUM.md`](LOTUS_PARTNER_PREMIUM.md) — link parceiro sem API, adequado à App Store.

# Lotus.ai Cortex — viabilidade e integração Trucker Easy (arquitetura original)

## Porque isto valoriza o app

| Diferencial | Concorrentes típicos | Trucker Easy + Cortex |
|-------------|----------------------|------------------------|
| Wellness no fluxo de trabalho | App genérico ou portal separado | Screening no **My Check-up**, mesmo ecrã que HOS/medicamentos |
| Identidade do motorista | Login duplo | `driver_id` Supabase + sessão servidor (sem API key no iOS) |
| Frota / dispatch | Pouco integrado | Mesmo `driver_id` que cargas e telemetria |
| Telehealth | Link externo | WKWebView nativo + gateway Python para Fase 2 (scores na API) |

Encaixa na promessa do site: **wellness + documentos + GPS** num só app para motoristas OTR.

---

## O que foi implementado (repo)

### Fase 1 — iOS (teste de campo)

| Ficheiro | Função |
|----------|--------|
| `ViewsCortexWellnessView.swift` | `WKWebView` + loading/erro |
| `ServicesLotusCortexService.swift` | URL via middleware ou fallback web |
| `ViewsCheckupView.swift` | Card **Lotus Cortex** no tab Check-up |
| `Info.plist` | ATS `lotus.ai` / `api.lotus.ai` (TLS) |

**Fluxo:** Check-up → Lotus Cortex → pede `POST {quantum}/v1/health/screening-session?driver_id=UUID` → abre `embed_url` no WebView.

### Fase 2 — Backend (pronto para credenciais Lotus)

| Ficheiro | Função |
|----------|--------|
| `backend/quantum-routing/app/health_gateway.py` | Proxy `POST /v1/health/screening-session` |
| `backend/quantum-routing/.env.example` | `LOTUS_CORTEX_*` |
| `requirements.txt` | `httpx` |

**Segurança:** `LOTUS_CORTEX_API_KEY` só no `.env` do servidor — **nunca** no xcconfig iOS.

---

## Configuração

### Backend (`backend/quantum-routing/.env`)

```bash
LOTUS_CORTEX_API_KEY=your_production_key
LOTUS_CORTEX_API_BASE_URL=https://api.lotus.ai/v1/cortex
LOTUS_CORTEX_WEB_BASE_URL=https://lotus.ai/cortex/auth
ROUTE_OPTIMIZATION_API_KEY=mesmo_valor_do_ios
```

```bash
cd backend/quantum-routing
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8003
```

Teste:

```bash
curl -s -X POST "http://localhost:8003/v1/health/screening-session?driver_id=UUID" \
  -H "X-API-Key: SUA_KEY"
```

### iOS (`Config/TruckerEasy.secrets.xcconfig`)

```xcconfig
LOTUS_CORTEX_WEB_BASE_URL = https:||lotus.ai/cortex/auth
ROUTE_OPTIMIZATION_API_BASE_URL = http:||SEU_EC2:8003
```

Motorista: **Perfil → Fleet & Dispatch** (login) antes de abrir Cortex.

---

## Viabilidade e riscos

| Item | Avaliação |
|------|-----------|
| Técnica Fase 1 | **Alta** — WebView + driver_id já implementado |
| Técnica Fase 2 | **Média-alta** — depende contrato API Lotus (`/sessions`, webhooks) |
| App Store | WebView de parceiro de saúde: política de privacidade + HIPAA/BAA se dados clínicos |
| Segurança | **Não** passar JWT Supabase em query string em produção; usar só `embed_url` do middleware |
| Operação | Lotus + DoctorsHero = duas linhas telehealth; posicionar Cortex como screening AI, DoctorsHero como consulta |

---

## Próximos passos (produto)

1. Lotus fornecer URL embed final + API key de staging.
2. Teste de campo: 5–10 motoristas no Check-up → métricas de conclusão de screening.
3. Webhook Lotus → Supabase `wellness_logs` ou tabela `cortex_screenings` (Fase 2).
4. Banner no Horizon se score fadiga/apneia = alto (integração com HOS).

---

## Diferenciação vs spec original

Melhorias face ao snippet CTO:

- Token **não** hardcoded no bundle; sessão via middleware.
- Reutiliza `DriverAuthManager` / Fleet login existente.
- ATS explícito para domínios Lotus.
- Card no **Check-up** (não sidebar separada) — menos fricção no tab já usado para wellness.
