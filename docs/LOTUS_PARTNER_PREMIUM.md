# Lotus.ai — modelo seguro (sem API, premium, App Store)

## Decisão de produto

- **Sem API Lotus** enquanto não houver contrato escrito e resposta deles.
- **Acesso só no site deles** — o app apenas mostra link + avisos legais.
- **Trucker Easy não faz diagnóstico**, screening clínico nem telemedicina.
- **Justificativa Pro:** benefício “acesso facilitado ao parceiro Lotus.ai” no plano premium.

Isto reduz risco com:

| Risco | Mitigação |
|-------|-----------|
| Apple Guideline 1.4.1 (physical harm / medical) | Disclaimer claro; app não é dispositivo médico |
| Apple 5.1.1 (third-party) | Utilizador abre Safari / SFSafariViewController; termos são da Lotus |
| HIPAA / PHI | App **não envia** dados de saúde nem JWT para Lotus |
| FDA (wellness vs device) | Sem alegações de screening/diagnóstico no copy do Trucker Easy |

---

## O que o app faz (implementado)

1. Card **Lotus.ai Partner (PRO)** no tab Check-up.
2. Ecrã com **disclaimer** obrigatório (“I understand”).
3. Botão **Open Lotus.ai in Safari** (recomendado para review).
4. Opcional: **View in app browser** (`SFSafariViewController`) — mesma URL pública, sem parâmetros de utilizador.

**Não fazemos:** `driver_id`, `auth=token`, WKWebView com sessão, middleware `/v1/health/screening-session`.

---

## Texto sugerido para App Store Connect

**Subscription / Pro description (excerpt):**

> TruckerEasy Pro includes a convenience link to our independent wellness partner Lotus.ai. Wellness and any telehealth services are provided solely by Lotus.ai under their own terms and privacy policy. TruckerEasy does not provide medical advice, diagnosis, or treatment.

**Privacy nutrition label:** Trucker Easy does not collect health data for Lotus; opening the partner link is optional and governed by Lotus.ai.

---

## Texto sugerido para site / pricing

> **Pro plan includes:** Partner access link to Lotus.ai wellness platform (account and fees may apply with Lotus.ai). TruckerEasy navigation, HOS tools, and document vault remain provided by Trucker Easy.

---

## Backend

`health_gateway.py` existe como rascunho mas **não está montado** em `main.py` até haver parceria e API key.

---

## Se Lotus responder no futuro

1. Contrato + DPA/BAA se aplicável.
2. Reativar gateway com sessão de curta duração (sem JWT Supabase na URL).
3. Revisão legal + nova submissão App Store se o fluxo mudar para integrado.
