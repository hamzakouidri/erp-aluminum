// Gemini Live: a short-lived token for one real-time voice session.
//
// The app opens the Live API websocket itself (audio has to stream both ways
// with no hop in between), so it cannot go through gemini-proxy. Instead this
// function checks the caller exactly like gemini-proxy, counts the session in
// the same daily limit, and returns an ephemeral token that allows a single
// session for a few minutes. The real key never leaves the server:
//   supabase functions deploy gemini-live-token
// It uses the GEMINI_API_KEY secret already set for gemini-proxy.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenAI } from "npm:@google/genai@^1";

const api = "https://generativelanguage.googleapis.com/v1beta";

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

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: adminRow } = await admin.from("app_admins")
      .select("user_id").eq("user_id", user.id).maybeSingle();
    const isAppAdmin = !!adminRow;
    if (!isAppAdmin) {
      const { data: memberships } = await admin.from("workshop_members")
        .select("blocked").eq("user_id", user.id);
      const active = (memberships ?? []).some((m) => m.blocked !== true);
      if (!active) return json({ error: "Forbidden" }, 403);

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

    // The models that can hold a Live session, for the app to pick from.
    const listed = await fetch(`${api}/models?pageSize=200`, {
      headers: { "x-goog-api-key": key },
    }).then((r) => r.json()).catch(() => ({}));
    const models = ((listed?.models ?? []) as Array<Record<string, unknown>>)
      .filter((m) =>
        ((m.supportedGenerationMethods ?? []) as string[])
          .includes("bidiGenerateContent")
      )
      .map((m) => String(m.name ?? "").replace("models/", ""));

    const now = Date.now();
    const ai = new GoogleGenAI({ apiKey: key });
    const token = await ai.authTokens.create({
      config: {
        uses: 1,
        // The session must start within two minutes and ends after thirty.
        newSessionExpireTime: new Date(now + 2 * 60 * 1000).toISOString(),
        expireTime: new Date(now + 30 * 60 * 1000).toISOString(),
        httpOptions: { apiVersion: "v1alpha" },
      },
    });
    return json({ token: token.name, models });
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});
