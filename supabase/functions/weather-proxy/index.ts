// GET /functions/v1/weather-proxy?lat=..&lon=..
//
// Proxy seguro do OpenWeatherMap (current weather). A CHAVE fica NO SERVIDOR (secret
// OPENWEATHER_API_KEY), nunca no app. O app chama com a anon key do Supabase; a função injeta o
// appid e devolve o JSON do OpenWeather VERBATIM (o app decodifica OWMCurrentResponse igual antes).
//
// Deploy:  supabase functions deploy weather-proxy --no-verify-jwt
// Secret:  supabase secrets set OPENWEATHER_API_KEY=...

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const OWM_URL = "https://api.openweathermap.org/data/2.5/weather";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const key = Deno.env.get("OPENWEATHER_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "proxy_not_configured" }), {
      status: 503,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const lat = url.searchParams.get("lat");
  const lon = url.searchParams.get("lon");
  if (!lat || !lon) {
    return new Response(JSON.stringify({ error: "missing_lat_lon" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const owm = `${OWM_URL}?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&appid=${key}&units=imperial`;
  const upstream = await fetch(owm);
  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
