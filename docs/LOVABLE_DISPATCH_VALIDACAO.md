# Checklist — Site Lovable ↔ App iOS (dispatch, sem ops dashboard)

Projeto Supabase: **`usowafvqawbunyhmfscx`**  
Site: [https://truckereasy.com](https://truckereasy.com)  
Auth dispatchers: [https://truckereasy.com/auth](https://truckereasy.com/auth)

---

## A. Variáveis no Lovable (obrigatório)

No projeto Lovable → **Settings → Environment**:

| Variável | Valor |
|----------|--------|
| `VITE_SUPABASE_URL` | `https://usowafvqawbunyhmfscx.supabase.co` |
| `VITE_SUPABASE_ANON_KEY` | JWT `eyJ…` (anon public — **não** `sb_publishable_…`) |

**Teste no browser (F12 → Console):**

```js
const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
const sb = createClient('https://usowafvqawbunyhmfscx.supabase.co', 'SEU_ANON_JWT');
const { data, error } = await sb.from('dispatched_loads').select('id').limit(1);
console.log({ data, error });
```

- `error` com RLS → normal sem login; com login dispatcher deve poder **insert**.

---

## B. Tabelas Supabase (SQL Editor)

Correr se ainda não aplicaste:

1. `supabase_migration_fix.sql` (ou migrations do repo)
2. Confirmar colunas:

```sql
select column_name, data_type
from information_schema.columns
where table_name = 'dispatched_loads'
order by ordinal_position;
```

`driver_id` tem de existir (**text**, igual a `auth.users.id` em string).

---

## C. Portal dispatcher (`/auth` + `/dispatch`)

### C.1 Login empresa

- [ ] Sign in / Register em `/auth` cria sessão Supabase Auth
- [ ] Mesmo projeto que o app (`usowafvqawbunyhmfscx`)

### C.2 Criar carga para motorista

Ao inserir em `dispatched_loads`:

| Campo | Regra |
|-------|--------|
| `driver_id` | **UUID do motorista** (copiado do app → Perfil → Fleet account) |
| `load_number` | Texto único visível |
| `origin_address` / `destination_address` | Endereços |
| `destination_lat` / `destination_lng` | Números (obrigatório para rota) |
| `status` | `'pending'` |

**SQL de teste** (substituir `DRIVER_UUID`):

```sql
insert into dispatched_loads (
  driver_id, load_number, origin_address, destination_address,
  destination_lat, destination_lng, status, company_name
) values (
  'DRIVER_UUID',
  'TEST-001',
  'Dallas, TX',
  'Houston, TX',
  29.7604, -95.3698,
  'pending',
  'Test Fleet'
);
```

### C.3 Deep link (opcional no site)

Gerar link para o motorista abrir no app:

```
truckereasy://dispatch?loadId=LOAD_ID&lat=29.7604&lng=-95.3698&address=Houston%2C%20TX&loadNumber=TEST-001
```

---

## D. App iOS (repo — já implementado)

### D.1 Config

`Config/TruckerEasy.secrets.xcconfig`:

```
SUPABASE_URL = https:||usowafvqawbunyhmfscx.supabase.co
SUPABASE_ANON_KEY = eyJ...   // anon JWT
```

### D.2 Fluxo motorista

1. Abrir app → tab **Perfil** (último ícone)
2. **Fleet & Dispatch** → **Connect fleet account**
3. Sign in ou Create account (mesmo email que a frota usa)
4. Copiar **Driver ID** e dar ao dispatcher
5. **Refresh pending loads** → banner na aba **My Horizon**

### D.3 Testes

| Teste | Resultado esperado |
|-------|-------------------|
| Login com anon key inválida | Erro claro no sheet |
| Insert SQL com `driver_id` certo + Refresh no app | Banner de carga no mapa |
| Deep link Safari `truckereasy://dispatch?...` | App abre alerta de carga |
| Logout no Perfil | Token Supabase limpo |

---

## E. Edge functions (app crowd data)

```bash
supabase functions deploy ops-feed
```

Teste (com anon JWT):

```bash
curl -s "https://usowafvqawbunyhmfscx.supabase.co/functions/v1/ops-feed?lat=40.7&lon=-74&radius_km=50" \
  -H "apikey: SEU_ANON_JWT" \
  -H "Authorization: Bearer SEU_ANON_JWT"
```

Deve devolver JSON com `parking_signals` / `weigh_signals`, não 401.

---

## F. Valhalla (roteamento — independente do site)

- [ ] `https://valhalla.truckereasy.com/status` → HTTP 200 JSON
- [ ] App `VALHALLA_SERVER_URL` aponta para HTTPS
- [ ] `truck_routing_config` no Supabase (ops) alinhado — **o app lê xcconfig**, não a tabela

---

## G. O que o site **não** precisa fazer para o app

- Não servir API em `truckereasy.com` para o app
- Não misturar `/ops` marketing com dashboard interno (integrar `ops-dashboard/` à parte)
- Waitlist “Notify Me” pode ficar só no site até ligares a uma tabela `launch_waitlist`

---

## H. Ordem recomendada de validação end-to-end

1. Motorista: criar conta no app (Fleet account)
2. Copiar Driver ID
3. Dispatcher: insert carga com esse `driver_id` (SQL ou UI `/dispatch`)
4. Motorista: Refresh pending loads → ver banner
5. Aceitar carga → rota (quando Valhalla estiver 200)

---

## Problemas comuns

| Sintoma | Causa provável |
|---------|----------------|
| 0 cargas no app | `driver_id` errado ou motorista sem login |
| HTTP 401 ops-feed | Function não deployada ou anon key errada |
| Rota não truck-safe | Valhalla 503 — EC2 ainda a buildar tiles |
| Site dispatch não grava | Lovable sem `VITE_SUPABASE_*` ou RLS bloqueia insert |
