import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type RegisterPayload = {
  fullName?: string;
  email?: string;
  password?: string;
  role?: string;
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

  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json(
      { error: "Missing Supabase environment variables" },
      { status: 500, headers: corsHeaders },
    );
  }

  const body = (await req.json()) as RegisterPayload;
  const fullName = (body.fullName ?? "").trim();
  const email = (body.email ?? "").trim().toLowerCase();
  const password = (body.password ?? "").trim();
  const role = (body.role ?? "visitor").trim().toLowerCase();

  if (!fullName || !email || !password) {
    return Response.json(
      { error: "Full name, email, and password are required" },
      { status: 400, headers: corsHeaders },
    );
  }

  if (role !== "visitor") {
    return Response.json(
      { error: "Lot owner accounts must be created by an admin" },
      { status: 400, headers: corsHeaders },
    );
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: createdUser, error: createError } = await adminClient.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        name: fullName,
        role,
      },
    });

  if (createError || !createdUser.user) {
    const message = createError?.message ?? "Failed to create auth user";
    const status = message.toLowerCase().includes("already") ? 409 : 400;
    return Response.json(
      { error: message },
      { status, headers: corsHeaders },
    );
  }

  const authUser = createdUser.user;

  const { error: profileError } = await adminClient.from("users").upsert(
    {
      user_id: authUser.id,
      name: fullName,
      email,
      phone: null,
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
        name: fullName,
      },
    },
    { headers: corsHeaders },
  );
});
