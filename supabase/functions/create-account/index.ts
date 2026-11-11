// Supabase Edge Function: create-account
// Deploy with: supabase functions deploy create-account
// Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY as Edge Function secrets.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders(), "Content-Type": "application/json" }
  });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Login diperlukan." }, 401);
    const callerClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) return json({ error: "Sesi tidak valid." }, 401);

    const admin = createClient(url, serviceKey);
    const { data: actor, error: actorError } = await admin.from("profiles").select("role").eq("id", caller.id).single();
    if (actorError || !actor || !["admin", "developer"].includes(actor.role)) return json({ error: "Akses ditolak." }, 403);

    const { email, password, display_name, role } = await req.json();
    if (!email || !password || password.length < 8 || !display_name || !["user", "admin"].includes(role))
      return json({ error: "Data tidak valid. Password minimal 8 karakter." }, 400);
    if (role === "admin" && actor.role !== "developer")
      return json({ error: "Hanya Developer yang dapat membuat Admin." }, 403);

    const { data, error } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { display_name }
    });
    if (error) return json({ error: error.message }, 400);
    const { error: profileError } = await admin.from("profiles").upsert({
      id: data.user.id, email, display_name, role
    });
    if (profileError) {
      await admin.auth.admin.deleteUser(data.user.id);
      return json({ error: profileError.message }, 500);
    }
    return json({ success: true, user_id: data.user.id, role });
  } catch (e) {
    return json({ error: e?.message || "Terjadi kesalahan server." }, 500);
  }
});

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };
}
