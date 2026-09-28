// supabase/functions/delete-staff/index.ts
//
// Deploy with: supabase functions deploy delete-staff --use-api

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ← ADDED: same CORS pattern as invite-staff
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  // ← ADDED: handle the browser's preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { staffId, email } = await req.json()

    if (!staffId || !email) {
      return new Response(
        JSON.stringify({ error: 'Missing staffId or email.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: usersData, error: listError } =
      await supabaseAdmin.auth.admin.listUsers()

    if (listError) {
      return new Response(
        JSON.stringify({ error: listError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const matchingUser = usersData.users.find(
      (u) => u.email?.toLowerCase() === email.toLowerCase(),
    )

    if (matchingUser) {
      const { error: deleteAuthError } =
        await supabaseAdmin.auth.admin.deleteUser(matchingUser.id)
      if (deleteAuthError) {
        return new Response(
          JSON.stringify({ error: deleteAuthError.message }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    const { error: deleteRowError } = await supabaseAdmin
      .from('staff')
      .delete()
      .eq('id', staffId)

    if (deleteRowError) {
      return new Response(
        JSON.stringify({ error: deleteRowError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})