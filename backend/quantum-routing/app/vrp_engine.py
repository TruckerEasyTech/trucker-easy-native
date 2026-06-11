"""Construção CQM (TSP capacitado em variáveis de atribuição) + amostragem Leap Hybrid ou fallback greedy."""

from __future__ import annotations

import math
import os
from typing import NamedTuple

from .contracts import LocationPoint, OptimizationMetrics, OptimizeRequest, OptimizeResponse


class _Customer(NamedTuple):
    idx: int
    point: LocationPoint


def haversine_km(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dphi = math.radians(b_lat - a_lat)
    dlmb = math.radians(b_lng - a_lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def _closed_tour_haversine_km(depot: LocationPoint, visits: list[LocationPoint]) -> float:
    if not visits:
        return 0.0
    total = haversine_km(depot.lat, depot.lng, visits[0].lat, visits[0].lng)
    for i in range(len(visits) - 1):
        a, b = visits[i], visits[i + 1]
        total += haversine_km(a.lat, a.lng, b.lat, b.lng)
    last = visits[-1]
    total += haversine_km(last.lat, last.lng, depot.lat, depot.lng)
    return total


def _optimization_metrics(
    depot: LocationPoint,
    customers: list[_Customer],
    ordered_ids: list[str],
    locations_by_id: dict[str, LocationPoint],
) -> OptimizationMetrics | None:
    baseline = [c.point for c in customers]
    if not baseline:
        return None
    optimized: list[LocationPoint] = []
    for oid in ordered_ids:
        p = locations_by_id.get(oid)
        if p is None or p.id == depot.id:
            continue
        optimized.append(p)
    if len(optimized) != len(baseline):
        return None
    kb = _closed_tour_haversine_km(depot, baseline)
    ko = _closed_tour_haversine_km(depot, optimized)
    saved = max(0.0, kb - ko)
    return OptimizationMetrics(
        approx_km_baseline_manual_order=round(kb, 3),
        approx_km_optimized_order=round(ko, 3),
        approx_km_saved=round(saved, 3),
    )


def _split_depot(locations: list[LocationPoint]) -> tuple[LocationPoint, list[_Customer]]:
    depot = next((p for p in locations if p.id.lower() == "depot"), locations[0])
    stops = [p for p in locations if p.id != depot.id]
    customers = [_Customer(k, p) for k, p in enumerate(stops)]
    return depot, customers


def _distance_matrix(depot: LocationPoint, customers: list[_Customer]) -> tuple[list[list[float]], list[float], list[float]]:
    n = len(customers)
    if n == 0:
        return [], [], []
    pts = [depot] + [c.point for c in customers]
    m = len(pts)
    dist = [[0.0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            if i != j:
                dist[i][j] = haversine_km(pts[i].lat, pts[i].lng, pts[j].lat, pts[j].lng)
    d_depot = [dist[0][1 + j] for j in range(n)]
    d_to_depot = [dist[1 + j][0] for j in range(n)]
    d_cust = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                d_cust[i][j] = dist[1 + i][1 + j]
    return d_cust, d_depot, d_to_depot


def _greedy_nn(depot: LocationPoint, customers: list[_Customer], capacity: float) -> list[str]:
    if not customers:
        return [depot.id]
    remaining = {c.idx: c for c in customers}
    ordered_ids: list[str] = []
    cur_lat, cur_lng = depot.lat, depot.lng
    load = 0.0
    while remaining:
        best_id: int | None = None
        best_d = float("inf")
        for c in remaining.values():
            if load + c.point.demand > capacity + 1e-9:
                continue
            d = haversine_km(cur_lat, cur_lng, c.point.lat, c.point.lng)
            if d < best_d:
                best_d = d
                best_id = c.idx
        if best_id is None:
            c = next(iter(remaining.values()))
            ordered_ids.append(c.point.id)
            load += c.point.demand
            del remaining[c.idx]
            cur_lat, cur_lng = c.point.lat, c.point.lng
            continue
        c = remaining[best_id]
        ordered_ids.append(c.point.id)
        load += c.point.demand
        cur_lat, cur_lng = c.point.lat, c.point.lng
        del remaining[best_id]
    return ordered_ids


def _cluster_for_vehicles(depot: LocationPoint, customers: list[_Customer], n_vehicles: int, capacity: float) -> list[list[str]]:
    if n_vehicles <= 1:
        return [_greedy_nn(depot, customers, capacity)]
    chunk = max(1, math.ceil(len(customers) / n_vehicles))
    routes: list[list[str]] = []
    for v in range(n_vehicles):
        slice_c = customers[v * chunk : (v + 1) * chunk]
        if not slice_c:
            continue
        routes.append(_greedy_nn(depot, slice_c, capacity))
    return routes if routes else [_greedy_nn(depot, customers, capacity)]


def _build_tsp_assignment_cqm(
    n: int,
    d_cust: list[list[float]],
    d_depot: list[float],
    d_to_depot: list[float],
):
    from dimod import Binary, ConstrainedQuadraticModel

    cqm = ConstrainedQuadraticModel()
    x = [[Binary(f"x_{i}_{k}") for k in range(n)] for i in range(n)]

    obj = sum(d_depot[j] * x[j][0] for j in range(n))
    for k in range(1, n):
        obj += sum(d_cust[i][j] * x[i][k - 1] * x[j][k] for i in range(n) for j in range(n) if i != j)
    obj += sum(d_to_depot[i] * x[i][n - 1] for i in range(n))
    cqm.set_objective(obj)

    for i in range(n):
        cqm.add_constraint(sum(x[i]) == 1, label=f"visit_once_{i}")
    for k in range(n):
        cqm.add_constraint(sum(x[i][k] for i in range(n)) == 1, label=f"slot_once_{k}")
    return cqm, x


def _dwave_api_token_set() -> bool:
    return bool(os.environ.get("DWAVE_API_TOKEN", "").strip())


def _braket_env_configured() -> bool:
    """Braket D-Wave: S3 + device ARN + flag explícita (credenciais AWS via env ou IAM role)."""
    if os.environ.get("USE_AMAZON_BRAKET", "").lower() not in ("1", "true", "yes"):
        return False
    bucket = os.environ.get("BRAKET_RESULTS_S3_BUCKET", "").strip()
    arn = os.environ.get("BRAKET_DWAVE_DEVICE_ARN", "").strip()
    return bool(bucket and arn)


def _assignment_feasible(sample: dict, n: int) -> bool:
    for i in range(n):
        s = sum(int(round(float(sample.get(f"x_{i}_{k}", 0)))) for k in range(n))
        if s != 1:
            return False
    for k in range(n):
        s = sum(int(round(float(sample.get(f"x_{i}_{k}", 0)))) for i in range(n))
        if s != 1:
            return False
    return True


def _build_tsp_assignment_bqm(
    n: int,
    d_cust: list[list[float]],
    d_depot: list[float],
    d_to_depot: list[float],
    penalty: float,
):
    from dimod import BinaryQuadraticModel

    bqm = BinaryQuadraticModel(vartype="BINARY")
    labels = [[f"x_{i}_{k}" for k in range(n)] for i in range(n)]
    for i in range(n):
        for k in range(n):
            bqm.add_variable(labels[i][k], 0.0)

    for j in range(n):
        bqm.add_linear(labels[j][0], d_depot[j])

    for k in range(1, n):
        for i in range(n):
            for j in range(n):
                if i == j:
                    continue
                bqm.add_quadratic(labels[i][k - 1], labels[j][k], d_cust[i][j])

    for i in range(n):
        bqm.add_linear(labels[i][n - 1], d_to_depot[i])

    for i in range(n):
        for k in range(n):
            bqm.add_linear(labels[i][k], -penalty)
        for a in range(n):
            for b in range(a + 1, n):
                bqm.add_quadratic(labels[i][a], labels[i][b], 2.0 * penalty)
        bqm.offset += penalty

    for k in range(n):
        for i in range(n):
            bqm.add_linear(labels[i][k], -penalty)
        for a in range(n):
            for b in range(a + 1, n):
                bqm.add_quadratic(labels[a][k], labels[b][k], 2.0 * penalty)
        bqm.offset += penalty

    return bqm


def _penalty_scale(n: int, d_cust: list[list[float]], d_depot: list[float], d_to_depot: list[float]) -> float:
    mx = 1.0
    for row in d_cust:
        mx = max(mx, max(row) if row else 0.0)
    mx = max(mx, max(d_depot) if d_depot else 0.0, max(d_to_depot) if d_to_depot else 0.0)
    return max(80.0, 5.0 * mx * n)


def _solve_braket_dwave_bqm(depot: LocationPoint, customers: list[_Customer]) -> list[str] | None:
    """Envia o mesmo BQM TSP-atribuição ao D-Wave via Amazon Braket (QPU), se dependências e env estiverem OK."""
    if not _braket_env_configured():
        return None
    n = len(customers)
    if n == 0:
        return []
    if n == 1:
        return [customers[0].point.id]
    try:
        from braket.ocean_plugin import BraketDWaveSampler
    except ImportError:
        return None

    d_cust, d_depot, d_to_depot = _distance_matrix(depot, customers)
    p = _penalty_scale(n, d_cust, d_depot, d_to_depot)
    bqm = _build_tsp_assignment_bqm(n, d_cust, d_depot, d_to_depot, p)

    labels = sorted(bqm.variables, key=lambda s: (len(str(s)), str(s)))
    vti = {v: i for i, v in enumerate(labels)}
    relabeled = bqm.relabel_variables(vti, inplace=False)
    qubo, _off = relabeled.to_qubo()
    inv = {i: v for v, i in vti.items()}

    bucket = os.environ["BRAKET_RESULTS_S3_BUCKET"].strip()
    prefix = os.environ.get("BRAKET_RESULTS_S3_PREFIX", "truckereasy-braket/").strip()
    arn = os.environ["BRAKET_DWAVE_DEVICE_ARN"].strip()
    num_reads = int(os.environ.get("BRAKET_NUM_READS", "50"))

    sampler = BraketDWaveSampler(s3_destination_folder=(bucket, prefix), device_arn=arn)
    sampleset = sampler.sample_qubo(qubo, num_reads=num_reads, answer_mode="HISTOGRAM")
    rows = list(sampleset.data(["sample", "energy"]))
    rows.sort(key=lambda s: float(s.energy))
    for rec in rows:
        sample_int: dict[int, int] = {}
        for k, v in rec.sample.items():
            ki = int(k) if not isinstance(k, int) else k
            sample_int[ki] = int(round(float(v)))
        try:
            sample = {str(inv[ki]): v for ki, v in sample_int.items()}
        except KeyError:
            continue
        if _assignment_feasible(sample, n):
            return _decode_tsp_sample(sample, n, customers)
    return None


def _solve_neal_sa(depot: LocationPoint, customers: list[_Customer]) -> list[str] | None:
    n = len(customers)
    if n == 0:
        return []
    if n == 1:
        return [customers[0].point.id]
    try:
        import neal
    except ImportError:
        return None
    d_cust, d_depot, d_to_depot = _distance_matrix(depot, customers)
    p = _penalty_scale(n, d_cust, d_depot, d_to_depot)
    bqm = _build_tsp_assignment_bqm(n, d_cust, d_depot, d_to_depot, p)
    sampler = neal.SimulatedAnnealingSampler()
    sampleset = sampler.sample(bqm, num_reads=80, num_sweeps=2000)
    rows = list(sampleset.data(["sample", "energy"]))
    rows.sort(key=lambda s: float(s.energy))
    for rec in rows:
        sample = {k: int(round(float(v))) for k, v in rec.sample.items()}
        if _assignment_feasible(sample, n):
            return _decode_tsp_sample(sample, n, customers)
    return None


def _decode_tsp_sample(sample: dict, n: int, customers: list[_Customer]) -> list[str]:
    seq: list[tuple[int, str]] = []
    for k in range(n):
        for i in range(n):
            if sample.get(f"x_{i}_{k}", 0) == 1:
                seq.append((k, customers[i].point.id))
                break
    seq.sort(key=lambda t: t[0])
    return [s[1] for s in seq]


def _solve_hybrid_cqm(depot: LocationPoint, customers: list[_Customer], time_limit: int = 60) -> list[str] | None:
    n = len(customers)
    if n == 0:
        return []
    if n == 1:
        return [customers[0].point.id]
    d_cust, d_depot, d_to_depot = _distance_matrix(depot, customers)
    cqm, _ = _build_tsp_assignment_cqm(n, d_cust, d_depot, d_to_depot)
    try:
        from dwave.system import LeapHybridCQMSampler
    except ImportError:
        return None
    sampler = LeapHybridCQMSampler()
    sampleset = sampler.sample_cqm(cqm, time_limit=time_limit, label="Trucker Easy - Route Opt")
    feasible = sampleset.filter(lambda row: row.is_feasible)
    if len(feasible) == 0:
        return None
    best = feasible.first
    return _decode_tsp_sample(best.sample, n, customers)


MAX_CQM_CUSTOMERS = 16


def _env_flag(name: str, default: str = "0") -> bool:
    return os.environ.get(name, default).lower() in ("1", "true", "yes")


def _route_solver_mode() -> str:
    """Production default: greedy. Set ROUTE_OPT_SOLVER=hybrid + DISABLE_DWAVE=0 for D-Wave labs."""
    return os.environ.get("ROUTE_OPT_SOLVER", "greedy").strip().lower()


def _use_greedy_fast_path() -> bool:
    mode = _route_solver_mode()
    if mode == "greedy":
        return True
    if mode == "hybrid":
        if _env_flag("DISABLE_DWAVE", "1"):
            return not _env_flag("USE_TSP_SA_SIMULATOR")
        return False
    return True


def _solve_stop_order_production(
    req: OptimizeRequest,
    depot: LocationPoint,
    customers: list[_Customer],
) -> tuple[list[str], str, str | None]:
    """Greedy nearest-neighbour (default) or optional classical TSP SA — no D-Wave / Braket."""
    msg: str | None = None
    if _env_flag("USE_TSP_SA_SIMULATOR") and len(customers) <= MAX_CQM_CUSTOMERS:
        try:
            from .quantum_simulator import classical_tsp_customer_order

            q_sa = classical_tsp_customer_order(
                depot.lat,
                depot.lng,
                [(c.point.id, c.point.lat, c.point.lng) for c in customers],
            )
            if q_sa is not None and len(q_sa) == len(customers):
                return q_sa, "simulated_quantum_annealing", None
        except Exception as exc:  # noqa: BLE001
            msg = f"classical TSP SA failed: {exc!s}; used greedy_nn."

    ordered = _greedy_nn(depot, customers, req.vehicle_capacity)
    if req.solver_type == "hybrid_cqm" and len(customers) > MAX_CQM_CUSTOMERS:
        cap_msg = f"Customer count {len(customers)} > {MAX_CQM_CUSTOMERS}; used greedy_nn."
        msg = cap_msg if not msg else f"{msg} {cap_msg}"
    return ordered, "greedy_nn", msg


def _audit(req: OptimizeRequest) -> dict[str, str | None]:
    return {"trip_id": req.trip_id, "load_id": req.load_id}


def run_optimization(req: OptimizeRequest) -> OptimizeResponse:
    depot, customers = _split_depot(req.locations)
    total_demand = sum(c.point.demand for c in customers)
    if total_demand > req.vehicle_capacity + 1e-9:
        return OptimizeResponse(
            request_id=req.request_id,
            status="error",
            solver_used="none",
            ordered_location_ids=[],
            routes=[],
            message="Total demand exceeds vehicle_capacity for this single-leg model.",
            metrics=None,
            **_audit(req),
        )

    if req.num_vehicles > 1:
        routes = _cluster_for_vehicles(depot, customers, req.num_vehicles, req.vehicle_capacity)
        flat = [rid for r in routes for rid in r]
        return OptimizeResponse(
            request_id=req.request_id,
            status="fallback",
            solver_used="greedy_cluster",
            ordered_location_ids=flat,
            routes=[[depot.id] + r + [depot.id] for r in routes],
            message="num_vehicles>1 uses greedy clustering until MVRP CQM is wired.",
            metrics=None,
            **_audit(req),
        )

    if _use_greedy_fast_path():
        ordered, solver_used, msg = _solve_stop_order_production(req, depot, customers)
        route_loop = [depot.id] + ordered + [depot.id]
        by_id = {p.id: p for p in req.locations}
        metrics = _optimization_metrics(depot, customers, ordered, by_id)
        print(f"[route-opt] Solver: {solver_used} (production path)", flush=True)
        return OptimizeResponse(
            request_id=req.request_id,
            status="ok",
            solver_used=solver_used,
            ordered_location_ids=ordered,
            routes=[route_loop],
            message=msg,
            metrics=metrics,
            **_audit(req),
        )

    disable_dwave = _env_flag("DISABLE_DWAVE", "1")
    use_tsp_sa_simulator = _env_flag("USE_TSP_SA_SIMULATOR")

    use_quantum = req.solver_type == "hybrid_cqm" and len(customers) <= MAX_CQM_CUSTOMERS
    if disable_dwave and not use_tsp_sa_simulator:
        use_quantum = False

    ordered: list[str] = []
    solver_used = "greedy_nn"
    status: str = "ok"
    msg: str | None = None

    if use_quantum:
        q: list[str] | None = None
        notes: list[str] = []
        quantum_source: str | None = None  # "braket" | "leap" | "classical_sa"

        if _braket_env_configured():
            try:
                qb = _solve_braket_dwave_bqm(depot, customers)
                if qb is not None and len(qb) == len(customers):
                    q = qb
                    quantum_source = "braket"
            except Exception as exc:  # noqa: BLE001
                notes.append(f"Braket D-Wave error: {exc!s}")

        if q is None and _dwave_api_token_set():
            try:
                ql = _solve_hybrid_cqm(depot, customers)
                if ql is not None and len(ql) == len(customers):
                    q = ql
                    quantum_source = "leap"
                elif ql is None:
                    notes.append("LeapHybrid returned no feasible tour")
            except Exception as exc:  # noqa: BLE001
                notes.append(f"LeapHybrid error: {exc!s}")

        if q is None and use_tsp_sa_simulator:
            try:
                from .quantum_simulator import classical_tsp_customer_order

                q_sa = classical_tsp_customer_order(
                    depot.lat,
                    depot.lng,
                    [(c.point.id, c.point.lat, c.point.lng) for c in customers],
                )
                if q_sa is not None and len(q_sa) == len(customers):
                    q = q_sa
                    quantum_source = "classical_sa"
            except Exception as exc:  # noqa: BLE001
                notes.append(f"classical TSP SA error: {exc!s}")

        if q is not None and len(q) == len(customers):
            ordered = q
            if quantum_source == "braket":
                solver_used = "amazon_braket_dwave"
            elif quantum_source == "leap":
                solver_used = "leap_hybrid_cqm"
            elif quantum_source == "classical_sa":
                solver_used = "simulated_quantum_annealing"
            else:
                solver_used = "leap_hybrid_cqm"
            status = "ok"
            msg = None
        else:
            qn = None
            if not disable_dwave:
                qn = _solve_neal_sa(depot, customers)
            if qn is not None and len(qn) == len(customers):
                ordered = qn
                solver_used = "dwave_neal_sa"
                status = "fallback" if (_dwave_api_token_set() or _braket_env_configured()) else "ok"
                if not _dwave_api_token_set() and not _braket_env_configured():
                    msg = "DWAVE_API_TOKEN unset; used dwave-neal Simulated Annealing locally."
                else:
                    prefix = "; ".join(notes) if notes else "Quantum backends unavailable or incomplete."
                    msg = f"{prefix} Used dwave-neal Simulated Annealing locally."
            else:
                ordered = _greedy_nn(depot, customers, req.vehicle_capacity)
                solver_used = "greedy_nn"
                status = "fallback"
                if disable_dwave:
                    neal_note = "DISABLE_DWAVE=1 (Neal skipped); used greedy_nn."
                else:
                    neal_note = "Neal SA found no feasible assignment; used greedy_nn."
                msg = "; ".join(notes + [neal_note]) if notes else neal_note
    else:
        ordered = _greedy_nn(depot, customers, req.vehicle_capacity)
        if req.solver_type == "hybrid_cqm" and len(customers) > MAX_CQM_CUSTOMERS:
            msg = f"Customer count {len(customers)} > {MAX_CQM_CUSTOMERS}; used greedy_nn."

    route_loop = [depot.id] + ordered + [depot.id]
    by_id = {p.id: p for p in req.locations}
    metrics = _optimization_metrics(depot, customers, ordered, by_id)
    print(f"[route-opt] Solver: {solver_used}", flush=True)
    return OptimizeResponse(
        request_id=req.request_id,
        status=status,
        solver_used=solver_used,
        ordered_location_ids=ordered,
        routes=[route_loop],
        message=msg,
        metrics=metrics,
        **_audit(req),
    )
