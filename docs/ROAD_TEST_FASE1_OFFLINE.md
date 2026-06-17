# 🚚 Roteiro de Teste de Estrada — Fase 1 Offline + P0 de Segurança

> Valida o trabalho de 16/06/2026: roteamento offline (Fase 1) + fixes P0 (#4 HOS por país, #5 permissão) + checagens de navegação. **Navegação NÃO roda no simulador (anti-spoof rejeita GPS simulado) — tem que ser no device, em movimento real.**

## ⚠️ Antes de começar — escolha o tipo de build
| Build | Onde | Logs `[Route]`/`[Valhalla]` aparecem? | Use para |
|---|---|---|---|
| **Debug (Xcode no device)** | cabo + iPhone | ✅ SIM (console do Xcode) | **Validação técnica** (ver os logs internos) |
| **TestFlight (Release)** | TestFlight | ❌ NÃO (`#if DEBUG` some) | Validação **visual** (banner, rota continua) |

**Recomendo o teste técnico em Debug com o iPhone no cabo** (passageiro com o Mac, ou parado revisando o console depois). Em TestFlight valida-se só o comportamento visível.

## 🔧 Setup
- [ ] Dirigir com **passageiro** segurando o telefone (segurança primeiro).
- [ ] Location Services **ON**; ao iniciar a rota, **aceitar "Sempre"** quando o iOS pedir (isso é o teste do #5).
- [ ] Bateria carregada / no carregador (GPS + tela ligada consome).
- [ ] Se Debug: Xcode aberto, console visível, filtrar por `[Route]`, `[Valhalla]`, `[HorizonGPS]`.

---

## TESTE 1 — Permissão "Sempre" (P0 #5)
**Ação:** iniciar uma rota nova. Quando começar a navegar, **bloquear a tela** por ~1 min dirigindo.
**Esperado:**
- [ ] No início da rota, o iOS pede permissão **"Sempre"** (se estava em "Quando em uso").
- [ ] Com a tela bloqueada, ao desbloquear, o **boneco está na posição certa** (não congelou 1 min atrás).
**Capturar:** se o boneco congelou → anotar se a permissão estava em "Sempre" ou "Quando em uso" (Ajustes → Trucker Easy → Localização).

---

## TESTE 2 — Banner offline aparece (Fase 1.4)
**Ação:** com uma rota ativa em navegação, ligar **Modo Avião**. *(No iPhone o GPS continua funcionando em Modo Avião — é exatamente o cenário "sem rede, GPS vivo".)*
**Esperado:**
- [ ] Em segundos aparece o pill **"Offline · GPS ativo, siga a rota"** no topo.
- [ ] O **boneco continua se movendo** (GPS vivo) e a **rota continua na tela** (não some, não fica branca).
**Capturar:** foto da tela com o banner. Tempo até o banner aparecer.

---

## TESTE 3 — Reroute offline mantém a rota (Fase 1.3)
**Ação:** ainda em Modo Avião e navegando, **errar de propósito** (pegar uma saída/rua fora da rota).
**Esperado:**
- [ ] **NÃO** aparece modal de erro de rota.
- [ ] **NÃO** trava por 2,5 min.
- [ ] A rota continua viva; o app guia de volta ("retorne à rota") conforme você se reaproxima.
**Capturar (Debug):** no console deve aparecer `[Route] Reroute OFFLINE — mantendo rota em cache`.

---

## TESTE 4 — Troca pra alternativa do corredor (Fase 1.2b)
**Ação:** numa região com **rotas paralelas** (ex.: rodovia + via marginal, ou 2 caminhos pro mesmo destino), iniciar a rota **com sinal** (pra baixar o corredor/alternates), depois ligar **Modo Avião** e **desviar pra um caminho alternativo plausível** ao destino.
**Esperado:**
- [ ] Se o caminho que você pegou bate com uma alternativa, o app **troca pra ela** offline (a linha da rota muda pro seu caminho) em vez de insistir na original.
**Capturar (Debug):** `[Route] Reroute OFFLINE → troca p/ alternativa do corredor (Xm vs principal Ym)`. Se NÃO trocar, anote a distância — pode ser que nenhuma alternativa estava perto o suficiente (>60m de diferença).
**Nota:** depende do Valhalla ter retornado alternates pra aquele par origem/destino — confirmar em Debug com `[Valhalla] ✅ Route` e que houve resposta com `alternates`.

---

## TESTE 5 — Sinal volta, normaliza
**Ação:** **desligar o Modo Avião**.
**Esperado:**
- [ ] O **banner offline some**.
- [ ] Se você estiver fora da rota, o **reroute online** recalcula normalmente (com sinal).
**Capturar:** tempo até o banner sumir após restaurar a rede.

---

## TESTE 6 — Os 3 modos de rota (verificação anterior)
**Ação:** ao traçar uma rota (com sinal), abrir o seletor de modos.
**Esperado:**
- [ ] Aparecem **Rápida**, **Sem pedágio** e **AI/Economia** com números diferentes (tempo/pedágio/economia).
- [ ] "Sem pedágio" realmente desvia de cabines onde dá; o custo aparece como **"Est."** (estimado).
**Capturar:** foto do seletor com os 3 cartões.

---

## TESTE 7 — Seta de manobra + saída (verificação anterior)
**Ação:** navegar até uma saída de rodovia.
**Esperado:**
- [ ] A **instrução é grande/legível** (não minúscula).
- [ ] O **número da saída** (exit shield) e o **"toward [cidade]"** aparecem quando a instrução do Valhalla traz.
- [ ] **Não** aparece a barra de faixas fake (4 faixas todas verdes) — foi removida.
**Capturar:** foto numa saída.

---

## TESTE 8 — HOS por país (P0 #4) — só se cruzar a fronteira
**Ação:** *(opcional, só quem cruza US↔Canadá)* dirigir através da fronteira.
**Esperado:**
- [ ] Ao entrar no Canadá, o limite de HOS muda pra **13h/16h** (NSC); ao voltar aos EUA, **11h/14h** (FMCSA).
- [ ] As **unidades/moeda NÃO mudam** sozinhas (continua sua preferência).
**Capturar (Debug):** observar o painel HOS antes/depois da fronteira. *(Sem cruzar fronteira, este teste não se aplica — anotar "N/A".)*

---

## 📝 Tabela de resultados (preencher)
| Teste | Passou? | Observação / o que capturou |
|---|---|---|
| 1 — Permissão "Sempre" | ☐ | |
| 2 — Banner offline | ☐ | |
| 3 — Reroute offline mantém rota | ☐ | |
| 4 — Troca p/ alternativa | ☐ | |
| 5 — Sinal volta normaliza | ☐ | |
| 6 — 3 modos de rota | ☐ | |
| 7 — Seta + saída | ☐ | |
| 8 — HOS por país | ☐ N/A | |

## 🆘 Se algo falhar
Anote: **o quê**, **onde** (GPS/cidade), **com ou sem sinal**, e o **log do console** (se Debug). Mandar de volta pro ajuste. Os logs-chave a procurar: `[Route] Reroute OFFLINE`, `[Valhalla] ✅ Route`, `[HorizonGPS] firstFix`.
