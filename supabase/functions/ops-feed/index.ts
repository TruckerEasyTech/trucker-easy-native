type ParkingSignal = {
  location_name: string
  latitude: number
  longitude: number
  available_slots: number | null
  total_slots: number | null
  updated_at: string | null
}

type WeighSignal = {
  station_name: string
  latitude: number
  longitude: number
  status: 'open' | 'closed' | 'monitoring'
  updated_at: string | null
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const NTAD_WIM_URL =
  'https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/NTAD_Weigh_in_Motion_Stations/FeatureServer/0/query'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const lat = Number(url.searchParams.get('lat'))
    const lon = Number(url.searchParams.get('lon'))
    const radiusKm = clamp(Number(url.searchParams.get('radius_km') ?? '80'), 5, 250)

    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return json({ error: 'lat and lon query parameters are required' }, 400)
    }

    const [partner, crowd, official] = await Promise.allSettled([
      fetchPartnerFeeds(lat, lon, radiusKm),
      fetchCrowdSignals(lat, lon, radiusKm),
      fetchOfficialWimStations(lat, lon, radiusKm),
    ])

    const parkingSignals = mergeParkingSignals([
      ...(partner.status === 'fulfilled' ? partner.value.parking_signals : []),
      ...(crowd.status === 'fulfilled' ? crowd.value.parking_signals : []),
    ])
    const weighSignals = mergeWeighSignals([
      ...(partner.status === 'fulfilled' ? partner.value.weigh_signals : []),
      ...(crowd.status === 'fulfilled' ? crowd.value.weigh_signals : []),
      ...(official.status === 'fulfilled' ? official.value.weigh_signals : []),
    ])

    return json({
      parking_signals: parkingSignals,
      weigh_signals: weighSignals,
      sources: {
        partner: statusOf(partner),
        crowd_supabase: statusOf(crowd),
        fhwa_ntad_wim: statusOf(official),
      },
      generated_at: new Date().toISOString(),
    })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500)
  }
})

async function fetchPartnerFeeds(lat: number, lon: number, radiusKm: number) {
  const urls = (Deno.env.get('OPERATIONAL_FEED_PROVIDER_URLS') ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)

  const apiKey = Deno.env.get('OPERATIONAL_FEED_API_KEY') ?? ''
  const results = await Promise.allSettled(
    urls.map(async (baseURL) => {
      const endpoint = new URL('/v1/ops-feed', baseURL)
      endpoint.searchParams.set('lat', String(lat))
      endpoint.searchParams.set('lon', String(lon))
      endpoint.searchParams.set('radius_km', String(radiusKm))

      const headers: Record<string, string> = { accept: 'application/json' }
      if (apiKey) {
        headers.authorization = `Bearer ${apiKey}`
        headers['x-api-key'] = apiKey
      }

      const response = await fetch(endpoint, { headers })
      if (!response.ok) throw new Error(`${baseURL} returned ${response.status}`)
      return await response.json()
    }),
  )

  return {
    parking_signals: results
      .filter((result): result is PromiseFulfilledResult<any> => result.status === 'fulfilled')
      .flatMap((result) => normalizeParkingSignals(result.value.parking_signals ?? [])),
    weigh_signals: results
      .filter((result): result is PromiseFulfilledResult<any> => result.status === 'fulfilled')
      .flatMap((result) => normalizeWeighSignals(result.value.weigh_signals ?? [])),
  }
}

async function fetchCrowdSignals(lat: number, lon: number, radiusKm: number) {
  const baseURL = Deno.env.get('SUPABASE_URL')
  const key = serviceOrAnonKey()
  if (!baseURL || !key) {
    return { parking_signals: [], weigh_signals: [] }
  }

  const since = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString()
  const headers = {
    apikey: key,
    authorization: `Bearer ${key}`,
    accept: 'application/json',
  }

  const [roadReports, weighReports] = await Promise.all([
    fetchJson(
      `${baseURL}/rest/v1/road_reports?select=report_type,latitude,longitude,location_name,reported_at&reported_at=gte.${encodeURIComponent(since)}&order=reported_at.desc&limit=200`,
      headers,
    ),
    fetchJson(
      `${baseURL}/rest/v1/weigh_station_reports?select=station_name,status,latitude,longitude,reported_at&reported_at=gte.${encodeURIComponent(since)}&order=reported_at.desc&limit=200`,
      headers,
    ),
  ])

  const parkingSignals: ParkingSignal[] = []
  const weighSignals: WeighSignal[] = []

  for (const report of roadReports) {
    const reportLat = Number(report.latitude)
    const reportLon = Number(report.longitude)
    if (!withinRadius(lat, lon, reportLat, reportLon, radiusKm)) continue

    if (report.report_type === 'parkingFull' || report.report_type === 'parkingAvailable') {
      parkingSignals.push({
        location_name: report.location_name ?? 'Truck Parking',
        latitude: reportLat,
        longitude: reportLon,
        available_slots: report.report_type === 'parkingFull' ? 0 : null,
        total_slots: null,
        updated_at: report.reported_at ?? null,
      })
    }

    if (report.report_type === 'scaleOpen' || report.report_type === 'scaleClosed') {
      weighSignals.push({
        station_name: report.location_name ?? 'Weigh Station',
        latitude: reportLat,
        longitude: reportLon,
        status: report.report_type === 'scaleOpen' ? 'open' : 'closed',
        updated_at: report.reported_at ?? null,
      })
    }
  }

  for (const report of weighReports) {
    const reportLat = Number(report.latitude)
    const reportLon = Number(report.longitude)
    if (!withinRadius(lat, lon, reportLat, reportLon, radiusKm)) continue

    const status = normalizeWeighStatus(report.status)
    if (!status) continue
    weighSignals.push({
      station_name: report.station_name ?? 'Weigh Station',
      latitude: reportLat,
      longitude: reportLon,
      status,
      updated_at: report.reported_at ?? null,
    })
  }

  return {
    parking_signals: parkingSignals,
    weigh_signals: weighSignals,
  }
}

async function fetchOfficialWimStations(lat: number, lon: number, radiusKm: number) {
  const params = new URLSearchParams({
    where: '1=1',
    outFields: '*',
    returnGeometry: 'true',
    resultRecordCount: '2000',
    f: 'json',
  })
  const data = await fetchJson(`${NTAD_WIM_URL}?${params.toString()}`)
  const features = Array.isArray(data.features) ? data.features : []

  const weighSignals: WeighSignal[] = []
  for (const feature of features) {
    const attr = feature.attributes ?? {}
    const geometry = feature.geometry ?? {}
    const stationLat = Number(geometry.y ?? attr.latitude)
    const stationLon = Number(geometry.x ?? attr.longitude)
    if (!withinRadius(lat, lon, stationLat, stationLon, radiusKm)) continue

    const stationId = String(attr.station_id ?? attr.STNNKEY ?? attr.Concat_ID ?? 'DOT WIM Station')
    const state = attr.state ? ` · ${attr.state}` : ''
    weighSignals.push({
      station_name: `DOT WIM Station ${stationId}${state}`,
      latitude: stationLat,
      longitude: stationLon,
      status: 'monitoring',
      updated_at: null,
    })
  }

  return { parking_signals: [], weigh_signals: weighSignals }
}

function serviceOrAnonKey() {
  const secretKeys = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (secretKeys) {
    try {
      return JSON.parse(secretKeys).default
    } catch {
      // Fall back to legacy variables below.
    }
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY') ?? ''
}

async function fetchJson(url: string, headers: Record<string, string> = {}) {
  const response = await fetch(url, { headers })
  if (!response.ok) throw new Error(`${url} returned ${response.status}`)
  return await response.json()
}

function normalizeParkingSignals(input: any[]): ParkingSignal[] {
  if (!Array.isArray(input)) return []
  return input.flatMap((item) => {
    const latitude = Number(item.latitude)
    const longitude = Number(item.longitude)
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return []
    return [{
      location_name: String(item.location_name ?? item.locationName ?? 'Truck Parking'),
      latitude,
      longitude,
      available_slots: nullableInt(item.available_slots ?? item.availableSlots),
      total_slots: nullableInt(item.total_slots ?? item.totalSlots),
      updated_at: item.updated_at ?? item.updatedAt ?? null,
    }]
  })
}

function normalizeWeighSignals(input: any[]): WeighSignal[] {
  if (!Array.isArray(input)) return []
  return input.flatMap((item) => {
    const latitude = Number(item.latitude)
    const longitude = Number(item.longitude)
    const status = normalizeWeighStatus(item.status)
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || !status) return []
    return [{
      station_name: String(item.station_name ?? item.stationName ?? 'Weigh Station'),
      latitude,
      longitude,
      status,
      updated_at: item.updated_at ?? item.updatedAt ?? null,
    }]
  })
}

function normalizeWeighStatus(value: unknown): WeighSignal['status'] | null {
  const normalized = String(value ?? '').toLowerCase()
  if (normalized === 'open') return 'open'
  if (normalized === 'closed') return 'closed'
  if (normalized === 'monitoring') return 'monitoring'
  return null
}

function mergeParkingSignals(groups: ParkingSignal[]) {
  const seen = new Set<string>()
  return groups.filter((signal) => {
    const key = `${signal.location_name.toLowerCase()}-${signal.latitude.toFixed(4)}-${signal.longitude.toFixed(4)}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function mergeWeighSignals(groups: WeighSignal[]) {
  const seen = new Set<string>()
  return groups.filter((signal) => {
    const key = `${signal.station_name.toLowerCase()}-${signal.latitude.toFixed(4)}-${signal.longitude.toFixed(4)}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function nullableInt(value: unknown) {
  const number = Number(value)
  return Number.isFinite(number) ? Math.round(number) : null
}

function withinRadius(lat1: number, lon1: number, lat2: number, lon2: number, radiusKm: number) {
  if (![lat1, lon1, lat2, lon2].every(Number.isFinite)) return false
  return haversineKm(lat1, lon1, lat2, lon2) <= radiusKm
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const earthKm = 6371
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
  return 2 * earthKm * Math.asin(Math.sqrt(a))
}

function toRad(value: number) {
  return value * Math.PI / 180
}

function clamp(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) return min
  return Math.max(min, Math.min(max, value))
}

function statusOf(result: PromiseSettledResult<unknown>) {
  return result.status === 'fulfilled'
    ? 'ok'
    : result.reason instanceof Error ? result.reason.message : String(result.reason)
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'content-type': 'application/json; charset=utf-8',
    },
  })
}
