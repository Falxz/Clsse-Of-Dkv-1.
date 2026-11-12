import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) throw new Error("Unauthorized");

    const callerClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) throw new Error("Session tidak valid");
    const { data: callerProfile, error: profileError } = await callerClient.from("profiles").select("role").eq("id", caller.id).single();
    if (profileError || callerProfile?.role !== "developer") throw new Error("Hanya Developer yang dapat mengelola akun");

    const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
    const body = await req.json();
    const targetId = String(body.user_id ?? "");
    const action = String(body.action ?? "");
    if (!targetId || !["disable", "enable", "set_role"].includes(action)) throw new Error("Permintaan tidak valid");
    if (targetId === caller.id && (action === "disable" || (action === "set_role" && body.role !== "developer"))) throw new Error("Developer tidak dapat menonaktifkan atau menurunkan role akunnya sendiri");

    const { data: target, error: targetError } = await admin.from("profiles").select("id,role,is_disabled,email").eq("id", targetId).single();
    if (targetError || !target) throw new Error("Akun tidak ditemukan");

    if (action === "set_role") {
      const role = String(body.role ?? "");
      if (!["user", "admin", "developer"].includes(role)) throw new Error("Role tidak valid");
      if (target.role === "developer" && role !== "developer") {
        const { count } = await admin.from("profiles").select("id", { count: "exact", head: true }).eq("role", "developer");
        if ((count ?? 0) <= 1) throw new Error("Tidak dapat menurunkan satu-satunya akun Developer");
      }
      const { error } = await admin.from("profiles").update({ role }).eq("id", targetId);
      if (error) throw error;
    } else {
      const disabled = action === "disable";
      const { error } = await admin.from("profiles").update({ is_disabled: disabled }).eq("id", targetId);
      if (error) throw error;
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(targetId, {
        ban_duration: disabled ? "876000h" : "none",
      });
      if (authUpdateError) throw authUpdateError;
    }

    await admin.from("activity_logs").insert({ actor_id: caller.id, actor_name: caller.email ?? "Developer", action: "USER_" + action.toUpperCase(), details: { target_id: targetId, target_email: target.email, role: body.role ?? null } });
    return new Response(JSON.stringify({ ok: true }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
