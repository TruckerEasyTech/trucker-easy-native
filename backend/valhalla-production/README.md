# Valhalla Production — Truck-Aware Routing

## Por que Valhalla e essencial

O Valhalla e o **unico** provedor de rotas no Trucker Easy que respeita restricoes de caminhao:
- **Altura** (pontes baixas)
- **Peso** (limite de GVW/eixo)
- **Comprimento** (curvas apertadas, tuneis)
- **Hazmat** (zonas proibidas para materiais perigosos)
- **Pedagios** (evitar/preferir)

Sem Valhalla, o app usa OSRM (roteamento de carro) ou MapKit (Apple Maps) como fallback — **nenhum deles conhece restricoes de caminhao**.

## Opcoes de Deploy

### Opcao 1: DigitalOcean (Recomendado — $48/mes)
```bash
# 1. Criar droplet: Ubuntu 24.04, 8GB RAM, 160GB SSD ($48/mes)
# 2. Apontar DNS: valhalla.truckereasy.com → IP do droplet
# 3. SSH e rodar:
bash deploy.sh valhalla.truckereasy.com
```

### Opcao 2: AWS EC2 (Oregon — us-west-2)

**Passo A — CloudShell (só infra: EC2 + IP + firewall):**
```bash
export AWS_REGION=us-west-2
export VALHALLA_DOMAIN=valhalla.truckereasy.com
export KEY_NAME=truckereasy-valhalla   # key pair já criada em Oregon
bash backend/valhalla-production/aws-oregon-valhalla-bootstrap.sh
```

**Passo B — SSH na EC2 (Valhalla + tiles, 1–3 h na 1ª vez):**
```bash
ssh -i ~/.ssh/truckereasy-valhalla.pem ubuntu@<IP_DO_SCRIPT>
sudo bash /caminho/para/deploy.sh valhalla.truckereasy.com
```

- `c5.xlarge` + 160 GB gp3 — ~$50–70/mes
- Teardown: `source ~/valhalla-oregon-i-xxx.env && bash aws-oregon-teardown.sh`

### Opcao 3: Render.com / Railway (PaaS mais simples)
- Usar o Docker image `ghcr.io/gis-ops/docker-valhalla/valhalla:latest`
- Apontar dominio customizado
- Minimo 4GB RAM

## Apos Deploy

Atualizar `Config/TruckerEasy.secrets.xcconfig`:
```
VALHALLA_SERVER_URL = https:||valhalla.truckereasy.com
```

## Cobertura Regional

O `deploy.sh` baixa e funde **US + Canada** (~14 GB PBF; tiles ~3–6 h na 1ª build).
Isto cobre rotas truck-aware nos EUA e Canada (TestFlight / frota NA).

Para Mexico ou outras regioes, adicionar PBF ao merge antes do tile build:
```bash
# Mexico (Geofabrik):
wget https://download.geofabrik.de/north-america/mexico-latest.osm.pbf
osmium merge us-latest.osm.pbf canada-latest.osm.pbf mexico-latest.osm.pbf -o us-ca-mx.osm.pbf

# Europa (dev local no Mac — ver comentario em ServicesValhallaRoutingService.swift):
wget https://download.geofabrik.de/europe-latest.osm.pbf
```

## Custo vs. APIs Comerciais

| Solucao | Custo/mes | Drivers | Truck-Aware |
|---------|-----------|---------|-------------|
| Valhalla proprio | $48-100 fixo | Ilimitado | Sim |
| HERE Truck API | ~$10/driver | Variavel | Sim |
| Google Routes | ~$5/1000 req | Variavel | Parcial |
| OSRM (gratuito) | $0 | Ilimitado | **Nao** |
