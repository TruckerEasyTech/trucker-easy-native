# Estudo: estrutura de um GPS de caminhão profissional (US/CA) — Trucker Path, Google/HERE, fleet

> Pesquisa feita por Jarvis (16/06/2026) com fontes reais, p/ posicionar o Trucker Easy
> contra os profissionais. Foco: maps, telemetria, fusão de dados. Sem teoria vazia —
> cada bloco aponta o que o app JÁ faz e o GAP concreto.

## 1. As 6 camadas de um GPS de caminhão profissional

1. **Roteamento truck-aware** — altura/peso/comprimento/eixo/hazmat + restrições de via.
2. **Map matching** — encaixar o GPS ruidoso na geometria da via correta (crítico p/ não ler restrição da via errada).
3. **Telemetria** — velocidade/posição/rumo ao vivo + média móvel, alimentando ETA, HOS e reachability.
4. **Dados ao vivo** — tráfego, balanças, parking, preço de diesel (próprios + crowdsourcing + gov).
5. **HOS/ELD** — horas de direção, rulesets automáticos por estado/fuso, pausas sugeridas na rota.
6. **Offline** — tiles + rota cacheados p/ áreas sem sinal.

## 2. Como o TRUCKER PATH faz (o benchmark de crowdsourcing)
- **Modelo "a comunidade sustenta a comunidade":** ao chegar num posto, o servidor PERGUNTA ao motorista o status de parking (cheio/algumas/vazio). ([Overdrive](https://www.overdriveonline.com/parking/article/15382894/crowdsourcing-a-solution-to-the-truck-parking-crisis))
- **Volume:** ~**15.000** updates de balança + ~**13.000** de parking **por dia**. ([FleetOwner](https://www.fleetowner.com/technology/article/21692143/crowd-sourcing-helps-app-get-around-parking-data-limitations))
- **Moderação + fontes oficiais:** time de moderação + dados direto de postos e agências estaduais.
- **Histórico → predição:** os reports são logados historicamente p/ mostrar *tendência* ("costuma ter vaga às 14h").

**→ GAP do Trucker Easy:** a estrutura de crowdsourcing JÁ existe (tabelas `truck_stop_parking_reports`, `weigh_station_reports`), mas estão **vazias** (0 linhas). O que falta NÃO é código — é o **loop de pedir o report** (igual Trucker Path: perguntar ao chegar) + volume de usuários. A predição histórica é um passo 2 (precisa de volume primeiro).

## 3. Como GOOGLE/HERE/fleet (Samsara, Trimble, Verizon) fazem
- **Map matching por HMM** (Hidden Markov Model): cada segmento de via = um "estado", cada fix de GPS = uma "observação"; o algoritmo acha a sequência de vias mais provável, usando **geometria + topologia + direção de movimento + limite de velocidade da via**. Robusto a ruído de GPS. ([PLOS One](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0302656))
- **Probe data:** a velocidade real dos veículos (probe) alimenta tráfego ao vivo e melhora o matching.
- **ELD integrado:** navegação + HOS num módulo só; **rulesets automáticos por GPS/estado**, e **pausas HOS-compliant sugeridas na rota** ("pare em X em 200 mi"). ([HOS247](https://hos247.com/resources/fleet-tracking/trucks-gps-tracking/), [Trimble CoPilot](https://transportation.trimble.com/en/solutions/mapping-and-routing/copilot))

**→ GAP do Trucker Easy:**
- **Map matching:** o app hoje faz snap **geométrico + gate de direção** (`PolylineLeadArrow.snappedPosition`, melhorado recente). É bom, mas é "nearest-segment com bearing", **não HMM**. Para interseções complexas, um HMM (estado=segmento, transição por topologia) seria o upgrade profissional. **Roadmap, não bloqueio.**
- **HOS:** o `DotHosContext` rastreia 11h/14h/pausa e detecta direção por velocidade — sólido. **Falta:** ruleset automático por estado/fuso e **pausa sugerida na rota** (o app avisa ETA×HOS por voz, mas não diz "pare em X"). Próximo diferencial.
- **ELD real:** hoje é timer local (não-ELD certificado). Integração ELD é contrato/hardware — fora do MVP.

## 4. Telemetria — o que o app JÁ tem e o padrão
| Sinal | Profissional | Trucker Easy hoje |
|---|---|---|
| Posição/rumo ao vivo | probe + map-matched | GPS + snap por bearing ✅ |
| Velocidade instantânea | ✅ | `currentSpeedMph` ✅ |
| **Velocidade média (real)** | rolling/probe | **`averageDrivingSpeedMph`** (acabei de adicionar) ✅ |
| ETA × HOS | ✅ | por voz ✅ |
| Jitter de manobra | filtrado | log `[NavJitter]` + snap melhorado ✅ |

## 5. Princípio que separa profissional de amador (e que o app agora segue)
**Nunca apresentar dado incerto como fato.** Trucker Path mostra "status reportado há X" (com proveniência); não inventa. O Trucker Easy passou por uma auditoria que **eliminou todas as simulações** (balança "monitoring" falsa, vagas fabricadas, notícias inventadas, velocidade chutada) — agora: **dado real ou "desconhecido", nunca chute.** Ver memória `trucker-easy-anti-falsopositivo`.

## 6. Roadmap priorizado p/ chegar no nível Trucker Path
1. **Loop de crowdsourcing ativo** (perguntar parking/balança ao chegar) → enche as tabelas vazias. *(maior alavanca, é o moat do Trucker Path)*
2. **Pausa HOS sugerida na rota** ("pare em X em 200 mi") → diferencial de segurança.
3. **Ruleset HOS automático por estado/fuso.**
4. **Map matching HMM** (upgrade do snap) p/ interseções complexas.
5. **Predição histórica de parking** (depois do volume de reports).
6. **Tráfego ao vivo** (probe/Mapbox) p/ reroute dinâmico.

> Conclusão: o Trucker Easy tem a **espinha dorsal certa** (Valhalla truck-aware, telemetria real, HOS, offline, dado honesto). A distância pro Trucker Path é **dado ao vivo via crowdsourcing** (estrutura pronta, falta o loop + usuários), não arquitetura.
