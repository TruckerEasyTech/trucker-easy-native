"""API HTTP do middleware de otimização — contrato estável para o cliente Swift."""

from __future__ import annotations

import os
from pathlib import Path


def _load_local_env() -> None:
    """Carrega `backend/quantum-routing/.env` ao arrancar (override=False: export do shell ganha)."""
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if not env_path.is_file():
        return
    try:
        from dotenv import load_dotenv

        load_dotenv(env_path, override=False)
    except ImportError:
        pass


_load_local_env()

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .contracts import OptimizeRequest, OptimizeResponse
from .vrp_engine import run_optimization

# Lotus Cortex API gateway disabled until formal partnership (no API keys).
# See app/health_gateway.py and docs/LOTUS_PARTNER_PREMIUM.md

app = FastAPI(title="Trucker Easy Route Optimization", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("CORS_ALLOW_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
@app.get("/status")
def health() -> dict[str, str]:
    """`/status` mirrors `/health` + hints opcionais (chaves extra não quebram clientes que só leem `status`)."""
    mode = os.environ.get("ROUTE_OPT_SOLVER", "greedy").strip().lower()
    out: dict[str, str] = {
        "status": "ok",
        "service": "trucker-easy-route-optimization",
        "solver_mode": mode,
    }
    if mode == "greedy" or os.environ.get("DISABLE_DWAVE", "1").lower() in ("1", "true", "yes"):
        out["message"] = "Production path: greedy stop-order (no D-Wave/Braket). Valhalla draws roads."
    if os.environ.get("USE_TSP_SA_SIMULATOR", "").lower() in ("1", "true", "yes"):
        out["plan_b"] = "simulated_quantum_annealing"
        out["message"] = "Classical TSP SA enabled (USE_TSP_SA_SIMULATOR=1); same POST /v1/optimize contract."
    if os.environ.get("DISABLE_DWAVE", "1").lower() in ("1", "true", "yes"):
        out["disable_dwave"] = "1"
    return out


@app.post("/optimize", response_model=OptimizeResponse)
@app.post("/v1/optimize", response_model=OptimizeResponse)
def optimize(
    body: OptimizeRequest,
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
) -> OptimizeResponse:
    expected = (os.environ.get("ROUTE_OPTIMIZATION_API_KEY") or "").strip()
    if expected and (not x_api_key or (x_api_key or "").strip() != expected):
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")
    return run_optimization(body)
