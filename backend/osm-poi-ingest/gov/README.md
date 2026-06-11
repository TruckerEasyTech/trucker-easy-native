# Gov feeds (cópia para EC2)

Scripts espelhados de `backend/government-poi-ingest/` — **não corras na raiz de osm-poi-ingest**.

Na EC2:

```bash
cd ~/osm-poi-ingest
./run_gov_sync.sh
```

Canonical source: edit files in `backend/government-poi-ingest/` no repo e copia de novo para `gov/` antes do deploy.
