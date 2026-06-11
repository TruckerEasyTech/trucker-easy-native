"""TSP clássico (força bruta + Simulated Annealing) — Plano B sem D-Wave / Braket.

Usa a mesma métrica Haversine (km) que o resto do motor. O contrato HTTP (`/v1/optimize`)
continua a ser servido por `vrp_engine.run_optimization`; este módulo só devolve a ordem
dos IDs das paragens quando `USE_TSP_SA_SIMULATOR=1` no ambiente.
"""

from __future__ import annotations

import math
import random
from itertools import permutations


def _haversine_km(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dphi = math.radians(b_lat - a_lat)
    dlmb = math.radians(b_lng - a_lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(h)))


def _build_matrices(
    depot_lat: float,
    depot_lng: float,
    stops: list[tuple[str, float, float]],
) -> tuple[list[list[float]], list[float], list[float], list[str]]:
    """Devolve (d_cust, d_depot, d_to_depot, ids) com distâncias em km (igual a `_distance_matrix` no vrp_engine)."""
    n = len(stops)
    ids = [s[0] for s in stops]
    pts = [(depot_lat, depot_lng)] + [(s[1], s[2]) for s in stops]
    m = len(pts)
    dist = [[0.0] * m for _ in range(m)]
    for i in range(m):
        for j in range(m):
            if i != j:
                dist[i][j] = _haversine_km(pts[i][0], pts[i][1], pts[j][0], pts[j][1])
    d_depot = [dist[0][1 + j] for j in range(n)]
    d_to_depot = [dist[1 + j][0] for j in range(n)]
    d_cust = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                d_cust[i][j] = dist[1 + i][1 + j]
    return d_cust, d_depot, d_to_depot, ids


def _tour_cost_km(perm: list[int], d_cust: list[list[float]], d_depot: list[float], d_to_depot: list[float]) -> float:
    if not perm:
        return 0.0
    total = d_depot[perm[0]]
    for a, b in zip(perm, perm[1:]):
        total += d_cust[a][b]
    total += d_to_depot[perm[-1]]
    return total


def _brute_force_tsp(d_cust: list[list[float]], d_depot: list[float], d_to_depot: list[float], n: int) -> list[int]:
    best: list[int] | None = None
    best_c = float("inf")
    for p in permutations(range(n)):
        c = _tour_cost_km(list(p), d_cust, d_depot, d_to_depot)
        if c < best_c:
            best_c = c
            best = list(p)
    assert best is not None
    return best


def _simulated_annealing_tsp(
    d_cust: list[list[float]],
    d_depot: list[float],
    d_to_depot: list[float],
    n: int,
    *,
    max_iters: int,
) -> list[int]:
    if n <= 1:
        return list(range(n))
    current = list(range(n))
    random.shuffle(current)
    current_c = _tour_cost_km(current, d_cust, d_depot, d_to_depot)
    best = current.copy()
    best_c = current_c
    temperature = 1000.0
    cooling_rate = 0.995
    min_temperature = 1.0
    it = 0
    while temperature > min_temperature and it < max_iters:
        it += 1
        if n < 2:
            break
        i, j = random.sample(range(n), 2)
        new_route = current.copy()
        new_route[i], new_route[j] = new_route[j], new_route[i]
        new_c = _tour_cost_km(new_route, d_cust, d_depot, d_to_depot)
        if new_c < current_c or random.random() < math.exp(-(new_c - current_c) / max(temperature, 1e-9)):
            current = new_route
            current_c = new_c
            if current_c < best_c:
                best = current.copy()
                best_c = current_c
        temperature *= cooling_rate
    return best


def classical_tsp_customer_order(
    depot_lat: float,
    depot_lng: float,
    stops: list[tuple[str, float, float]],
) -> list[str] | None:
    """Ordem fechada depot → paragens → depot minimizando km Haversine (sem capacidade; VRP capacitado fica no greedy do motor)."""
    if not stops:
        return []
    n = len(stops)
    d_cust, d_depot, d_to_depot, ids = _build_matrices(depot_lat, depot_lng, stops)
    if n == 1:
        return [ids[0]]
    brute_max = 8
    if n <= brute_max:
        perm = _brute_force_tsp(d_cust, d_depot, d_to_depot, n)
    else:
        max_iters = min(500_000, max(30_000, 15_000 * n))
        perm = _simulated_annealing_tsp(d_cust, d_depot, d_to_depot, n, max_iters=max_iters)
    return [ids[i] for i in perm]
