# Checklist — retomar após route-proxy deployado

**Feito (26–27 mai):**
- `route-proxy` deployada no Supabase (`usowafvqawbunyhmfscx`)
- Secret `ROUTE_OPTIMIZATION_UPSTREAM_URL` configurado
- `ROUTE_OPTIMIZATION_UPSTREAM_API_KEY` **não** necessário (length 0 no EC2)
- App aponta para HTTPS (`route-proxy`), não HTTP direto no IP
- Valhalla no EC2: porta **8002**, container `valhalla-truck` OK

**Pendente (não bloqueia TestFlight básico):**
1. **EC2 — quantum routing na porta 8003**
   - SSH/scp na porta 22 está fechado; usar S3, Git clone, ou abrir SG temporariamente
   - Depois de copiar `backend/quantum-routing` para o EC2:
     ```bash
     cd /caminho/quantum-routing
     bash deploy-ec2-docker.sh
     ```
   - Container expõe **8787** internamente; host **8003** (igual ao secret)

2. **Validar route-proxy com usuário logado**
   - App → login → rota **AI Smart**
   - Dashboard → Functions → `route-proxy` → Logs
   - `502 upstream unavailable` = EC2 :8003 ainda offline (esperado até passo 1)

3. **TestFlight**
   - Build com `Config/TruckerEasy.secrets.xcconfig` (gitignored)
   - Rotas **Rápida** e **Sem pedágios** via Valhalla
   - AI Smart: OK na UI; optimize completo só após EC2 :8003

**Comandos úteis (Mac):**
```bash
cd "/Users/thaiskeller/Desktop/trucker easy app"
./scripts/deploy_route_proxy.sh
supabase secrets list --project-ref usowafvqawbunyhmfscx --workdir "$(pwd)"
```
