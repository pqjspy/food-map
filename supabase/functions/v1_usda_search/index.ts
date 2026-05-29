// USDA FoodData Central search proxy.
// - Hides the USDA API key (env var) from the client.
// - Caches normalized queries in `usda_cache` for 90 days so we share quota
//   across all clients (web + future mobile).
// - Normalizes USDA's response into the per-100g shape the app uses.

// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const USDA_BASE = "https://api.nal.usda.gov/fdc/v1";
const USDA_DATA_TYPES = "Foundation,SR Legacy,Branded";
const CACHE_MAX_AGE_MS = 90 * 24 * 60 * 60 * 1000; // 90 days

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });
}

function normalizeQuery(q: string): string {
  return q.trim().toLowerCase().replace(/\s+/g, " ");
}

function parseFood(f: any) {
  const nMap: Record<number, number> = {};
  for (const n of f.foodNutrients ?? []) {
    const id = n.nutrientId ?? n.nutrient?.id;
    if (id != null) nMap[id] = n.value ?? n.amount;
  }
  const KCAL = 1008, PROT = 1003, FAT = 1004, CARB = 1005, KJ = 1062;
  let kcal = nMap[KCAL];
  if (kcal == null && nMap[KJ] != null) kcal = +(nMap[KJ] * 0.239).toFixed(0);
  return {
    fdcId: f.fdcId,
    name: f.description ?? "Unnamed food",
    brand: f.brandName ?? f.brandOwner ?? null,
    dataType: f.dataType,
    per100: {
      kcal: +(kcal ?? 0).toFixed(0),
      c: +(nMap[CARB] ?? 0).toFixed(1),
      p: +(nMap[PROT] ?? 0).toFixed(1),
      f: +(nMap[FAT] ?? 0).toFixed(1),
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST")   return json({ error: "POST only" }, 405);

  let q: string;
  try {
    const body = await req.json();
    q = String(body?.q ?? "");
  } catch {
    return json({ error: "invalid json body" }, 400);
  }
  if (!q.trim()) return json({ foods: [] });

  const queryNorm = normalizeQuery(q);

  // Service-role client — bypasses RLS so we can read/write usda_cache.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Cache lookup
  const { data: cached } = await supabase
    .from("usda_cache")
    .select("results, fetched_at")
    .eq("query_norm", queryNorm)
    .maybeSingle();

  if (cached) {
    const age = Date.now() - new Date(cached.fetched_at as string).getTime();
    if (age < CACHE_MAX_AGE_MS) {
      return json({ foods: cached.results, cached: true });
    }
  }

  // Live USDA fetch
  const key = Deno.env.get("USDA_API_KEY");
  if (!key) return json({ error: "USDA_API_KEY not configured" }, 500);

  const url = `${USDA_BASE}/foods/search`
    + `?api_key=${encodeURIComponent(key)}`
    + `&query=${encodeURIComponent(queryNorm)}`
    + `&pageSize=25`
    + `&dataType=${encodeURIComponent(USDA_DATA_TYPES)}`;

  const res = await fetch(url);
  if (!res.ok) {
    const text = await res.text();
    return json({ error: `USDA ${res.status}`, detail: text.slice(0, 200) }, res.status);
  }
  const data = await res.json();
  const foods = (data.foods ?? [])
    .map(parseFood)
    .filter((f: any) => f.per100.kcal > 0);

  // Upsert cache (best-effort — don't fail the response if cache write errors)
  await supabase.from("usda_cache").upsert({
    query_norm: queryNorm,
    results: foods,
    fetched_at: new Date().toISOString(),
  });

  return json({ foods, cached: false });
});
