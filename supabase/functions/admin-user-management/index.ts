import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type AdminAction = "create";

type CreateUserPayload = {
  action: AdminAction;
  name?: string;
  email?: string;
  phone?: string;
  role?: string;
  password?: string;
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

  if (!name || !email || !role || !password) {
    return Response.json(
      { error: "Name, email, role, and password are required" },
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
      },
    },
    { headers: corsHeaders },
  );
});
