# App Store + rotas de camião — o que é verdade

## O que a Apple exige (simplificado)

- O app **não pode crashar** se o teu servidor estiver offline.  
- Deve haver **comportamento razoável** sem conta/servidor opcional.  
- **Não** é obrigatório que *todas* as funcionalidades funcionem offline.  
- **Não** é obrigatório esconder que rotas Pro usam o teu servidor.

Muitas apps (Waze, apps de frota, etc.) dependem de backend; passam review com fallback claro.

---

## O que o Trucker Easy já faz (código atual)

| Camada | Função | Review Apple (servidor down) |
|--------|--------|------------------------------|
| Valhalla | Rota **camião** (Pro / produção) | Falha → passa ao seguinte |
| OSRM público | Fallback com aviso | ✅ Rota calcula |
| MapKit | Fallback Apple | ✅ Rota calcula |
| Cache | Rota guardada | ✅ Se existir cache |
| `truckSafeOnlyMode` OFF | Padrão | ✅ Sempre há rota *ou* aviso |
| `truckSafeOnlyMode` ON | Bloqueia carro | Erro explícito (segurança frota) |

**Conclusão:** não precisas reimplementar a arquitetura híbrida — **já está em** `RoutingService.swift`.

---

## Estratégia recomendada para submissão

### 1. Default para review

- `truckSafeOnlyMode` = **OFF** (já é o padrão).  
- Valhalla URL pode estar vazio ou apontar para produção; se falhar, MapKit/OSRM funcionam.

### 2. Notas para o revisor (App Store Connect)

Texto sugerido (inglês):

```
Routing: The app calculates driving directions using Apple MapKit when our optional 
truck-optimized server is unavailable. Truck-specific height/weight routing requires 
network access to our Valhalla service; users see a clear notice when a car-grade 
fallback route is shown. Test account: [email]. Demo load: [city A] to [city B].
```

### 3. Produto real (motoristas)

- **Produção:** Valhalla HTTPS Oregon.  
- **Frotas:** toggle “Apenas rotas seguras para caminhão” ON.  
- **Marketing:** “Rotas otimizadas para caminhão” quando Valhalla OK — não prometer o mesmo nível só com MapKit.

### 4. Freemium / IAP (opcional)

A AWS sugeriu subscrição Pro — é **negócio**, não requisito da Apple. Podes:

- Grátis: MapKit + aviso.  
- Pro: Valhalla + Route Easy + sem limite.

Implementar IAP é fase posterior; **não bloqueia** a submissão.

---

## Mitos da AWS (esclarecer)

| Afirmação AWS | Realidade |
|---------------|-----------|
| “Não pode depender de servidor próprio” | Podes; precisas de **fallback** ou mensagem clara |
| “Apple testa sem teu servidor” | Testam que o app **não quebra**; MapKit cobre isso |
| “Deve funcionar offline” | GPS offline sim; **rotas novas** offline são limitadas (cache) |
| “Implementar IAP primeiro” | Opcional |

---

## Segurança do motorista vs review

| Objetivo | Config |
|----------|--------|
| Máxima segurança (frota) | Valhalla produção + truck-safe **ON** |
| Passar review + demo | truck-safe **OFF** + MapKit fallback |
| Melhor dos dois | Produção Valhalla + truck-safe ON para contas empresa; OFF só em build demo se necessário |

---

## Próximo passo técnico (não código)

1. Deploy Valhalla pelo Mac: `docs/DEPLOY_VALHALLA_DO_MAC.md`  
2. Testar iPhone 4G  
3. Preparar notas do revisor + conta demo  

Nenhuma mudança obrigatória no Swift para a App Store além de manter o fallback atual.
