# Valhalla no AWS — fazer tudo pelo Mac (sem CloudShell)

O **CloudShell não é obrigatório**. O script `aws-oregon-valhalla-bootstrap.sh` corre igual no **Terminal do Mac**, desde que tenhas AWS CLI configurado.

---

## O que já tens no app (não precisas reescrever)

O plano “híbrido” da AWS **já está no código** (`RoutingService.swift`):

1. **Valhalla** (camião) — se o teu servidor responder  
2. **OSRM público** — fallback com aviso  
3. **MapKit** (Apple) — último recurso  
4. **Cache** — rota guardada  

Isto é compatível com **App Store**: com `truckSafeOnlyMode` **OFF** (padrão), a Apple consegue calcular uma rota mesmo sem o teu servidor.

---

## Parte A — Criar a EC2 pelo Mac (substitui CloudShell)

### A.1 Instalar AWS CLI (uma vez)

```bash
brew install awscli
aws --version
aws configure
```

Preenche: Access Key, Secret Key, região **`us-west-2`**, formato `json`.

Teste:

```bash
aws sts get-caller-identity
```

Se falhar: IAM user precisa de `AmazonEC2FullAccess` (ou política equivalente para criar EC2, SG, Elastic IP).

### A.2 Key pair em Oregon (uma vez)

```bash
aws ec2 create-key-pair \
  --key-name truckereasy-valhalla \
  --region us-west-2 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/truckereasy-valhalla.pem

chmod 400 ~/.ssh/truckereasy-valhalla.pem
```

Se disser que já existe, usa a chave que tens.

### A.3 Correr o bootstrap no Mac

```bash
cd "/Users/thaiskeller/Desktop/trucker easy app/backend/valhalla-production"

export AWS_REGION=us-west-2
export VALHALLA_DOMAIN=valhalla.truckereasy.com
export KEY_NAME=truckereasy-valhalla
# Recomendado: só o teu IP no SSH
# export SSH_CIDR=TEU_IP_PUBLICO/32

bash aws-oregon-valhalla-bootstrap.sh
```

No fim aparece **IP público** e ficheiro `~/valhalla-oregon-i-xxxxx.env`.

```bash
source ~/valhalla-oregon-i-*.env
echo $VALHALLA_IP
```

### A.4 DNS

No Cloudflare / Route 53 / onde tiveres o domínio:

| Tipo | Nome | Valor |
|------|------|--------|
| A | `valhalla` | IP do passo A.3 |

---

## Parte B — Instalar Valhalla na EC2 (SSH do Mac)

```bash
ssh -i ~/.ssh/truckereasy-valhalla.pem ubuntu@$VALHALLA_IP
```

Na EC2:

```bash
sudo apt-get update -y
sudo apt-get install -y git

# Opção 1: copiar só o deploy.sh do Mac
# (no Mac, noutro terminal:)
# scp -i ~/.ssh/truckereasy-valhalla.pem \
#   backend/valhalla-production/deploy.sh \
#   ubuntu@$VALHALLA_IP:/tmp/deploy.sh

sudo bash /tmp/deploy.sh valhalla.truckereasy.com
```

**Primeira vez: 1–3 horas** (download OSM + build tiles). Não feches o SSH.

Teste na EC2:

```bash
curl -s http://localhost:8002/status
curl -s https://valhalla.truckereasy.com/status
```

---

## Parte C — App no Mac / iPhone

Edita `Config/TruckerEasy.secrets.xcconfig`:

```
VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
```

(em `.xcconfig` usa `||` em vez de `//`)

Xcode: **Product → Clean Build Folder**, depois Run no iPhone.

**Teste em 4G** (Wi‑Fi off): Horizon → rota → Diagnostics → **Valhalla** verde.

---

## Se o CloudShell “não funciona”

| Sintoma | Solução |
|---------|---------|
| Região errada | Console AWS → canto superior → **US West (Oregon)** |
| `Unable to locate credentials` no Mac | `aws configure` de novo |
| `UnauthorizedOperation` | IAM precisa permissão EC2 |
| Sessão CloudShell expira | Usa **Terminal do Mac** (Parte A) |
| SSH não liga | Security group porta 22; `SSH_CIDR` = teu IP |
| HTTPS falha | DNS A record propagado? `deploy.sh` terminou? |

---

## Dev no Mac enquanto a EC2 não está pronta

Para testar **em casa** na mesma Wi‑Fi:

```bash
# No Mac, com Docker Desktop ligado
docker run -d -p 8002:8002 \
  -v ~/valhalla-data:/custom_files \
  ghcr.io/gis-ops/docker-valhalla/valhalla:latest
```

No `secrets.xcconfig` (IP do Mac: `ipconfig getifaddr en0`):

```
VALHALLA_SERVER_URL = http:||SEU_IP_MAC:8002
```

iPhone na **mesma rede**. Isto não substitui produção Oregon, mas valida o app.

---

## Não uses (para o teu objetivo)

- **Amazon Location + HERE** — mesmo tipo de API comercial que querias evitar (`truck-routing.yaml` com `DataSource: Here`).
- **t3.medium** sozinho — pouca RAM; o bootstrap usa **c5.xlarge**.

---

## Checklist segurança do motorista

- [ ] Valhalla HTTPS responde `/status`  
- [ ] App em 4G **sem** “Rota via OSRM” (ou só com fallback consciente)  
- [ ] Perfil camião (altura/peso) correto no app  
- [ ] Para frota: **“Apenas rotas seguras”** ON quando Valhalla estiver estável  
