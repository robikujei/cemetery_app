import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type LotOwnerProfilePayload = Record<string, unknown>;

type CreateUserPayload = {
  action: "create";
  name?: string;
  email?: string;
  phone?: string;
  role?: string;
  password?: string;
  lotOwnerProfile?: LotOwnerProfilePayload;
};

const normalizeRole = (value: unknown) => {
  const role = String(value ?? "").trim().toLowerCase();
  return ["guard", "gate officer", "gate-officer"].includes(role)
    ? "gate_officer"
    : role;
};

type ListUsersPayload = {
  action: "list";
  page?: number;
  pageSize?: number;
};

// This action is deliberately parameter-free.  It lets an authenticated user
// reconnect only a profile with the same verified Auth email; it never takes a
// role or a user id from the client.
type RecoverProfilePayload = {
  action: "recover_profile";
};

type AdminUserManagementPayload =
  | CreateUserPayload
  | ListUsersPayload
  | RecoverProfilePayload;

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

  const body = (await req.json()) as AdminUserManagementPayload;

  // Auth accounts may survive while their public profile is left pointing at
  // an old Auth UUID (for example after an account is recreated).  The
  // password sign-in proves control of the email, so it is safe to reconnect
  // the same-email profile.  This intentionally does not create a privileged
  // profile from client-provided metadata.
  if (body.action === "recover_profile") {
    const email = currentUser.email?.trim().toLowerCase();
    if (!email) {
      return Response.json(
        { error: "The signed-in account has no email address" },
        { status: 400, headers: corsHeaders },
      );
    }

    const { data: profile, error: profileError } = await adminClient
      .from("users")
      .select("user_id, name, role, email")
      .ilike("email", email)
      .maybeSingle();
    if (profileError) {
      return Response.json(
        { error: `Unable to find the portal profile: ${profileError.message}` },
        { status: 500, headers: corsHeaders },
      );
    }
    if (!profile) {
      return Response.json(
        { error: "No portal profile matches this account email" },
        { status: 404, headers: corsHeaders },
      );
    }

    if (profile.user_id !== currentUser.id) {
      const { error: relinkError } = await adminClient
        .from("users")
        .update({ user_id: currentUser.id, email })
        .eq("user_id", profile.user_id);
      if (relinkError) {
        return Response.json(
          { error: `Unable to reconnect the portal profile: ${relinkError.message}` },
          { status: 500, headers: corsHeaders },
        );
      }
    }

    const { data: linkedProfile, error: linkedProfileError } = await adminClient
      .from("users")
      .select("user_id, name, role, email")
      .eq("user_id", currentUser.id)
      .maybeSingle();
    if (linkedProfileError || !linkedProfile) {
      return Response.json(
        {
          error: linkedProfileError?.message ??
            "The portal profile could not be reloaded after reconnecting",
        },
        { status: 500, headers: corsHeaders },
      );
    }

    return Response.json(
      { profile: linkedProfile, recovered: true },
      { headers: corsHeaders },
    );
  }

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

  if (body.action === "list") {
    const pageSize = Math.min(Math.max(Number(body.pageSize) || 100, 1), 100);
    const page = Math.max(Number(body.page) || 0, 0);
    // Authentication is the source of truth for portal accounts.  Some
    // visitor and gate-officer accounts predate their matching public profile,
    // so listing only public.users makes valid accounts disappear from User
    // Management.
    const { data: authPage, error: authUsersError } = await adminClient.auth
      .admin.listUsers({ page: page + 1, perPage: pageSize });
    if (authUsersError) {
      return Response.json(
        { error: `Failed to load authentication users: ${authUsersError.message}` },
        { status: 500, headers: corsHeaders },
      );
    }

    const authUsers = authPage.users ?? [];
    const userIds = authUsers.map((user) => user.id);
    const { data: profiles, error: profilesError, count } = await adminClient
      .from("users")
      .select("*", { count: "exact" })
      .in("user_id", userIds);
    if (profilesError) {
      return Response.json(
        { error: `Failed to load user profiles: ${profilesError.message}` },
        { status: 500, headers: corsHeaders },
      );
    }

    const { data: ownerships, error: ownershipError } = userIds.length === 0
      ? { data: [], error: null }
      : await adminClient
        .from("lot_ownership")
        .select("ownership_id, user_id, lot_id, total_months, status")
        .in("user_id", userIds);
    if (ownershipError) {
      return Response.json(
        { error: `Failed to load lot ownership: ${ownershipError.message}` },
        { status: 500, headers: corsHeaders },
      );
    }
    const ownershipByUserId = new Map<string, Record<string, unknown>>();
    for (const ownership of ownerships ?? []) {
      ownershipByUserId.set(String(ownership.user_id), ownership);
    }
    const profileByUserId = new Map<string, Record<string, unknown>>();
    for (const profile of profiles ?? []) {
      profileByUserId.set(String(profile.user_id), profile);
    }
    const pageUsers = authUsers.map((authUser) => {
      const profile = profileByUserId.get(authUser.id);
      const metadata = (authUser.user_metadata ?? {}) as Record<string, unknown>;
      const metadataRole = normalizeRole(metadata.role);
      const role = normalizeRole(profile?.role ?? metadataRole ?? "visitor") ||
        "visitor";
      const metadataName = textOrNull(metadata.name);
      const metadataPhone = textOrNull(metadata.phone);
      const ownership = ownershipByUserId.get(authUser.id);
      return {
        ...profile,
        user_id: authUser.id,
        name: profile?.name ?? metadataName ?? authUser.email?.split("@")[0] ?? "Unknown",
        email: profile?.email ?? authUser.email ?? "",
        phone: profile?.phone ?? metadataPhone ?? "",
        role,
        profile_missing: !profile,
        is_lot_owner: Boolean(ownership) || role === "lot_owner",
        linked_lot_id: ownership?.lot_id,
        linked_ownership_id: ownership?.ownership_id,
        linked_total_months: ownership?.total_months,
      };
    });
    pageUsers.sort((a, b) =>
      String(a.name).localeCompare(String(b.name), undefined, {
        sensitivity: "base",
      })
    );
    // GoTrue does not return a total. This exact count is available whenever
    // the last page is short; on a full page it leaves one more page available
    // for the client to request without preloading it.
    const total = authUsers.length < pageSize
      ? page * pageSize + authUsers.length
      : (page + 2) * pageSize;
    return Response.json(
      { users: pageUsers, page, pageSize, total: Math.max(total, count ?? 0) },
      { headers: corsHeaders },
    );
  }

  if (body.action !== "create") {
    return Response.json(
      { error: "Unsupported action" },
      { status: 400, headers: corsHeaders },
    );
  }

  const name = (body.name ?? "").trim();
  const email = (body.email ?? "").trim().toLowerCase();
  const phone = (body.phone ?? "").trim();
  const role = normalizeRole(body.role);
  const password = (body.password ?? "").trim();
  const lotOwnerProfile = normalizeLotOwnerProfile(body.lotOwnerProfile);

  if (!name || !email || !role || !password) {
    return Response.json(
      { error: "Name, email, role, and password are required" },
      { status: 400, headers: corsHeaders },
    );
  }

  if (!["admin", "gate_officer", "lot_owner", "visitor"].includes(role)) {
    return Response.json(
      { error: "Unsupported user role" },
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

  // A profile can outlive a deleted/recreated Auth account. Remember it so
  // the newly created account can be relinked instead of failing on email.
  const { data: existingProfiles, error: existingProfileError } =
    await adminClient
      .from("users")
      .select("user_id")
      .ilike("email", email)
      .limit(1);

  if (existingProfileError) {
    return Response.json(
      {
        error:
          `Unable to check the existing profile: ${existingProfileError.message}`,
      },
      { status: 500, headers: corsHeaders },
    );
  }

  const existingProfile = existingProfiles?.[0] ?? null;

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

  const profilePayload = {
    user_id: authUser.id,
    name,
    email,
    phone: phone || null,
    role,
    password: "managed_by_auth",
    ...(role === "lot_owner" ? lotOwnerProfile : {}),
  };

  const { error: profileError } = existingProfile
    ? await adminClient
      .from("users")
      .update(profilePayload)
      .eq("user_id", existingProfile.user_id)
    : await adminClient.from("users").upsert(profilePayload, {
      onConflict: "user_id",
    });

  if (profileError) {
    // Do not leave an Auth-only account that can sign in but can never route
    // to a portal. The administrator can safely retry after fixing the error.
    const { error: cleanupError } = await adminClient.auth.admin.deleteUser(
      authUser.id,
    );
    return Response.json(
      {
        error:
          cleanupError
            ? `Profile sync failed: ${profileError.message}. Auth cleanup also failed: ${cleanupError.message}`
            : `Profile sync failed and the incomplete Auth account was removed: ${profileError.message}`,
        user_id: cleanupError ? authUser.id : null,
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
