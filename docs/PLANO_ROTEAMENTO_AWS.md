# Plano de roteamento — AWS vs. o que já tens no repo

Este documento alinha o plano sugerido pela AWS com o código e scripts **já existentes** no Trucker Easy. Não precisas de reimplementar Fases 2–4 do zero.

---

## Mapa rápido

| Fase AWS | O que pedem | Estado no projeto |
|----------|-------------|-------------------|
| **1** Valhalla EC2 Oregon + HTTPS | EC2, Docker Valhalla, domínio, `VALHALLA_SERVER_URL` | Scripts prontos: `backend/valhalla-production/` + guia `RODAR_AGORA.md` |
| **2** Modo truck-safe | `truckSafeOnlyMode`, bloquear OSRM/MapKit | **Já no código** — toggle em **My Horizon → Truck Profile** |
| **3** Amazon Location (HERE) | SDK AWS, `CalculateRoute` truck | **Opcional** — contradiz stack própria (Valhalla/OSM); só se quiseres API gerida AWS |
| **4** CloudFront multi-região | CDN à frente do ALB | Depois da Fase 1 estável; não é obrigatório no MVP |

---

## Fase 1 — Fazer agora (produção Oregon)

### O que NÃO copiar literalmente do tutorial AWS genérico

- **t3.medium** — pouco RAM para tiles NA; o repo usa **c5.xlarge + 160 GB** (`aws-oregon-valhalla-bootstrap.sh`).
- **Só porta 8002** — em produção usa **`deploy.sh`**, que configura **HTTPS** (Caddy/Let's Encrypt), não HTTP exposto na internet.
- **`docker run` único** — o `deploy.sh` faz compose, tiles Geofabrik e healthcheck.

### Comandos certos (ordem)

1. **CloudShell** (região `us-west-2`):

```bash
export AWS_REGION=us-west-2
export VALHALLA_DOMAIN=valhalla.truckereasy.com
export KEY_NAME=truckereasy-valhalla
bash backend/valhalla-production/aws-oregon-valhalla-bootstrap.sh
source ~/valhalla-oregon-i-*.env && echo $VALHALLA_IP
```

2. **DNS** — registo **A** `valhalla.truckereasy.com` → IP do passo 1.

3. **SSH na EC2** → instalar Valhalla:

```bash
ssh -i ~/truckereasy-valhalla.pem ubuntu@SEU_IP
sudo bash deploy.sh valhalla.truckereasy.com
```

4. **Mac** — `Config/TruckerEasy.secrets.xcconfig`:

```
VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
```

(em xcconfig usa `||` em vez de `//`)

5. **Teste**:

```bash
curl -s https://valhalla.truckereasy.com/status
```

6. **Supabase** (ops dashboard) — ver `RODAR_AGORA.md` secções 7–9 (`truck_routing_config`, cron `health-check`).

Guia completo passo a passo: [`backend/valhalla-production/RODAR_AGORA.md`](../backend/valhalla-production/RODAR_AGORA.md).

---

## Fase 2 — Modo truck-safe (já implementado)

### Comportamento

| `truckSafeOnlyMode` | Valhalla OK | Valhalla offline |
|---------------------|-------------|------------------|
| **OFF** (padrão) | Rota Valhalla | Fallback OSRM/MapKit + aviso *"Rota via OSRM…"* |
| **ON** | Rota Valhalla | **Erro** — não aplica rota de carro |

### Onde ativar no app

**My Horizon** → ícone/definições do **perfil do camião** (Truck Profile) → toggle **"Apenas rotas seguras para caminhão"**.

### Código relevante

- `RoutingService.calculateTruckRoute` — lança erro se `truckSafeOnlyMode` e Valhalla falhou.
- `ViewsHorizonView.commitSelectedRoute` — não aplica OSRM quando o modo está ON.
- **Diagnostics** (canto inferior) — linha **Truck-safe** ON/OFF + ping Valhalla.

---

## Fase 3 — Amazon Location Service (opcional)

Só faz sentido se quiseres **pagar API gerida** com dados HERE/TomTom por baixo. O produto Trucker Easy foi desenhado para **Valhalla próprio** (sem revenda de GPS comercial como motor principal).

Se avançares:

- Cria `Route Calculator` em `us-west-2`.
- Novo provider em `RoutingService` **antes** de OSRM, **depois** de Valhalla.
- Mantém `truckSafeOnlyMode` a exigir providers `isTruckAware`.

Não está no repo hoje — é projeto separado (~1 semana).

---

## Fase 4 — CloudFront (depois)

Útil quando tiveres tráfego global e quiseres cache/edge à frente do ALB. URL final pode ser `https://api.truckereasy.com/valhalla/...` com origin no Oregon.

Monitorização: CloudWatch no ALB + alarmes latência/5xx (como AWS sugeriu).

---

## Dev local vs produção

| Ambiente | `VALHALLA_SERVER_URL` | O que vês no iPhone |
|----------|------------------------|---------------------|
| Dev LAN | `http:||192.168.x.x:8002` | Valhalla se Mac + Wi‑Fi iguais |
| Dev sem Mac | (Valhalla down) | OSRM + aviso (se truck-safe OFF) |
| Produção | `https:||valhalla.truckereasy.com` | Valhalla truck costing em 4G/LTE |

---

## Checklist “acabou de funcionar”

- [ ] `curl https://valhalla.teudominio.com/status` → JSON OK  
- [ ] `secrets.xcconfig` com HTTPS (não só LAN)  
- [ ] iPhone em **4G** (Wi‑Fi off) calcula rota **sem** aviso OSRM  
- [ ] Diagnostics: **Valhalla** verde  
- [ ] Com truck-safe **ON** e Valhalla down → mensagem de erro (não rota de carro)  
- [ ] Supabase `truck_routing_config` + cron `health-check` (ops)

---

## Resumo

O plano AWS está **certo na direção**. No teu repo:

1. **Executa Fase 1** com os scripts Oregon já escritos — não reinventes com `t3.medium` + Docker manual.  
2. **Fase 2** já está no app — ativa o toggle quando Valhalla HTTPS estiver no ar.  
3. **Fases 3–4** são evolução opcional, não bloqueiam deixar de ver "Rota via OSRM".
