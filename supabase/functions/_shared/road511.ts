/** Road511 helpers — Free plan requires ?jurisdiction=XX (max 2 per request). */

export type Road511Row = Record<string, unknown>;

export type Road511Weigh = {
  station_name: string;
  latitude: number;
  longitude: number;
  status: string;
  updated_at: string;
  source: string;
};

export type Road511Parking = {
  location_name: string;
  latitude: number;
  longitude: number;
  available_slots: number | null;
  total_slots: number | null;
  updated_at: string;
  source: string;
};

export type Road511Place = {
  external_id: string;
  external_source: string;
  poi_type: string;
  name: string;
  lat: number;
  lon: number;
  has_shower: boolean;
  amenities: string[];
  status_open: boolean | null;
  parking_available: number | null;
  parking_total: number | null;
};

// Bounding boxes from backend/osm-poi-ingest/regions_us_ca.json
const JURISDICTION_BOXES: Array<{
  id: string;
  code: string;
  south: number;
  west: number;
  north: number;
  east: number;
}> = [
  { id: "us-tx", code: "TX", south: 25.84, west: -106.65, north: 36.5, east: -93.51 },
  { id: "us-ca", code: "CA", south: 32.53, west: -124.41, north: 42.01, east: -114.13 },
  { id: "us-fl", code: "FL", south: 24.52, west: -87.63, north: 31.0, east: -80.03 },
  { id: "us-ny", code: "NY", south: 40.5, west: -79.76, north: 45.02, east: -71.86 },
  { id: "us-il", code: "IL", south: 36.97, west: -91.51, north: 42.51, east: -87.02 },
  { id: "us-oh", code: "OH", south: 38.4, west: -84.82, north: 42.33, east: -80.52 },
  { id: "us-pa", code: "PA", south: 39.72, west: -80.52, north: 42.27, east: -74.69 },
  { id: "us-ga", code: "GA", south: 30.36, west: -85.61, north: 35.0, east: -80.84 },
  { id: "us-nc", code: "NC", south: 33.84, west: -84.32, north: 36.59, east: -75.46 },
  { id: "us-az", code: "AZ", south: 31.33, west: -114.82, north: 37.0, east: -109.05 },
  { id: "us-wa", code: "WA", south: 45.54, west: -124.85, north: 49.0, east: -116.92 },
  { id: "us-co", code: "CO", south: 36.99, west: -109.06, north: 41.0, east: -102.04 },
  { id: "us-mn", code: "MN", south: 43.5, west: -97.24, north: 49.38, east: -89.53 },
  { id: "us-mi", code: "MI", south: 41.7, west: -90.42, north: 48.3, east: -82.41 },
  { id: "us-tn", code: "TN", south: 34.98, west: -90.31, north: 36.68, east: -81.65 },
  { id: "us-wi", code: "WI", south: 42.75, west: -92.9, north: 47.08, east: -86.25 },
  { id: "us-in", code: "IN", south: 37.77, west: -88.1, north: 41.76, east: -84.78 },
  { id: "us-mo", code: "MO", south: 35.99, west: -95.77, north: 40.61, east: -89.1 },
  { id: "us-va", code: "VA", south: 36.54, west: -83.68, north: 39.47, east: -75.24 },
  { id: "ca-on", code: "ON", south: 41.68, west: -95.16, north: 56.86, east: -74.34 },
  { id: "ca-bc", code: "BC", south: 48.3, west: -139.06, north: 60.0, east: -114.03 },
  { id: "ca-ab", code: "AB", south: 49.0, west: -120.0, north: 60.0, east: -110.0 },
  { id: "ca-qc", code: "QC", south: 45.0, west: -79.76, north: 62.59, east: -57.1 },
  { id: "ca-mb", code: "MB", south: 49.0, west: -102.0, north: 60.0, east: -89.0 },
  { id: "ca-sk", code: "SK", south: 49.0, west: -110.0, north: 60.0, east: -101.0 },
];

/** Up to 2 jurisdiction codes for Road511 Free plan. */
export function jurisdictionsForLatLon(lat: number, lon: number): string[] {
  const hits = JURISDICTION_BOXES.filter(
    (b) => lat >= b.south && lat <= b.north && lon >= b.west && lon <= b.east,
  ).sort((a, b) => a.id.length - b.id.length);

  const codes: string[] = [];
  for (const hit of hits) {
    if (!codes.includes(hit.code)) codes.push(hit.code);
    if (codes.length >= 2) break;
  }
  return codes;
}

export function parseWeighStatus(props: Record<string, unknown>): string {
  const candidates = [
    props.status,
    props.operating_status,
    props.open_status,
    props.is_open,
    props.open,
  ];
  for (const c of candidates) {
    if (c === true || c === "true" || c === "open" || c === "OPEN") return "open";
    if (c === false || c === "false" || c === "closed" || c === "CLOSED") {
      return "closed";
    }
    if (typeof c === "string") {
      const lower = c.toLowerCase();
      if (lower.includes("open")) return "open";
      if (lower.includes("closed")) return "closed";
      if (lower.includes("monitor")) return "monitoring";
    }
  }
  return "monitoring";
}

function amenitiesFromProps(props: Record<string, unknown>): string[] {
  const raw = props.amenities ?? props.facilities;
  if (Array.isArray(raw)) return raw.map(String);
  return [];
}

function hasShower(amenities: string[]): boolean {
  return amenities.some((a) => /shower/i.test(a));
}

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

export async function fetchRoad511Trucking(
  apiKey: string,
  lat: number,
  lon: number,
  radiusKm: number,
  jurisdictionOverride?: string,
): Promise<{
  weigh: Road511Weigh[];
  parking: Road511Parking[];
  places: Road511Place[];
  jurisdictions: string[];
}> {
  const weigh: Road511Weigh[] = [];
  const parking: Road511Parking[] = [];
  const places: Road511Place[] = [];

  const jurisdictions = jurisdictionOverride?.trim()
    ? jurisdictionOverride.split(",").map((s) => s.trim().toUpperCase()).slice(0, 2)
    : jurisdictionsForLatLon(lat, lon);

  if (!jurisdictions.length) {
    console.warn("Road511: no jurisdiction resolved for", lat, lon);
    return { weigh, parking, places, jurisdictions: [] };
  }

  const urlBase = "https://api.road511.com/api/v1/features";
  const types = [
    "inspection_stations",
    "weigh_stations",
    "truck_parking",
    "truck_rest_areas",
  ];

  const responses = await Promise.all(
    types.map(async (featureType) => {
      const url = new URL(urlBase);
      url.searchParams.set("type", featureType);
      url.searchParams.set("jurisdiction", jurisdictions.join(","));
      url.searchParams.set("lat", String(lat));
      url.searchParams.set("lng", String(lon));
      url.searchParams.set("radius_km", String(Math.min(radiusKm, 80)));
      url.searchParams.set("active", "true");
      url.searchParams.set("limit", "50");
      const resp = await fetch(url.toString(), {
        headers: { "X-API-Key": apiKey, Accept: "application/json" },
      });
      if (!resp.ok) {
        const body = await resp.text();
        console.warn(`Road511 ${featureType} HTTP ${resp.status}:`, body.slice(0, 120));
        return [] as Road511Row[];
      }
      const json = await resp.json();
      if (json.error) {
        console.warn(`Road511 ${featureType}:`, json.error);
        return [] as Road511Row[];
      }
      return (json.data ?? []) as Road511Row[];
    }),
  );

  const rows = responses.flat();
  const maxKm = Math.min(radiusKm, 80);

  for (const row of rows) {
    const featureType = String(row.feature_type ?? "");
    const name = String(row.name ?? featureType);
    const latitude = Number(row.latitude);
    const longitude = Number(row.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;
    if (haversineKm(lat, lon, latitude, longitude) > maxKm) continue;

    const props = (row.properties ?? {}) as Record<string, unknown>;
    const updated = String(row.last_updated ?? new Date().toISOString());
    const id = String(row.id ?? `${featureType}-${latitude}-${longitude}`);

    if (featureType === "weigh_stations" || featureType === "inspection_stations") {
      const status = parseWeighStatus(props);
      weigh.push({
        station_name: name,
        latitude,
        longitude,
        status,
        updated_at: updated,
        source: `road511:${featureType}`,
      });
      places.push({
        external_id: id,
        external_source: "road511",
        poi_type: "weigh_station",
        name,
        lat: latitude,
        lon: longitude,
        has_shower: false,
        amenities: amenitiesFromProps(props),
        status_open: status === "open" ? true : status === "closed" ? false : null,
        parking_available: null,
        parking_total: null,
      });
    } else if (
      featureType === "truck_parking" ||
      featureType === "truck_rest_areas" ||
      featureType === "rest_areas"
    ) {
      const available = props.available != null ? Number(props.available) : null;
      const capacity = props.capacity != null ? Number(props.capacity) : null;
      const amenities = amenitiesFromProps(props);
      parking.push({
        location_name: name,
        latitude,
        longitude,
        available_slots: Number.isFinite(available!) ? available : null,
        total_slots: Number.isFinite(capacity!) ? capacity : null,
        updated_at: String(props.observed_at ?? updated),
        source: "road511:truck_parking",
      });
      places.push({
        external_id: id,
        external_source: "road511",
        poi_type: featureType === "rest_areas" ? "rest_area" : "truck_stop",
        name,
        lat: latitude,
        lon: longitude,
        has_shower: hasShower(amenities),
        amenities,
        status_open: props.open === true || props.open === "true" ? true : null,
        parking_available: Number.isFinite(available!) ? available : null,
        parking_total: Number.isFinite(capacity!) ? capacity : null,
      });
    }
  }

  return { weigh, parking, places, jurisdictions };
}
