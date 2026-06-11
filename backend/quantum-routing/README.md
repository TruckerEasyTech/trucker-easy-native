# Middleware de otimização de rotas (Trucker Easy)

Contrato HTTP entre o **app iOS (Swift)** e um motor Python. **Produção (EC2): greedy** — reordena paragens sem D-Wave. **Dev opcional:** Leap / Braket via `ROUTE_OPT_SOLVER=hybrid`.

## Produção (EC2 / Docker) — greedy only

```bash
cd backend/quantum-routing
docker build -t truckereasy-route-opt .
docker run -p 8003:8787 \
  -e ROUTE_OPT_SOLVER=greedy \
  -e DISABLE_DWAVE=1 \
  truckereasy-route-opt
# ou: ./deploy-ec2-docker.sh na EC2
```

- `GET /health` → `"solver_mode":"greedy"`, `"disable_dwave":"1"`
- `POST /v1/optimize` → `solver_used`: `greedy_nn` (ou `simulated_quantum_annealing` se `USE_TSP_SA_SIMULATOR=1`)
- **Valhalla** continua a desenhar a estrada; este serviço só muda a **ordem das paragens** em dispatch multi-stop.
- **App iOS:** inalterado — se optimize falhar, Valhalla route still works.

## Arranque local (dev)

```bash
cd backend/quantum-routing
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# Configurar Leap: https://docs.dwavequantum.com/en/latest/ocean/sapi_access_basic.html
export ROUTE_OPTIMIZATION_API_KEY=dev-secret   # opcional; exige header X-API-Key no cliente
uvicorn app.main:app --reload --host 0.0.0.0 --port 8787
```

- `GET http://localhost:8787/health` ou **`/status`** — mesmo JSON (`"status": "ok"`), útil no Safari do iPhone contra o IP do Mac na LAN.
- `POST http://localhost:8787/v1/optimize` — corpo JSON = contrato em `app/contracts.py`; na resposta use **`solver_used`** (ex. `amazon_braket_dwave`). O servidor também imprime uma linha `[route-opt] Solver: …` no terminal em cada otimização bem encaminhada.
- **`metrics`** na resposta: `approx_km_saved` = poupança aproximada (km) de um **percurso fechado Haversine** «manual» (ordem das paragens no pedido) vs ordem optimizada — útil em testes de campo; para km de estrada use odómetro / polilinha do `RoutingService` numa fase seguinte.
- `DISABLE_DWAVE=1` — força greedy (útil em CI sem credenciais Leap)
- **`DWAVE_API_TOKEN` ausente** — o motor usa **`dwave-neal`** (Simulated Annealing clássico) sobre um QUBO equivalente ao TSP-atribuição; o JSON de resposta mantém-se idêntico (`solver_used`: `dwave_neal_sa`). Com token, tenta-se primeiro **Leap Hybrid CQM**; se falhar, tenta-se Neal e por fim greedy.

## Valhalla + quântico (arquitetura híbrida no iOS)

O app já separa os dois papéis:

| Serviço | Porta típica (dev) | Função |
|--------|----------------------|--------|
| **Valhalla** | `8002` | Polyline / costing camião na estrada (`VALHALLA_SERVER_URL` no xcconfig). |
| **Este FastAPI** | `8003` (ou `8002` se só quântico) | `POST /v1/optimize` — ordem das paragens (TSP); `RouteOptimizationAPIBaseURL` no xcconfig. |

O módulo ASGI é sempre **`app.main:app`** (não `main:app`). O ficheiro `run_server.sh` chama `uvicorn` com o caminho certo; por defeito usa a porta **8003**.

### Opção 2 — só o servidor quântico na 8002 (Valhalla parado)

```bash
docker stop valhalla-europe 2>/dev/null || true
# Em .env: USE_AMAZON_BRAKET=1 e bucket + BRAKET_DWAVE_DEVICE_ARN + credenciais AWS (ver .env.example)
cd backend/quantum-routing && source .venv/bin/activate
chmod +x run_server.sh
PORT=8002 ./run_server.sh
curl -s "http://127.0.0.1:8002/status"
```

### Opção 3 — Valhalla + quântico (recomendado)

Valhalla a ouvir na **8002**; este middleware na **8003** (`./run_server.sh` sem `PORT=`). No `TruckerEasy.secrets.xcconfig`: `VALHALLA_SERVER_URL` com `:8002` e `ROUTE_OPTIMIZATION_API_BASE_URL` com `:8003`; se definires `ROUTE_OPTIMIZATION_API_KEY` no `.env`, usa o mesmo valor no xcconfig.

#### Terminal no Mac (dois serviços)

**1) Valhalla (Europa) — porta 8002** (outro terminal ou o mesmo após o pull):

```bash
docker run -d -p 8002:8002 --name valhalla-europe \
  -e tile_urls=https://download.geofabrik.de/europe-latest.osm.pbf \
  ghcr.io/gis-ops/docker-valhalla/valhalla:latest
```

A primeira execução pode demorar (download PBF + build de tiles). Acompanhar: `docker logs -f valhalla-europe`. Se o nome já existir: `docker rm -f valhalla-europe` antes de voltar a correr.

**2) Middleware Python — porta 8003**

```bash
cd backend/quantum-routing && source .venv/bin/activate
chmod +x run_server.sh   # uma vez
./run_server.sh          # PORT por defeito 8003
```

**3) Teste no iPhone (Safari, mesma Wi‑Fi que o Mac)**

1. IP do Mac na LAN: `ipconfig getifaddr en0` (se vazio, tentar `en1`).
2. Abrir: `http://<IP-do-Mac>:8003/status` — JSON com `"status":"ok"` confirma que o telemóvel alcança o middleware (substitui `192.168.0.105` pelo teu IP real).

No xcconfig do app: `http:||<IP-do-Mac>:8002` (Valhalla) e `http:||<IP-do-Mac>:8003` (optimização), regra `||` → `//` no Swift.

## AWS Lambda

Empacotar com dependências Linux (`pip install -r requirements.txt --target package`) e expor com **API Gateway + Lambda**; opcionalmente usar [Mangum](https://github.com/jordaneremieff/mangum) como ASGI adapter sobre o handler FastAPI.

## Segurança (obrigatório)

- **Nunca** commits de `AWS_SECRET_ACCESS_KEY`, `AWS_ACCESS_KEY_ID`, `DWAVE_API_TOKEN`, nem ficheiros `.env` preenchidos.
- Chaves expostas em chat, e-mail ou tickets devem ser consideradas **comprometidas**: revogar na IAM / rotacionar de imediato e criar credenciais novas.
- Em produção, preferir **IAM role** (ECS, EKS, Lambda, EC2) em vez de access keys de utilizador de longa duração.
- Copiar apenas `backend/quantum-routing/.env.example` → `.env` local (ignorado pelo Git) e preencher variáveis no deploy (Secrets Manager, Parameter Store, etc.).

## D-Wave / Ocean (só no servidor)

1. **Instalar Ocean + Braket (opcional)** num venv Python ≥ 3.10: [Installing the Ocean SDK](https://docs.dwavequantum.com/en/latest/ocean/install.html) (`pip install -r requirements.txt`). O plugin Braket instala-se com o mesmo `requirements.txt`.
2. **Credenciais Leap** — no container/VM de deploy, executar `dwave setup` / `dwave config create` conforme [Configuring Access to the Leap Service](https://docs.dwavequantum.com/en/latest/ocean/sapi_access_basic.html), ou montar `dwave.conf` via secret do orquestrador (**nunca** no repositório nem no app iOS).
3. **Amazon Braket (D-Wave QPU)** — quando `USE_AMAZON_BRAKET=1` e estão definidos `BRAKET_RESULTS_S3_BUCKET`, `BRAKET_DWAVE_DEVICE_ARN` e credenciais AWS (ou role), o motor envia o **mesmo BQM** usado pelo Neal para o sampler [BraketDWaveSampler](https://amazon-braket-ocean-plugin-python.readthedocs.io/) (hardware D-Wave na região, ex. `us-west-2`). A resposta JSON mantém-se; `solver_used` pode ser `amazon_braket_dwave`.
4. **Prioridade** (modo `hybrid_cqm`): **Braket** (se configurado) → **Leap Hybrid CQM** (se `DWAVE_API_TOKEN`) → **Plano B** (`USE_TSP_SA_SIMULATOR=1`: força bruta / SA clássico, `solver_used`: `simulated_quantum_annealing`) → **dwave-neal** (se `DISABLE_DWAVE` não estiver activo) → **greedy**.
5. **`ROUTE_OPTIMIZATION_API_KEY`** — define no ambiente do serviço o mesmo valor que colocas em `RouteOptimizationAPIKey` no xcconfig do iOS; o cliente envia `X-API-Key` em cada `POST /v1/optimize`.

## Deploy do contentor

```bash
docker build -t truckereasy-route-opt ./backend/quantum-routing
docker run -p 8787:8787 \
  -e ROUTE_OPTIMIZATION_API_KEY=… \
  -e DWAVE_API_TOKEN=… \
  -e AWS_DEFAULT_REGION=us-west-2 \
  -e USE_AMAZON_BRAKET=1 \
  -e BRAKET_RESULTS_S3_BUCKET=… \
  -e BRAKET_DWAVE_DEVICE_ARN=… \
  truckereasy-route-opt
```

Variáveis Braket adicionais: ver `.env.example` (`BRAKET_RESULTS_S3_PREFIX`, `BRAKET_NUM_READS`).

Mapear `/optimize` e `/v1/optimize` no *load balancer* / API Gateway para a porta **8787**.
