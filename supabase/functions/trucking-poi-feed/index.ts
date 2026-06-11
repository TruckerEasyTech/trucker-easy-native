// GET /functions/v1/trucking-poi-feed?lat=&lon=&radius_km=
// Aggregates official trucking POI signals (Road511 → state 511/DOT/NBI) and optional NextBillion browse.
// Keys live in Edge secrets: ROAD511_API_KEY, NEXTBILLION_API_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  fetchRoad511Trucking,
  type Road511Place,
} from "../_shared/road511.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

type WeighSignal = {
  station_name: string;
  latitude: number;
  longitude: number;
  status: string;
  updated_at: string;
  source: string;
};

type ParkingSignal = {
  location_name: string;
  latitude: number;
  longitude: number;
  available_slots: number | null;
  total_slots: number | null;
  updated_at: string;
  source: string;
};

type PlaceRow = Road511Place;

async function fetchNextBillionBrowse(
  apiKey: string,
  lat: number,
  lon: number,
): Promise<PlaceRow[]> {
  const places: PlaceRow[] = [];
  const categories = "truck_stop,fuel,rest_area,truck_parking,weigh_station";
  const url = new URL("https://api.nextbillion.io/browse");
  url.searchParams.set("at", `${lat},${lon}`);
  url.searchParams.set("categories", categories);
  url.searchParams.set("limit", "40");
  url.searchParams.set("key", apiKey);
  const resp = await fetch(url.toString(), { headers: { Accept: "application/json" } });
  if (!resp.ok) {
    console.warn(`NextBillion browse: HTTP ${resp.status}`);
    return places;
  }
  const json = await resp.json();
  const items = (json.items ?? []) as Array<Record<string, unknown>>;
  for (const item of items) {
    const title = String(item.title ?? item.name ?? "Truck place");
    const pos = item.position as Record<string, number> | undefined;
    const latP = pos?.lat ?? (item as { lat?: number }).lat;
    const lonP = pos?.lng ?? pos?.lon ?? (item as { lng?: number }).lng;
    if (!Number.isFinite(latP) || !Number.isFinite(lonP)) continue;
    const id = String(item.id ?? `nb-${latP}-${lonP}`);
    const cats = ((item.categories ?? []) as Array<Record<string, string>>)
      .map((c) => (c.name ?? c.id ?? "").toLowerCase())
      .join(" ");
    let poiType = "truck_stop";
    if (cats.includes("weigh") || cats.includes("scale")) poiType = "weigh_station";
    else if (cats.includes("rest")) poiType = "rest_area";
    else if (cats.includes("fuel")) poiType = "fuel";
    places.push({
      external_id: id,
      external_source: "nextbillion",
      poi_type: poiType,
      name: title,
      lat: latP!,
      lon: lonP!,
      has_shower: cats.includes("shower"),
      amenities: [],
      status_open: null,
      parking_available: null,
      parking_total: null,
    });
  }
  return places;
}

async function upsertPlaces(
  supabase: ReturnType<typeof createClient>,
  rows: PlaceRow[],
): Promise<void> {
  if (!rows.length) return;
  const payload = rows.map((r) => ({
    osm_type: "external",
    osm_id: Math.abs(
      [...(`${r.external_source}:${r.external_id}`)].reduce(
        (h, c) => ((h << 5) - h + c.charCodeAt(0)) | 0,
        0,
      ),
    ),
    poi_type: r.poi_type,
    name: r.name,
    lat: r.lat,
    lon: r.lon,
    country_code: "US",
    tags: { amenities: r.amenities, source_feed: r.external_source },
    has_shower: r.has_shower,
    has_hgv_fuel: r.poi_type === "fuel" || r.poi_type === "truck_stop",
    has_weigh_station: r.poi_type === "weigh_station",
    source: r.external_source,
    external_source: r.external_source,
    external_id: r.external_id,
  }));
  const { error } = await supabase.from("poi_places").upsert(payload, {
    onConflict: "external_source,external_id,poi_type",
  });
  if (error) console.error("poi_places upsert:", error);
}

async function upsertOperational(
  supabase: ReturnType<typeof createClient>,
  places: PlaceRow[],
): Promise<void> {
  if (!places.length) return;
  const { data: existing } = await supabase
    .from("poi_places")
    .select("id, external_source, external_id, poi_type")
    .in(
      "external_id",
      places.map((p) => p.external_id),
    );
  if (!existing?.length) return;
  const idByKey = new Map(
    existing.map((r) => [`${r.external_source}:${r.external_id}:${r.poi_type}`, r.id]),
  );
  const ops: Array<Record<string, unknown>> = [];
  for (const p of places) {
    const poiId = idByKey.get(`${p.external_source}:${p.external_id}:${p.poi_type}`);
    if (!poiId) continue;
    const observed = new Date().toISOString();
    if (p.poi_type === "weigh_station" && p.status_open != null) {
      ops.push({
        poi_place_id: poiId,
        signal_type: "weigh_status",
        status_value: p.status_open ? "open" : "closed",
        source: p.external_source,
        confidence_score: p.external_source === "road511" ? 0.93 : 0.75,
        observed_at: observed,
      });
    }
    if (p.status_open != null) {
      ops.push({
        poi_place_id: poiId,
        signal_type: "site_open",
        status_value: p.status_open ? "open" : "closed",
        source: p.external_source,
        confidence_score: 0.9,
        observed_at: observed,
      });
    }
    if (p.parking_available != null || p.parking_total != null) {
      ops.push({
        poi_place_id: poiId,
        signal_type: "parking_availability",
        status_value: "available",
        available_slots: p.parking_available,
        total_slots: p.parking_total,
        source: p.external_source,
        confidence_score: 0.88,
        observed_at: observed,
      });
    }
  }
  if (ops.length) {
    const { error } = await supabase.from("poi_operational_status").insert(ops);
    if (error) console.error("poi_operational_status insert:", error);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const lat = parseFloat(url.searchParams.get("lat") ?? "");
  const lon = parseFloat(url.searchParams.get("lon") ?? "");
  const radiusKm = parseFloat(url.searchParams.get("radius_km") ?? "80");
  const persist = url.searchParams.get("persist") === "1";
  const jurisdiction = url.searchParams.get("jurisdiction") ?? undefined;

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return new Response(JSON.stringify({ error: "lat and lon required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const road511Key =
    Deno.env.get("ENABLE_ROAD511") === "true"
      ? (Deno.env.get("ROAD511_API_KEY") ?? "")
      : "";
  const nbKey = Deno.env.get("NEXTBILLION_API_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  let weigh_signals: WeighSignal[] = [];
  let parking_signals: ParkingSignal[] = [];
  let places: PlaceRow[] = [];
  const sources: string[] = [];

  let road511Jurisdictions: string[] = [];

  try {
    if (road511Key) {
      const r511 = await fetchRoad511Trucking(
        road511Key,
        lat,
        lon,
        radiusKm,
        jurisdiction,
      );
      weigh_signals.push(...r511.weigh);
      parking_signals.push(...r511.parking);
      places.push(...r511.places);
      road511Jurisdictions = r511.jurisdictions;
      if (r511.weigh.length || r511.parking.length || r511.places.length) {
        sources.push("road511");
      }
    }
    if (nbKey) {
      const nb = await fetchNextBillionBrowse(nbKey, lat, lon);
      places.push(...nb);
      sources.push("nextbillion");
    }
  } catch (e) {
    console.error("trucking-poi-feed fetch error:", e);
  }

  // De-dupe places within 150m
  const deduped: PlaceRow[] = [];
  for (const p of places) {
    if (
      deduped.some(
        (d) =>
          haversineKm(d.lat, d.lon, p.lat, p.lon) < 0.15 &&
          d.poi_type === p.poi_type,
      )
    ) {
      continue;
    }
    deduped.push(p);
  }
  places = deduped;

  if (persist && supabaseUrl && serviceKey && places.length) {
    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });
    await upsertPlaces(supabase, places);
    await upsertOperational(supabase, places);
  }

  const body = JSON.stringify({
    sources,
    weigh_signals,
    parking_signals,
    places,
    meta: {
      jurisdictions: road511Jurisdictions,
      note:
        "Road511 requires jurisdiction on Free plan (auto-detected from lat/lon). NextBillion optional.",
    },
  });

  return new Response(body, {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=120",
    },
  });
});
