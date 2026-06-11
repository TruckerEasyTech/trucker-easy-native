// Supabase Edge Function: GET /functions/v1/ops-feed?lat=&lon=&radius_km=
// Response shape must match iOS `PartnerOperationalFeedResponse` in OperationalFeedService.swift

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { fetchRoad511Trucking } from "../_shared/road511.ts";

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
  const jurisdiction = url.searchParams.get("jurisdiction") ?? undefined;

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return new Response(
      JSON.stringify({ error: "Query params lat and lon are required (finite numbers)" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const maxKm = Number.isFinite(radiusKm) && radiusKm > 0 ? radiusKm : 80;

  const road511Key =
    Deno.env.get("ENABLE_ROAD511") === "true"
      ? (Deno.env.get("ROAD511_API_KEY") ?? "")
      : "";
  let road511Weigh: Awaited<ReturnType<typeof fetchRoad511Trucking>>["weigh"] = [];
  let road511Parking: Awaited<ReturnType<typeof fetchRoad511Trucking>>["parking"] = [];
  if (road511Key) {
    try {
      const r511 = await fetchRoad511Trucking(
        road511Key,
        lat,
        lon,
        maxKm,
        jurisdiction,
      );
      road511Weigh = r511.weigh;
      road511Parking = r511.parking;
    } catch (e) {
      console.error("Road511 fetch:", e);
    }
  }

  const [
    { data: roadRows, error: roadErr },
    { data: weighRows, error: weighErr },
    { data: parkingRows, error: parkingErr },
    { data: govOpsRows, error: govOpsErr },
  ] =
    await Promise.all([
      supabase
        .from("road_reports")
        .select(
          "id, driver_id, report_type, latitude, longitude, location_name, confirmations, reported_at",
        )
        .order("reported_at", { ascending: false })
        .limit(500),
      supabase
        .from("weigh_station_reports")
        .select(
          "id, station_name, driver_id, status, latitude, longitude, updated_at",
        )
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("truck_stop_parking_reports")
        .select(
          "id, location_name, latitude, longitude, status, available_slots, total_slots, reported_at",
        )
        .order("reported_at", { ascending: false })
        .limit(500),
      supabase
        .from("poi_operational_status")
        .select(
          "signal_type, status_value, available_slots, total_slots, source, observed_at, poi_places!inner(id, name, lat, lon, poi_type)",
        )
        .in("signal_type", ["weigh_status", "site_open", "parking_availability"])
        .order("observed_at", { ascending: false })
        .limit(800),
    ]);

  if (roadErr) {
    console.error("road_reports:", roadErr);
  }
  if (weighErr) {
    console.error("weigh_station_reports:", weighErr);
  }
  if (parkingErr) {
    console.error("truck_stop_parking_reports:", parkingErr);
  }
  if (govOpsErr) {
    console.error("poi_operational_status:", govOpsErr);
  }

  const parkingTypes = new Set([
    "parkingfull",
    "parking",
    "parking_full",
    "truckparking",
  ]);

  const structuredParkingSignals = (parkingRows ?? [])
    .filter((r) => {
      const la = r.latitude as number;
      const lo = r.longitude as number;
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
      return haversineKm(lat, lon, la, lo) <= maxKm;
    })
    .map((r) => {
      const status = String(r.status ?? "").toLowerCase();
      const inferredTotal = (r.total_slots as number | null) ?? 50;
      const inferredAvailable =
        (r.available_slots as number | null) ??
        (status === "full" ? 0 : status === "many" ? Math.round(inferredTotal * 0.65) : Math.round(inferredTotal * 0.2));
      return {
        location_name: (r.location_name as string) ?? "Parking report",
        latitude: r.latitude as number,
        longitude: r.longitude as number,
        available_slots: inferredAvailable,
        total_slots: inferredTotal,
        updated_at: r.reported_at as string,
      };
    });

  const legacyParkingSignals = (roadRows ?? [])
    .filter((r) => {
      const t = String(r.report_type ?? "").toLowerCase();
      return parkingTypes.has(t) || t.includes("parking");
    })
    .filter((r) => {
      const la = r.latitude as number;
      const lo = r.longitude as number;
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
      return haversineKm(lat, lon, la, lo) <= maxKm;
    })
    .map((r) => ({
      location_name: (r.location_name as string) ?? "Parking report",
      latitude: r.latitude as number,
      longitude: r.longitude as number,
      available_slots: null as number | null,
      total_slots: null as number | null,
      updated_at: r.reported_at as string,
    }));

  const parking_signals = [...structuredParkingSignals, ...legacyParkingSignals];

  const crowd_weigh_signals = (weighRows ?? [])
    .filter((w) => {
      const la = w.latitude as number | null;
      const lo = w.longitude as number | null;
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
      return haversineKm(lat, lon, la!, lo!) <= maxKm;
    })
    .map((w) => ({
      station_name: String(w.station_name ?? "Weigh station"),
      latitude: w.latitude as number,
      longitude: w.longitude as number,
      status: String(w.status ?? "monitoring").toLowerCase(),
      updated_at: (w.updated_at ?? w.created_at) as string,
      source: "crowd",
    }));

  const gov_weigh_signals = (govOpsRows ?? [])
    .filter((row) => {
      const place = row.poi_places as Record<string, unknown> | null;
      if (!place) return false;
      const la = place.lat as number;
      const lo = place.lon as number;
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
      if (haversineKm(lat, lon, la, lo) > maxKm) return false;
      const sig = String(row.signal_type ?? "");
      return sig === "weigh_status" || (sig === "site_open" && place.poi_type === "weigh_station");
    })
    .map((row) => {
      const place = row.poi_places as Record<string, unknown>;
      const raw = String(row.status_value ?? "").toLowerCase();
      const status = raw === "open" ? "open" : raw === "closed" ? "closed" : "monitoring";
      return {
        station_name: String(place.name ?? "Weigh station"),
        latitude: place.lat as number,
        longitude: place.lon as number,
        status,
        updated_at: row.observed_at as string,
        source: String(row.source ?? "government"),
      };
    });

  const gov_parking_signals = (govOpsRows ?? [])
    .filter((row) => String(row.signal_type ?? "") === "parking_availability")
    .filter((row) => {
      const place = row.poi_places as Record<string, unknown> | null;
      if (!place) return false;
      const la = place.lat as number;
      const lo = place.lon as number;
      if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
      return haversineKm(lat, lon, la, lo) <= maxKm;
    })
    .map((row) => {
      const place = row.poi_places as Record<string, unknown>;
      return {
        location_name: String(place.name ?? "Truck parking"),
        latitude: place.lat as number,
        longitude: place.lon as number,
        available_slots: (row.available_slots as number | null) ?? null,
        total_slots: (row.total_slots as number | null) ?? null,
        updated_at: row.observed_at as string,
        source: String(row.source ?? "government"),
      };
    });

  const road511_weigh_signals = road511Weigh.map((w) => ({
    station_name: w.station_name,
    latitude: w.latitude,
    longitude: w.longitude,
    status: w.status,
    updated_at: w.updated_at,
    source: w.source,
  }));

  const road511_parking_signals = road511Parking.map((p) => ({
    location_name: p.location_name,
    latitude: p.latitude,
    longitude: p.longitude,
    available_slots: p.available_slots,
    total_slots: p.total_slots,
    updated_at: p.updated_at,
    source: p.source,
  }));

  // Road511 (511/DOT/NBI) → DB gov ops → crowd reports.
  const weigh_signals = [
    ...road511_weigh_signals,
    ...gov_weigh_signals,
    ...crowd_weigh_signals,
  ];
  const parking_with_gov = [
    ...road511_parking_signals,
    ...gov_parking_signals,
    ...parking_signals,
  ];

  const body = JSON.stringify({
    parking_signals: parking_with_gov,
    weigh_signals,
  });

  return new Response(body, {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=60",
    },
  });
});
