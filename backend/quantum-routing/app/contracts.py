"""Contrato JSON entre o app Swift e este serviço (iOS não precisa de semântica quântica)."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class LocationPoint(BaseModel):
    id: str
    lat: float
    lng: float
    demand: float = 0.0
    time_window_start: str | None = Field(
        default=None,
        description="ISO-8601 opcional; reservado para VRP com janelas (solver atual ignora na função objetivo).",
    )
    time_window_end: str | None = Field(
        default=None,
        description="ISO-8601 opcional; idem.",
    )


class OptimizationMetrics(BaseModel):
    """Proxy de quilometragem para testes de campo: percurso fechado (depot → … → depot) em linha recta (Haversine).

    Não substitui odómetro nem distância de estrada; correlaciona com o ganho do solver na mesma métrica que o CQM optimiza.
    """

    approx_km_baseline_manual_order: float = Field(
        ...,
        description="Ordem manual = ordem das paragens no JSON recebido (excl. depot).",
    )
    approx_km_optimized_order: float = Field(..., description="Ordem devolvida pelo solver.")
    approx_km_saved: float = Field(..., ge=0, description="max(0, baseline − optimized) em km.")
    methodology: str = "closed_tour_haversine_km"


class OptimizeRequest(BaseModel):
    request_id: str
    fleet_id: str = ""
    vehicle_capacity: float = Field(ge=0, description="Capacidade do veículo (mesma unidade que demand).")
    locations: list[LocationPoint] = Field(min_length=2)
    solver_type: Literal["hybrid_cqm", "greedy"] = "hybrid_cqm"
    num_vehicles: int = Field(default=1, ge=1, le=8, description="MVP: apenas 1 veículo usa CQM; >1 devolve greedy por veículo.")
    trip_id: str | None = Field(default=None, description="UUID SwiftData Trip — auditoria / métricas.")
    load_id: str | None = Field(default=None, description="ID da carga (ex. Supabase dispatched_loads).")


class OptimizeResponse(BaseModel):
    request_id: str
    status: Literal["ok", "error", "fallback"]
    solver_used: str
    ordered_location_ids: list[str]
    routes: list[list[str]] = Field(default_factory=list, description="Por veículo: depot ... depot")
    message: str | None = None
    trip_id: str | None = None
    load_id: str | None = None
    metrics: OptimizationMetrics | None = Field(
        default=None,
        description="Poupança aproximada em km (Haversine) vs ordem manual do pedido.",
    )
