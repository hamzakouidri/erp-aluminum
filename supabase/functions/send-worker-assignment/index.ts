import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
});

type Lang = "ar" | "fr" | "en";

// Mirrors lib/settings/locales/notification_keys.dart. A push shown by the
// phone while the app is closed is displayed as sent, so the text is written
// here in the language stored with each device token.
const TEXTS: Record<string, Record<Lang, string>> = {
  "generic.title": { ar: "تنبيه جديد", fr: "Nouvelle alerte", en: "New alert" },
  "generic.body": {
    ar: "حدث جديد في الورشة",
    fr: "Nouvel événement dans l'atelier",
    en: "New event in the workshop",
  },
  "order_created.title": {
    ar: "📋 طلبية جديدة في الورشة",
    fr: "📋 Nouvelle commande dans l'atelier",
    en: "📋 New order in the workshop",
  },
  "order_updated.title": {
    ar: "✏️ تعديل طلبية في الورشة",
    fr: "✏️ Commande modifiée dans l'atelier",
    en: "✏️ Order updated in the workshop",
  },
  "order_deleted.title": {
    ar: "🗑️ تم حذف طلبية",
    fr: "🗑️ Commande supprimée",
    en: "🗑️ Order deleted",
  },
  "order.default_client": { ar: "عميل", fr: "Client", en: "Customer" },
  "order.by": { ar: "بواسطة: {author}", fr: "Par : {author}", en: "By: {author}" },
  "assignment.title": { ar: "مهمة جديدة", fr: "Nouvelle tâche", en: "New task" },
  "assignment.body": {
    ar: "تم إسناد {quantity} عنصر لك من الطلبية #{order}",
    fr: "{quantity} élément(s) de la commande #{order} vous ont été assignés",
    en: "{quantity} item(s) from order #{order} were assigned to you",
  },
  "prices.title": { ar: "تحديث الأسعار", fr: "Mise à jour des prix", en: "Price update" },
  "prices.body": {
    ar: "تم تحديث {count} سعر في إدارة الأسعار",
    fr: "{count} prix mis à jour dans la gestion des prix",
    en: "{count} prices updated in price management",
  },
  "price_publication.title": {
    ar: "أسعار جديدة متوفرة",
    fr: "Nouveaux prix disponibles",
    en: "New prices available",
  },
  "price_publication.body": {
    ar: "نشر مدير التطبيق تحديثاً في: {category}. افتح التطبيق لقبوله أو تجاهله.",
    fr: "L'administrateur a publié une mise à jour : {category}. Ouvrez l'application pour l'accepter ou l'ignorer.",
    en: "The administrator published an update: {category}. Open the app to accept or ignore it.",
  },
  "payments.title": { ar: "حركة دفع جديدة", fr: "Nouveau paiement", en: "New payment" },
  "cashbox.title": {
    ar: "حركة صندوق جديدة",
    fr: "Nouveau mouvement de caisse",
    en: "New cash movement",
  },
  "money.body": {
    ar: "{description} - {amount} د.ج",
    fr: "{description} - {amount} DA",
    en: "{description} - {amount} DZD",
  },
  "delivery_plan.title": {
    ar: "خطة توزيع جديدة",
    fr: "Nouveau plan de distribution",
    en: "New distribution plan",
  },
  "delivery_plan.body": {
    ar: "تم إنشاء خطة توزيع للطلبية #{order}",
    fr: "Un plan de distribution a été créé pour la commande #{order}",
    en: "A distribution plan was created for order #{order}",
  },
  "delivered.title": { ar: "تم تسليم الطلبية", fr: "Commande livrée", en: "Order delivered" },
  "delivered.body": {
    ar: "تم تأكيد خطة التوزيع بنجاح",
    fr: "Le plan de distribution a été confirmé",
    en: "The distribution plan was confirmed",
  },
};

const t = (key: string, lang: Lang, args: Record<string, string> = {}) =>
  Object.entries(args).reduce(
    (text, [name, value]) => text.replaceAll(`{${name}}`, value),
    TEXTS[key]?.[lang] ?? TEXTS[key]?.ar ?? key,
  );

const asLang = (value: unknown): Lang =>
  value === "fr" || value === "en" ? value : "ar";

// Same rules as NotificationTexts.fromPushData in the application. Returns
// null when the event lacks the fields, so the caller's own text is kept.
function render(
  eventType: string,
  data: Record<string, string>,
  lang: Lang,
): { title: string; body: string } | null {
  const field = (name: string) => (data[name] ?? "").trim();
  if (eventType.startsWith("order_")) {
    const action = field("action") || eventType.slice("order_".length);
    const titleKey = action === "created"
      ? "order_created.title"
      : action === "deleted"
      ? "order_deleted.title"
      : "order_updated.title";
    let body = field("client_name") || t("order.default_client", lang);
    const code = field("order_code") || field("order_number");
    if (code) body += `  |  #${code}`;
    if (field("author")) body += `\n${t("order.by", lang, { author: field("author") })}`;
    return { title: t(titleKey, lang), body };
  }
  switch (eventType) {
    case "worker_assignment":
      return {
        title: t("assignment.title", lang),
        body: t("assignment.body", lang, {
          quantity: field("quantity") || "0",
          order: field("order_number"),
        }),
      };
    case "prices":
      if (!field("count")) return null;
      return {
        title: t("prices.title", lang),
        body: t("prices.body", lang, { count: field("count") }),
      };
    case "price_publication": {
      const category = field(`category_title_${lang}`) ||
        field("category_title_fr") || field("category");
      return {
        title: t("price_publication.title", lang),
        body: t("price_publication.body", lang, { category }),
      };
    }
    case "payments":
    case "cashbox": {
      if (!field("amount")) return null;
      const amount = Number(field("amount"));
      return {
        title: t(`${eventType}.title`, lang),
        body: t("money.body", lang, {
          description: field("description"),
          amount: Number.isFinite(amount) ? amount.toFixed(2) : field("amount"),
        }),
      };
    }
    case "deliveries":
      if (field("kind") === "plan_created") {
        return {
          title: t("delivery_plan.title", lang),
          body: t("delivery_plan.body", lang, { order: field("order_id") }),
        };
      }
      if (field("kind") === "delivered") {
        return { title: t("delivered.title", lang), body: t("delivered.body", lang) };
      }
      return null;
  }
  return null;
}

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
    const selectTokens = (columns: string) => {
      let query = admin.from("device_push_tokens")
        .select(columns).in("user_id", allowed);
      if (!isGlobalAudience) query = query.eq("workshop_id", workshopId);
      return query;
    };
    // deno-lint-ignore no-explicit-any
    let { data: rawTokenRows, error: tokenError }: { data: any[] | null; error: any } =
      await selectTokens("token,language");
    if (tokenError) {
      // Database where push_notifications.sql predates the language column.
      ({ data: rawTokenRows } = await selectTokens("token"));
    }
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
    const data = Object.fromEntries(
      Object.entries(input.data ?? {}).map(([key, value]) => [key, String(value ?? "")]),
    );
    // The authenticated caller is the authoritative actor. Never trust a
    // client-supplied id for recipient filtering, but always forward it so a
    // foreground client can also reject its own event defensively.
    data.sender_user_id = user.id;
    const textData: Record<string, string> = {
      order_number: String(orderNumber),
      order_id: String(orderId),
      quantity: String(quantity),
      ...data,
    };
    const textFor = (lang: Lang) => {
      const rendered = render(
        audience === "workers" ? "worker_assignment" : eventType,
        textData,
        lang,
      );
      if (rendered) return rendered;
      // Unknown event: keep the caller's text (written in its language).
      return {
        title: String(input.title ?? t("generic.title", lang)),
        body: String(input.body ?? t("generic.body", lang)),
      };
    };
    const results = await Promise.all((tokenRows ?? []).map(async ({ token, language }) => {
      const { title, body } = textFor(asLang(language));
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
    // FCM answers 404 UNREGISTERED (or 400 for a malformed token) once an
    // app is uninstalled or its token rotated. Such a token never works
    // again; keeping it made every later event retry it and count it as a
    // failure.
    const deadTokens = failed
      .filter(({ status, error }) =>
        status === 404 || /UNREGISTERED|registration-token-not-registered/i
          .test(String(error ?? "")) ||
        (status === 400 && /INVALID_ARGUMENT/.test(String(error ?? "")) &&
          /registration token/i.test(String(error ?? ""))))
      .map(({ token }) => token);
    if (deadTokens.length > 0) {
      await admin.from("device_push_tokens").delete().in("token", deadTokens);
    }
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
      removed_tokens: deadTokens.length,
      errors: failed.slice(0, 5).map(({ status, error }) => ({ status, error })),
    }, failed.length === results.length && results.length > 0 ? 502 : 200);
  } catch (error) {
    console.error("send-worker-assignment failed:", String(error));
    return json({ error: String(error) }, 500);
  }
});
