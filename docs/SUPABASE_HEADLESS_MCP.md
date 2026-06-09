# Supabase MCP headless setup

Use this when the agent environment has no browser/OAuth flow.

## Required secrets

Create a Supabase PAT at:

```text
https://supabase.com/dashboard/account/tokens
```

Set these environment variables in the environment that launches Cursor/Claude Code/CI:

```bash
SUPABASE_PROJECT_REF=qhwuwiiwdzqkjzjqgpvx
SUPABASE_ACCESS_TOKEN=<supabase-pat>
```

Do not commit the PAT.

## Cursor / MCP config

Copy `.mcp.example.json` to the MCP config location used by your client and keep the `${...}` placeholders.

```json
{
  "mcpServers": {
    "supabase": {
      "type": "http",
      "url": "https://mcp.supabase.com/mcp?project_ref=${SUPABASE_PROJECT_REF}",
      "headers": {
        "Authorization": "Bearer ${SUPABASE_ACCESS_TOKEN}"
      }
    }
  }
}
```

Read-only variant:

```json
{
  "mcpServers": {
    "supabase": {
      "type": "http",
      "url": "https://mcp.supabase.com/mcp?project_ref=${SUPABASE_PROJECT_REF}&read_only=true",
      "headers": {
        "Authorization": "Bearer ${SUPABASE_ACCESS_TOKEN}"
      }
    }
  }
}
```

## GitHub Actions secrets

For Edge Function deployment, add repository or environment secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`

The workflow `.github/workflows/deploy-supabase-functions.yml` deploys all functions under `supabase/functions`.

Manual run:

```text
GitHub > Actions > Deploy Supabase Edge Functions > Run workflow
```

## Local deploy from a machine with Supabase CLI

```bash
export SUPABASE_ACCESS_TOKEN=<supabase-pat>
export SUPABASE_PROJECT_REF=qhwuwiiwdzqkjzjqgpvx
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase functions deploy ops-feed --project-ref "$SUPABASE_PROJECT_REF"
```
