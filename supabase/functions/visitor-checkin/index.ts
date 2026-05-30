import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type CheckInPayload = {
  visitorId?: string;
  visitorName?: string;
  burialId?: string | number | null;
  deceasedName?: string | null;
  lotNumber?: string | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: corsHeaders },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return Response.json(
      { error: "Missing Supabase environment variables" },
      { status: 500, headers: corsHeaders },
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json(
      { error: "Missing authorization header" },
      { status: 401, headers: corsHeaders },
    );
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userResult, error: userError } = await userClient.auth.getUser();
  if (userError || !userResult.user) {
    return Response.json(
      { error: "Invalid session" },
      { status: 401, headers: corsHeaders },
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const authUser = userResult.user;

  const profile = await adminClient
    .from("users")
    .select("user_id, email, role")
    .or(`user_id.eq.${authUser.id},email.eq.${authUser.email ?? ""}`)
    .maybeSingle();

  const role = (profile.data?.role ?? "").toString().toLowerCase();
  if (role !== "gate_officer" && role !== "admin") {
    return Response.json(
      { error: "Gate officer access required" },
      { status: 403, headers: corsHeaders },
    );
  }

  const body = (await req.json()) as CheckInPayload;
  const visitorId = (body.visitorId ?? "").toString().trim();
  const visitorName = (body.visitorName ?? "Unknown").toString().trim() ||
    "Unknown";
  const burialId = body.burialId ?? null;
  const deceasedName = body.deceasedName ?? null;
  const lotNumber = body.lotNumber ?? null;

  if (!visitorId) {
    return Response.json(
      { error: "visitorId is required" },
      { status: 400, headers: corsHeaders },
    );
  }

  const now = new Date();
  const todayStart = new Date(now);
  todayStart.setHours(0, 0, 0, 0);
  const tomorrowStart = new Date(todayStart);
  tomorrowStart.setDate(tomorrowStart.getDate() + 1);

  const existingCheckin = await adminClient
    .from("visitor_log")
    .select("log_id")
    .eq("user_id", visitorId)
    .gte("time_in", todayStart.toISOString())
    .lt("time_in", tomorrowStart.toISOString())
    .maybeSingle();

  if (existingCheckin.data) {
    return Response.json(
      {
        alreadyCheckedIn: true,
        message: `${visitorName} already checked in today`,
      },
      { headers: corsHeaders },
    );
  }

  const { data: inserted, error: insertError } = await adminClient
    .from("visitor_log")
    .insert({
      user_id: visitorId,
      burial_id: burialId,
      time_in: now.toISOString(),
      method: "QR",
    })
    .select("log_id")
    .maybeSingle();

  if (insertError) {
    return Response.json(
      { error: insertError.message },
      { status: 400, headers: corsHeaders },
    );
  }

  await adminClient.from("audit_log").insert({
    user_email: authUser.email,
    user_role: role,
    action: "SCAN_QR",
    entity_type: "visitor_log",
    entity_id: inserted?.log_id ?? null,
    details:
      `Scanned QR for ${visitorName}${deceasedName ? ` visiting ${deceasedName}` : ""}${lotNumber ? ` (Lot ${lotNumber})` : ""}`,
    created_at: now.toISOString(),
  });

  return Response.json(
    {
      success: true,
      logId: inserted?.log_id ?? null,
      message:
        burialId != null
          ? `${visitorName} checked in to visit ${deceasedName ?? "Unknown"} (Lot ${lotNumber ?? "--"})`
          : `${visitorName} checked in`,
    },
    { headers: corsHeaders },
  );
});
