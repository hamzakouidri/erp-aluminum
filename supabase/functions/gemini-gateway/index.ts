import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

const maxRequestBytes = 8 * 1024 * 1024;
const allowedModels = new Set(["gemini-2.5-pro", "gemini-2.5-flash"]);

function boundedNumber(value: unknown, fallback: number, min: number, max: number) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, number));
}

function configuredModel(name: string | undefined, fallback: string) {
  const candidate = (name ?? "").trim();
  return allowedModels.has(candidate) ? candidate : fallback;
}

function parseJson(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch (_) {
    return { error: { message: value } };
  }
}

function buildGeminiRequest(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid Gemini request body");
  }
  const request = value as Record<string, unknown>;
  if (!Array.isArray(request.contents) || request.contents.length === 0 ||
    request.contents.length > 20) {
    throw new Error("A request must contain between 1 and 20 content turns");
  }

  const rawGeneration = request.generationConfig;
  const generation = rawGeneration && typeof rawGeneration === "object" &&
      !Array.isArray(rawGeneration)
    ? rawGeneration as Record<string, unknown>
    : {};
  const responseMimeType = generation.responseMimeType === "application/json"
    ? "application/json"
    : "text/plain";

  return {
    system_instruction: request.system_instruction,
    contents: request.contents,
    generationConfig: {
      temperature: boundedNumber(generation.temperature, 0.1, 0, 1),
      maxOutputTokens: Math.round(
        boundedNumber(generation.maxOutputTokens, 2048, 64, 4096),
      ),
      responseMimeType,
    },
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = req.headers.get("authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return json({ error: "Supabase function configuration is missing" }, 503);
    }

    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Unauthorized" }, 401);

    const raw = await req.text();
    if (raw.length > maxRequestBytes) {
      return json({ error: "AI request is too large" }, 413);
    }
    const input = JSON.parse(raw) as Record<string, unknown>;
    const geminiRequest = buildGeminiRequest(input.request_body);

    const admin = createClient(supabaseUrl, serviceKey);
    const perMinute = Math.round(
      boundedNumber(Deno.env.get("GEMINI_REQUESTS_PER_MINUTE"), 12, 1, 120),
    );
    const perDay = Math.round(
      boundedNumber(Deno.env.get("GEMINI_REQUESTS_PER_DAY"), 600, 1, 10000),
    );
    const { data: permitted, error: quotaError } = await admin.rpc(
      "consume_gemini_request",
      {
        p_user_id: user.id,
        p_minute_limit: perMinute,
        p_day_limit: perDay,
      },
    );
    if (quotaError) {
      console.error("Gemini quota check failed:", quotaError.message);
      return json({ error: "AI quota service is unavailable" }, 503);
    }
    if (permitted !== true) {
      return json({ error: "AI request limit reached" }, 429);
    }

    const apiKey = Deno.env.get("GEMINI_API_KEY")?.trim();
    if (!apiKey) return json({ error: "Gemini is not configured" }, 503);

    const primary = configuredModel(
      Deno.env.get("GEMINI_MODEL"),
      "gemini-2.5-pro",
    );
    const fallback = configuredModel(
      Deno.env.get("GEMINI_FALLBACK_MODEL"),
      "gemini-2.5-flash",
    );
    const models = [...new Set([primary, fallback])];
    let latest: { status: number; body: unknown; model: string } | null = null;

    for (const model of models) {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify(geminiRequest),
        },
      );
      const body = parseJson(await response.text());
      latest = { status: response.status, body, model };
      if (response.ok) break;
      // The fallback is reserved for a temporarily unavailable primary model.
      // Quota and validation errors must be returned clearly to the caller.
      if (response.status !== 404 && response.status < 500) break;
    }

    if (!latest) return json({ error: "Gemini did not return a response" }, 502);
    console.log(JSON.stringify({
      event: "gemini_request",
      userId: user.id,
      model: latest.model,
      status: latest.status,
    }));
    // Keep the Edge Function response successful so Flutter can receive the
    // Gemini status and show a localized message without exposing API details.
    return json(latest);
  } catch (error) {
    console.error("gemini-gateway failed:", String(error));
    return json({ error: "Invalid AI request" }, 400);
  }
});
