import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
});

Deno.serve(async (req) => {
  try {
    const authorization = req.headers.get("authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const { data: { user } } = await callerClient.auth.getUser();
    if (!user) return json({ error: "Unauthorized" }, 401);

    const input = await req.json();
    const workshopId = String(input.workshop_id ?? "");
    const workerUids = [...new Set((input.worker_uids ?? []).map(String))];
    const audience = String(input.audience ?? "workers");
    const eventType = String(input.event_type ?? "worker_assignment");
    const supportedAudience = [
      "managers",
      "order_viewers",
      "workers",
      "all_managers",
    ];
    const isGlobalAudience = audience === "all_managers";
    if ((!workshopId && !isGlobalAudience) ||
      !supportedAudience.includes(audience) ||
      (audience === "workers" && workerUids.length === 0))
      return json({ error: "Missing workshop or recipients" }, 400);

    const admin = createClient(supabaseUrl, serviceKey);
    const managerRoles = ["owner", "manager", "co_manager", "admin"];
    // "all_managers" (e.g. new shared prices) reaches every workshop and is
    // reserved for the application administrator.
    let isAppAdmin = false;
    if (isGlobalAudience) {
      const { data: adminRow } = await admin.from("app_admins")
        .select("user_id").eq("user_id", user.id).maybeSingle();
      isAppAdmin = !!adminRow ||
        (user.email ?? "").toLowerCase() === "kouidrihamza45@gmail.com";
      if (!isAppAdmin) return json({ error: "Forbidden" }, 403);
    }
    // deno-lint-ignore no-explicit-any
    let member: any = null;
    if (isGlobalAudience) {
      member = { role: "admin", permissions: {}, blocked: false };
    } else {
      const { data } = await admin.from("workshop_members")
        .select("role,permissions,blocked").eq("workshop_id", workshopId)
        .eq("user_id", user.id).maybeSingle();
      member = data;
    }
    const isManager = !!member &&
      ["owner", "manager", "co_manager", "admin"].includes(member.role);
    const isOrderEvent = eventType.startsWith("order_");
    const canPublishOrderEvent = !!member && member.blocked !== true &&
      (isManager || member.permissions?.view_orders === true);
    if (!member || member.blocked === true ||
      (!isManager && !(isOrderEvent && canPublishOrderEvent))) {
      return json({ error: "Forbidden" }, 403);
    }

    let recipientsQuery = admin.from("workshop_members")
      .select("user_id,role,permissions,blocked").eq("blocked", false);
    if (!isGlobalAudience) {
      recipientsQuery = recipientsQuery.eq("workshop_id", workshopId);
    }
    if (audience === "managers" || isGlobalAudience) {
      recipientsQuery = recipientsQuery.in(
        "role",
        ["owner", "manager", "co_manager", "admin"],
      );
    } else if (audience === "workers") {
      recipientsQuery = recipientsQuery.in("user_id", workerUids);
    }
    const { data: recipients } = await recipientsQuery;
    let allowed = (recipients ?? [])
      .filter((row) => audience !== "order_viewers" ||
        ["owner", "manager", "co_manager", "admin"].includes(row.role) ||
        row.permissions?.view_orders === true)
      .map((row) => row.user_id)
      .filter((userId, index, all) =>
        userId !== user.id && all.indexOf(userId) === index);
    const preferenceType = String(input.preference_type ?? eventType);
    const { data: disabled } = await admin.from("notification_preferences")
      .select("user_id").eq("event_type", preferenceType).eq("enabled", false)
      .in("user_id", allowed);
    const disabledUsers = new Set((disabled ?? []).map((row) => row.user_id));
    allowed = allowed.filter((userId) => !disabledUsers.has(userId));
    let tokenQuery = admin.from("device_push_tokens")
      .select("token").in("user_id", allowed);
    if (!isGlobalAudience) tokenQuery = tokenQuery.eq("workshop_id", workshopId);
    const { data: rawTokenRows } = await tokenQuery;
    const tokenRows = [...new Map(
      (rawTokenRows ?? []).map((row) => [row.token, row]),
    ).values()];

    const rawServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
    if (!rawServiceAccount.trim().startsWith("{")) {
      return json({
        error: "FIREBASE_SERVICE_ACCOUNT_JSON must contain the full Firebase service-account JSON, not an API key",
      }, 500);
    }
    const serviceAccount = JSON.parse(rawServiceAccount);
    const auth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = await auth.getAccessToken();
    const endpoint = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const orderNumber = Number(input.order_number ?? 0);
    const orderId = Number(input.order_id ?? 0);
    const quantity = Number(input.quantity ?? 0);
    const title = audience !== "workers"
      ? String(input.title ?? "تنبيه جديد") : "مهمة جديدة";
    const body = audience !== "workers"
      ? String(input.body ?? "حدث جديد في الورشة")
      : `تم إسناد ${quantity} عنصر لك من الطلبية #${orderNumber}`;
    const data = Object.fromEntries(
      Object.entries(input.data ?? {}).map(([key, value]) => [key, String(value ?? "")]),
    );
    // The authenticated caller is the authoritative actor. Never trust a
    // client-supplied id for recipient filtering, but always forward it so a
    // foreground client can also reject its own event defensively.
    data.sender_user_id = user.id;
    const results = await Promise.all((tokenRows ?? []).map(async ({ token }) => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ message: {
          token,
          notification: {
            title,
            body,
          },
          data: {
            type: eventType,
            workshop_id: workshopId,
            order_id: String(orderId),
            order_number: String(orderNumber),
            ...data,
          },
          android: {
            priority: "high",
            // Keep the message queued by FCM while the phone is off or
            // offline (maximum allowed: 28 days) instead of only 24 hours.
            ttl: "2419200s",
            notification: {
              channel_id: "erp_orders_alert_channel_v2",
              sound: "default",
              default_vibrate_timings: true,
              visibility: "PUBLIC",
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        } }),
      });
      const responseBody = await response.text();
      if (!response.ok &&
        (response.status === 404 || responseBody.includes("UNREGISTERED"))) {
        // Uninstalled app / expired token: drop it so it stops failing.
        await admin.from("device_push_tokens").delete().eq("token", token);
      }
      if (!response.ok) {
        return { ok: false, token, status: response.status, error: responseBody };
      }
      return { ok: true, token };
    }));
    const failed = results.filter((result) => !result.ok);
    // Diagnostic line visible in Edge Functions > Logs.
    console.log(JSON.stringify({
      event: eventType,
      audience,
      recipients: allowed.length,
      tokens: (tokenRows ?? []).length,
      sent: results.length - failed.length,
      failed: failed.length,
      firstError: failed[0]?.error?.slice(0, 300) ?? null,
    }));
    return json({
      sent: results.length - failed.length,
      failed: failed.length,
      errors: failed.slice(0, 5).map(({ status, error }) => ({ status, error })),
    }, failed.length === results.length && results.length > 0 ? 502 : 200);
  } catch (error) {
    console.error("send-worker-assignment failed:", String(error));
    return json({ error: String(error) }, 500);
  }
});
