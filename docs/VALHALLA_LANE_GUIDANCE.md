# Lane guidance (qual faixa pegar) — investigação do Valhalla

> Investigado por Jarvis em 15/06/2026, contra o Valhalla de produção
> (`valhalla.truckereasy.com`). Objetivo: a UI já está pronta p/ faixa
> (`HorizonLaneGuidanceBar` aceita `activeLaneMask`), falta o DADO.

## Diagnóstico (dados reais, não suposição)

Testado direto no servidor:
- **Versão:** Valhalla **3.5.1** (recente — *suporta* lane guidance). ✅
- **Tiles:** construídos em **2026-05-26** (frescos). ✅
- **3 rotas testadas** (Atlanta, Manhattan, saída de freeway I-285) = **26 manobras, ZERO com `lanes`**.
- **`/locate` (atributos de edge):** tem **`lane_count=2`** (nº de faixas) mas **NÃO tem `turn_lanes`** (direção de cada faixa).

### Causa-raiz
**Não é versão nem tiles velhos.** O `lanes` da manobra (Odin) depende de **`turn:lanes`**
armazenado nos tiles — e o build atual **não importou** essa informação (só `lane_count`).
É um problema de **config de build (mjolnir)**, não de cliente.

Config atual (`backend/valhalla-production/deploy.sh`): imagem
`ghcr.io/gis-ops/docker-valhalla/valhalla:latest`, env padrão
(`build_admins=True`, `build_time_zones=True`, `build_elevation=False`,
`force_rebuild=False`) — **sem nada habilitando turn lanes**.

## O que seria preciso para ter faixa real

1. **SSH na EC2** e inspecionar o `valhalla.json` gerado (seção `mjolnir`) — confirmar
   se o import de turn lanes está ligado. A imagem gis-ops gera o config; pode ser
   preciso um `valhalla.json` customizado em `custom_files/`.
2. **Rebuild dos tiles** com turn lanes habilitado: `force_rebuild=True` + (se preciso)
   config custom. Custo/tempo: **~1–3h** de build na **c5.xlarge** (instância paga —
   é o mesmo tipo que está fora do AWS Free Tier; ver `docs/AWS_TU_FAZES.md`).
3. **VERIFICAR antes de tocar no cliente:** `curl /locate ...verbose` deve mostrar
   `turn_lanes`, e uma rota de teste deve trazer `lanes` nas manobras. Só então
   construir o pipeline cliente (parser Valhalla → `RouteStep.lanes` → `activeLaneMask`).

### ⚠️ Riscos honestos
- **Incerto** se a imagem gis-ops emite turn lanes mesmo com config ajustada — pode
  exigir build manual do Valhalla. Por isso o passo 3 (verificar) é obrigatório.
- Mesmo funcionando, **cobertura é parcial**: só vias com `turn:lanes` no OSM
  (rodovias/grandes interseções, não toda rua).
- É um **projeto de backend de horas**, com payoff incerto — **não é bloqueador de launch**.

## Recomendação
- **Já entregue (dado que existe):** placa de saída grande + destino (`EXIT 29 → Ashford
  Dunwoody Road`). Resolve "ver melhor onde/pra onde sair" sem depender de faixa.
- **Faixa de verdade:** tratar como tarefa de infra futura (passos 1–3 acima), pós-launch.

## 🎁 Bônus achado na investigação
O `/locate` mostra **`speed_limit` por edge** nos tiles. Ou seja: o **limite de velocidade
real por trecho** está disponível no Valhalla — dá pra ligar isso no aviso de velocidade
(Issue 2 do teste de estrada) e trocar o limite-base genérico (65) pelo limite real da via.
Ver [[trucker-easy-roadtest-fixes]] (memória).
