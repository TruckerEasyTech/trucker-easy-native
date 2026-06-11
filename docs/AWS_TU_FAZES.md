# AWS — só a tua parte (checklist)

O código do app, scripts Oregon e documentação **já estão no repo**.  
Tu só precisas de executar estes passos na **conta AWS** e no **Terminal do Mac**.

Substitui `valhalla.truckereasy.com` pelo teu subdomínio real.

---

## Parte 0 — Pré-requisitos (15 min)

- [ ] Conta AWS ativa  
- [ ] Domínio (ex. `truckereasy.com`) onde podes criar registo **A**  
- [ ] Mac com Terminal  

---

## Parte 1 — AWS CLI no Mac (uma vez)

```bash
brew install awscli
aws configure
```

| Campo | Valor |
|-------|--------|
| Region | `us-west-2` |
| Output | `json` |

Chaves: **IAM → Users → Security credentials → Create access key (CLI)**.

Verificar:

```bash
aws sts get-caller-identity
```

Tem de mostrar JSON com `Account` e `Arn`. Se falhar, o utilizador IAM precisa permissão **EC2** (ex. `AmazonEC2FullAccess`).

Preflight no repo:

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app/backend/valhalla-production"
bash verificar-aws-cli.sh
```

---

## Parte 2 — Key pair SSH (uma vez)

```bash
aws ec2 create-key-pair \
  --key-name truckereasy-valhalla \
  --region us-west-2 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/truckereasy-valhalla.pem

chmod 400 ~/.ssh/truckereasy-valhalla.pem
```

Se der erro “already exists”, usa a chave que já tens.

---

## Parte 3 — Criar EC2 Oregon (5–10 min)

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app/backend/valhalla-production"

export AWS_REGION=us-west-2
export VALHALLA_DOMAIN=valhalla.truckereasy.com
export KEY_NAME=truckereasy-valhalla

bash run-bootstrap-from-mac.sh
```

**Anota o IP público** que aparece no fim (ex. `54.x.x.x`).

```bash
source ~/valhalla-oregon-i-*.env
echo $VALHALLA_IP
```

**Custo:** ~$50–70/mês (c5.xlarge + disco) enquanto a instância estiver ligada.

---

## Parte 4 — DNS (5–30 min de propagação)

No Cloudflare / Route 53 / registrador:

| Tipo | Nome | Valor |
|------|------|--------|
| **A** | `valhalla` | IP do Parte 3 (`$VALHALLA_IP`) |

Teste no Mac:

```bash
dig +short valhalla.truckereasy.com
```

Tem de devolver o mesmo IP.

---

## Parte 5 — Instalar Valhalla na EC2 (1–3 h na 1ª vez)

### 5a) Copiar script do Mac para a EC2

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app/backend/valhalla-production"
export VALHALLA_IP=COLOCA_O_IP_AQUI

bash copiar-deploy-para-ec2.sh
```

### 5b) SSH e instalar

```bash
ssh -i ~/.ssh/truckereasy-valhalla.pem ubuntu@$VALHALLA_IP
```

Dentro da EC2:

```bash
sudo bash /tmp/deploy.sh valhalla.truckereasy.com
```

Não feches o SSH até terminar. Acompanhar:

```bash
cd /opt/valhalla && sudo docker compose logs -f
```

### 5c) Testar

Na EC2 ou no Mac:

```bash
curl -s https://valhalla.truckereasy.com/status
```

Resposta JSON = OK.

---

## Parte 6 — App iPhone (Mac / Xcode)

Edita `Config/TruckerEasy.secrets.xcconfig`:

```
VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
```

Xcode: **Product → Clean Build Folder** → Run no iPhone.

Teste com **Wi‑Fi desligado no telefone** (só 4G): calcular rota → Diagnostics → **Valhalla** verde.

Opcional (frota): My Horizon → Truck Profile → **Apenas rotas seguras para caminhão** ON.

---

## Parte 7 — Supabase (opcional, ops)

SQL no dashboard (ajusta domínio):

```sql
insert into truck_routing_config (config_key, config_value, environment, description)
values (
  'valhalla_primary_url',
  '{"url": "https://valhalla.truckereasy.com"}'::jsonb,
  'production',
  'Valhalla truck costing — Oregon'
)
on conflict (config_key, environment) do update
  set config_value = excluded.config_value,
      updated_at = now();
```

---

## Erro: `not eligible for Free Tier` no RunInstances

A conta só deixa lançar tipos **Free Tier** (ex. `t2.micro`). O Valhalla com mapa da América do Norte precisa de **instância paga** (usa os teus **créditos AWS**, não é “sem custo”, mas os $99 cobrem meses).

**Solução A — Permitir instâncias pagas (recomendado)**

1. Console AWS → **EC2** → **Dashboard** (ou **Account attributes**).
2. Se aparecer aviso de “Free Tier only” / limitação de conta nova, completa **verificação de pagamento** (cartão) — os créditos promocionais continuam a aplicar-se.
3. Tenta lançar manualmente uma **t3.large** na região **us-west-2**. Se o Console deixar, o CLI também deixa.

**Solução B — Tentar tipo menor (pago, se a conta permitir)**

```bash
export INSTANCE_TYPE=t3.large
export VOLUME_GB=120
bash run-bootstrap-from-mac.sh
```

(`t3.large` ~8 GB RAM — mínimo para teste; o default do repo é `c5.xlarge`.)

**Solução C — Se a conta recusar QUALQUER tipo pago**

Usa **DigitalOcean** com o mesmo `deploy.sh` (ver `backend/valhalla-production/README.md` Opção 1) — não passa pelo filtro Free Tier da AWS.

**Não uses** `t2.micro` / `t3.micro` para Valhalla NA — a build de tiles falha por falta de RAM.

---

## Se algo falhar

| Erro | O que fazer |
|------|-------------|
| `aws: command not found` | `brew install awscli` |
| `not eligible for Free Tier` | Secção acima — permitir EC2 pago ou DigitalOcean |
| `Unable to locate credentials` | `aws configure` |
| `UnauthorizedOperation` | IAM com permissão EC2 |
| SSH timeout | Security group porta 22; IP correto |
| HTTPS não abre | DNS propagado? `deploy.sh` terminou? |
| App ainda “via OSRM” | `secrets.xcconfig` com HTTPS; rebuild; Valhalla `/status` OK |

---

## Apagar tudo (economizar)

```bash
source ~/valhalla-oregon-i-*.env
cd "/Users/thaiskeller/Desktop/trucker easy app/backend/valhalla-production"
bash aws-oregon-teardown.sh
```

---

## O que NÃO precisas fazer na AWS

- CloudShell  
- Amazon Location + HERE (`truck-routing.yaml` é opcional)  
- ALB manual (o `deploy.sh` usa Caddy + Let's Encrypt na EC2)  
- Reescrever código Swift do app  
