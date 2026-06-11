# Comandos por lugar — Valhalla Oregon + Supabase + App

**CloudShell não funciona?** Usa o Mac: [`docs/DEPLOY_VALHALLA_DO_MAC.md`](../docs/DEPLOY_VALHALLA_DO_MAC.md) ou `bash run-bootstrap-from-mac.sh` nesta pasta.

Substitui:
- `valhalla.truckereasy.com` → teu domínio
- `truckereasy-valhalla` → nome da key pair AWS
- `SEU_PROJECT_REF` → ref do projeto Supabase (Settings → General)
- `SUA_CRON_SECRET` → output de `openssl rand -hex 32`

---

## 1) Mac — gerar secret do cron (opcional, antes do Supabase)

```bash
openssl rand -hex 32
```

Guarda o resultado como `SUA_CRON_SECRET`.

---

## 2) AWS CloudShell — região Oregon (us-west-2)

No console AWS: canto superior direito → região **US West (Oregon)** → abrir **CloudShell**.

### 2a) Criar key pair (só se ainda não existir)

```bash
aws ec2 create-key-pair \
  --key-name truckereasy-valhalla \
  --region us-west-2 \
  --query 'KeyMaterial' \
  --output text > ~/truckereasy-valhalla.pem

chmod 400 ~/truckereasy-valhalla.pem
cat ~/truckereasy-valhalla.pem
```

Copia o conteúdo do `.pem` para o Mac: `~/truckereasy-valhalla.pem` com `chmod 400`.

### 2b) Subir script e rodar bootstrap

Cola o ficheiro `aws-oregon-valhalla-bootstrap.sh` no CloudShell (Editor → New file) ou:

```bash
cd ~
# se clonares o repo no CloudShell:
# git clone https://github.com/TEU_USER/trucker-easy-app.git
# cd trucker-easy-app/backend/valhalla-production

export AWS_REGION=us-west-2
export VALHALLA_DOMAIN=valhalla.truckereasy.com
export KEY_NAME=truckereasy-valhalla
# opcional — só o teu IP no SSH:
# export SSH_CIDR=123.45.67.89/32

bash aws-oregon-valhalla-bootstrap.sh
```

No fim anota: **IP público** e corre:

```bash
source ~/valhalla-oregon-i-*.env
echo $VALHALLA_IP
```

---

## 3) DNS (Cloudflare, Route 53 ou outro)

Cria manualmente no painel:

| Tipo | Nome | Valor |
|------|------|--------|
| A | `valhalla` (ou FQDN `valhalla.truckereasy.com`) | IP do passo 2 (`$VALHALLA_IP`) |

Espera 5–30 min e no Mac:

```bash
dig +short valhalla.truckereasy.com
```

---

## 4) Mac — SSH para a EC2

```bash
chmod 400 ~/truckereasy-valhalla.pem
ssh -i ~/truckereasy-valhalla.pem ubuntu@COLOCA_O_IP_AQUI
```

---

## 5) Dentro da EC2 (SSH) — Valhalla + HTTPS

```bash
sudo apt-get update -y
sudo apt-get install -y git

# Opção A — clone do teu repositório:
git clone https://github.com/TEU_USER/TEU_REPO.git /tmp/trucker-easy
sudo bash /tmp/trucker-easy/backend/valhalla-production/deploy.sh valhalla.truckereasy.com

# Opção B — só o script (se fizeres scp do Mac antes):
# No Mac: scp -i ~/truckereasy-valhalla.pem backend/valhalla-production/deploy.sh ubuntu@IP:/tmp/
# Na EC2: sudo bash /tmp/deploy.sh valhalla.truckereasy.com
```

Acompanhar logs (1–3 h na primeira vez):

```bash
cd /opt/valhalla && sudo docker compose logs -f
```

Teste na EC2:

```bash
curl -s http://localhost:8002/status
curl -s https://valhalla.truckereasy.com/status
```

---

## 6) Mac — `TruckerEasy.secrets.xcconfig`

Edita `Config/TruckerEasy.secrets.xcconfig`:

```
VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
VALHALLA_SERVER_URLS = https:||valhalla.truckereasy.com,http:||192.168.0.105:8002
```

(Remove LAN do primeiro se não precisares em dev.)

Rebuild no Xcode: **Product → Clean Build Folder**, depois Run.

---

## 7) Supabase — SQL Editor (config por empresa)

Dashboard → **SQL** → New query:

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

(Se a tua tabela tiver `company_id`, adiciona a coluna no `INSERT` e no `ON CONFLICT`.)

---

## 8) Mac — Supabase CLI (secrets + deploy health-check)

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app"

supabase login
supabase link --project-ref SEU_PROJECT_REF

supabase secrets set CRON_SECRET="SUA_CRON_SECRET" --project-ref SEU_PROJECT_REF

supabase functions deploy health-check --project-ref SEU_PROJECT_REF
```

Teste manual (com JWT de utilizador logado no dashboard — não é este comando):

```bash
curl -s -X POST "https://SEU_PROJECT_REF.supabase.co/functions/v1/health-check" \
  -H "Authorization: Bearer SUA_ANON_OU_USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"source":"curl-test","environment":"production"}'
```

Teste **cron / system** (no Mac ou CloudShell):

```bash
curl -s -X POST "https://SEU_PROJECT_REF.supabase.co/functions/v1/health-check" \
  -H "Content-Type: application/json" \
  -H "x-cron-secret: SUA_CRON_SECRET" \
  -d '{"mode":"system","source":"pg-cron","environment":"production"}'
```

---

## 9) Supabase — SQL Editor (cron com pg_cron + pg_net)

Ativa extensões (se ainda não):

```sql
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
```

Agenda a cada 15 min (ajusta URL e secret):

```sql
select cron.schedule(
  'health-check-system',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://SEU_PROJECT_REF.supabase.co/functions/v1/health-check',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', 'SUA_CRON_SECRET'
    ),
    body := '{"mode":"system","source":"pg-cron","environment":"production"}'::jsonb
  ) as request_id;
  $$
);
```

Ver jobs:

```sql
select * from cron.job;
```

---

## 10) Lovable (browser — sem comando terminal)

No projeto Lovable, pede ou faz manualmente:

1. Navbar: link **Operações** → `/ops` (visível só logado).
2. Confirma rotas: `/ops`, `/ops/alertas`, `/ops/documentacao`, `/ops/api-teste`, `/ops/roteamento`.
3. Página API teste: botão chama `supabase.functions.invoke('health-check', { body: { source: 'api-test-page', environment: 'production' } })`.

---

## 11) Mac — teste final no iPhone

```bash
# Do Mac, confirma Valhalla:
curl -s https://valhalla.truckereasy.com/status | head

# Xcode: Run no dispositivo com 4G (Wi‑Fi do Mac desligado no telefone)
# Horizon → calcular rota → Diagnostics deve mostrar Valhalla
```

---

## 12) Teardown (apagar EC2 Oregon — só se quiseres desligar)

No CloudShell, depois de `source` do ficheiro `.env` gerado no bootstrap:

```bash
source ~/valhalla-oregon-i-XXXXXXXX.env
bash aws-oregon-teardown.sh
```

---

## Ordem resumida

1. Mac → `openssl` (secret)  
2. CloudShell → `aws-oregon-valhalla-bootstrap.sh`  
3. DNS → registo A  
4. Mac → `ssh` → EC2 → `deploy.sh`  
5. Mac → `secrets.xcconfig` + Xcode  
6. Supabase → SQL `truck_routing_config`  
7. Mac → `supabase secrets` + `functions deploy`  
8. Supabase → SQL `cron.schedule`  
9. Lovable → navbar `/ops`  
10. iPhone → teste rota  
