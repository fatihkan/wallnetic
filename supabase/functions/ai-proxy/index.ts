import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const FAL_API_KEY = Deno.env.get("FAL_API_KEY")!
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

const DAILY_LIMIT = 10
const MONTHLY_LIMIT = 100

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    // Verify user auth
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const token = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Check usage limits
    const today = new Date().toISOString().split("T")[0]
    const monthStart = today.substring(0, 7) + "-01"

    const { data: todayUsage } = await supabase
      .from("usage")
      .select("generation_count")
      .eq("user_id", user.id)
      .eq("date", today)
      .single()

    if (todayUsage && todayUsage.generation_count >= DAILY_LIMIT) {
      return new Response(JSON.stringify({
        error: "Daily generation limit reached",
        limit: DAILY_LIMIT,
        used: todayUsage.generation_count,
      }), {
        status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Parse request
    const { endpoint, body } = await req.json()

    // Forward to fal.ai
    const falResponse = await fetch(`https://queue.fal.run/${endpoint}`, {
      method: "POST",
      headers: {
        "Authorization": `Key ${FAL_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    })

    const falData = await falResponse.json()

    if (!falResponse.ok) {
      return new Response(JSON.stringify(falData), {
        status: falResponse.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Track usage
    await supabase.rpc("increment_usage", {
      p_user_id: user.id,
      p_date: today,
    }).catch(() => {
      // Fallback: upsert manually
      supabase.from("usage").upsert({
        user_id: user.id,
        date: today,
        generation_count: (todayUsage?.generation_count || 0) + 1,
      }, { onConflict: "user_id,date" })
    })

    return new Response(JSON.stringify(falData), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
