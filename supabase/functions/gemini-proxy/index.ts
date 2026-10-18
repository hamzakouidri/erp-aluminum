// Gemini gateway: the API key stays on the server.
//
// The app sends { op: "models" } or { op: "generate", model, body } with the
// signed-in user's token. The caller must be an application admin or an
// unblocked member of a workshop; members get AI_DAILY_LIMIT requests a day
// (default 400). The key is the GEMINI_API_KEY secret:
//   supabase secrets set GEMINI_API_KEY=...
//   supabase functions deploy gemini-proxy
// Usage counts live in public.ai_usage_daily (supabase/ai_usage.sql).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const api = "https://generativelanguage.googleapis.com/v1beta";
const maxBodyBytes = 15 * 1024 * 1024;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  try {
    const key = Deno.env.get("GEMINI_API_KEY") ?? "";
    if (!key) return json({ error: "GEMINI_API_KEY is not set" }, 500);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: "Unauthorized" }, 401);

    const raw = await req.text();
    if (raw.length > maxBodyBytes) return json({ error: "Request too large" }, 413);
    const input = JSON.parse(raw);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: adminRow } = await admin.from("app_admins")
      .select("user_id").eq("user_id", user.id).maybeSingle();
    const isAppAdmin = !!adminRow;
    if (!isAppAdmin) {
      const { data: memberships } = await admin.from("workshop_members")
        .select("blocked").eq("user_id", user.id);
      const active = (memberships ?? []).some((m) => m.blocked !== true);
      if (!active) return json({ error: "Forbidden" }, 403);
    }

    if (input.op === "models") {
      const response = await fetch(`${api}/models?pageSize=200`, {
        headers: { "x-goog-api-key": key },
      });
      return new Response(await response.text(), {
        status: response.status,
        headers: { "content-type": "application/json" },
      });
    }

    if (input.op !== "generate") return json({ error: "Unknown op" }, 400);
    const model = String(input.model ?? "");
    if (!/^gemini-[a-z0-9.\-]+$/.test(model)) {
      return json({ error: "Invalid model" }, 400);
    }

    if (!isAppAdmin) {
      const limit = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "400");
      const day = new Date().toISOString().slice(0, 10);
      const { data: usage } = await admin.from("ai_usage_daily")
        .select("requests").eq("user_id", user.id).eq("day", day)
        .maybeSingle();
      const used = usage?.requests ?? 0;
      if (used >= limit) {
        return json({ error: "Daily AI limit reached", limit }, 429);
      }
      await admin.from("ai_usage_daily").upsert({
        user_id: user.id,
        day,
        requests: used + 1,
        updated_at: new Date().toISOString(),
      });
    }

    const response = await fetch(`${api}/models/${model}:generateContent`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": key,
      },
      body: JSON.stringify(input.body ?? {}),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});
