import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type AdminAction = "create";

type LotOwnerProfilePayload = Record<string, unknown>;

type CreateUserPayload = {
  action: AdminAction;
  name?: string;
  email?: string;
  phone?: string;
  role?: string;
  password?: string;
  lotOwnerProfile?: LotOwnerProfilePayload;
};

const textOrNull = (value: unknown) => {
  const text = String(value ?? "").trim();
  return text.length > 0 ? text : null;
};

const intOrNull = (value: unknown) => {
  const text = String(value ?? "").trim();
  if (!text) return null;
  const parsed = Number.parseInt(text, 10);
  return Number.isFinite(parsed) ? parsed : null;
};

const numberOrNull = (value: unknown) => {
  const text = String(value ?? "")
    .trim()
    .toUpperCase()
    .replaceAll("PHP", "")
    .replaceAll("₱", "")
    .replaceAll(",", "");
  if (!text) return null;
  const parsed = Number.parseFloat(text);
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizeLotOwnerProfile = (profile?: LotOwnerProfilePayload) => {
  const source = profile ?? {};
  return {
    control_number: textOrNull(source.control_number),
    first_name: textOrNull(source.first_name),
    middle_name: textOrNull(source.middle_name),
    last_name: textOrNull(source.last_name),
    address: textOrNull(source.address),
    occupation: textOrNull(source.occupation),
    age: intOrNull(source.age),
    civil_status: textOrNull(source.civil_status),
    date_of_birth: textOrNull(source.date_of_birth),
    gender: textOrNull(source.gender),
    spouse_beneficiary: textOrNull(source.spouse_beneficiary),
    beneficiary_relationship: textOrNull(source.beneficiary_relationship),
    lot_class_type: textOrNull(source.lot_class_type),
    block_number: textOrNull(source.block_number),
    lot_number: textOrNull(source.lot_number),
    number_of_lots: intOrNull(source.number_of_lots),
    purchase_term: textOrNull(source.purchase_term),
    lot_price: numberOrNull(source.lot_price),
    interment_fee: numberOrNull(source.interment_fee),
    certification_fee: numberOrNull(source.certification_fee),
    burial_permit_fee: numberOrNull(source.burial_permit_fee),
    total_amount: numberOrNull(source.total_amount),
    or_number: textOrNull(source.or_number),
    receipt_amount: numberOrNull(source.receipt_amount),
    receipt_date: textOrNull(source.receipt_date),
    approved_date: textOrNull(source.approved_date),
    approved_by_name: textOrNull(source.approved_by_name),
    approval_signature: textOrNull(source.approval_signature),
  };
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
    global: {
      headers: { Authorization: authHeader },
    },
  });

  const { data: userResult, error: userError } = await userClient.auth.getUser();
  if (userError || !userResult.user) {
    return Response.json(
      { error: "Invalid session" },
      { status: 401, headers: corsHeaders },
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const currentUser = userResult.user;

  let { data: adminProfile } = await adminClient
    .from("users")
    .select("user_id, email, role")
    .eq("user_id", currentUser.id)
    .maybeSingle();

  if (!adminProfile && currentUser.email) {
    const fallback = await adminClient
      .from("users")
      .select("user_id, email, role")
      .eq("email", currentUser.email)
      .maybeSingle();

    adminProfile = fallback.data ?? null;
  }

  const isAdmin =
    (adminProfile?.role ?? "").toString().toLowerCase() === "admin";

  if (!isAdmin) {
    return Response.json(
      { error: "Admin access required" },
      { status: 403, headers: corsHeaders },
    );
  }

  const body = (await req.json()) as CreateUserPayload;

  if (body.action !== "create") {
    return Response.json(
      { error: "Unsupported action" },
      { status: 400, headers: corsHeaders },
    );
  }

  const name = (body.name ?? "").trim();
  const email = (body.email ?? "").trim().toLowerCase();
  const phone = (body.phone ?? "").trim();
  const role = (body.role ?? "").trim().toLowerCase();
  const password = (body.password ?? "").trim();
  const lotOwnerProfile = normalizeLotOwnerProfile(body.lotOwnerProfile);

  if (!name || !email || !role || !password) {
    return Response.json(
      { error: "Name, email, role, and password are required" },
      { status: 400, headers: corsHeaders },
    );
  }

  if (
    role === "lot_owner" &&
    (!lotOwnerProfile.first_name || !lotOwnerProfile.last_name)
  ) {
    return Response.json(
      { error: "Lot owner first name and last name are required" },
      { status: 400, headers: corsHeaders },
    );
  }

  const { data: createdUser, error: createError } = await adminClient.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        name,
        phone,
        role,
      },
    });

  if (createError || !createdUser.user) {
    return Response.json(
      { error: createError?.message ?? "Failed to create auth user" },
      { status: 400, headers: corsHeaders },
    );
  }

  const authUser = createdUser.user;

  const { error: profileError } = await adminClient.from("users").upsert(
    {
      user_id: authUser.id,
      name,
      email,
      phone: phone || null,
      role,
      password: "managed_by_auth",
      ...(role === "lot_owner" ? lotOwnerProfile : {}),
    },
    {
      onConflict: "user_id",
    },
  );

  if (profileError) {
    return Response.json(
      {
        error:
          `Auth user created, but profile sync failed: ${profileError.message}`,
        user_id: authUser.id,
      },
      { status: 500, headers: corsHeaders },
    );
  }

  return Response.json(
    {
      success: true,
      user: {
        id: authUser.id,
        email: authUser.email,
        role,
        name,
        phone: phone || null,
        lot_owner_profile: role === "lot_owner" ? lotOwnerProfile : null,
      },
    },
    { headers: corsHeaders },
  );
});
