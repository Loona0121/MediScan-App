// supabase/functions/invite-staff/index.ts
//
// Deploy with: supabase functions deploy invite-staff --use-api

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── ADDED: CORS headers so the web app (browser) can call this function.
// Mobile apps aren't affected by CORS, which is why this was only caught now.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  // ── ADDED: handle the browser's preflight OPTIONS request.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email, role, pharmacyId } = await req.json()

    if (!email || !role || !pharmacyId) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: email, role, pharmacyId.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: existingStaff } = await supabaseAdmin
      .from('staff')
      .select('id')
      .eq('pharmacy_id', pharmacyId)
      .eq('email', email)
      .maybeSingle()

    if (existingStaff) {
      return new Response(
        JSON.stringify({ error: 'This email is already registered as a staff member.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // ── CHANGED: redirectTo now points to the web reset-password page,
    // which works for both PC (opens browser) and Android (opens app
    // directly via App Links, falling back to browser if not installed).
    const { data: inviteData, error: inviteError } =
      await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
        redirectTo: 'https://app.mediscan.space/accept-invite',
      })

    if (inviteError || !inviteData.user) {
      const rawMessage = inviteError?.message ?? 'Invite failed.'
      const isDuplicate = rawMessage.toLowerCase().includes('already registered') ||
        rawMessage.toLowerCase().includes('already been registered')
      const friendlyMessage = isDuplicate
        ? 'This email is already registered to an account. Please use a different email.'
        : rawMessage

      return new Response(
        JSON.stringify({ error: friendlyMessage }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { error: insertError } = await supabaseAdmin.from('staff').insert({
      full_name: '',
      username: null,
      email: email,
      role: role,
      pharmacy_id: pharmacyId,
      profile_completed: false,
    })

    if (insertError) {
      return new Response(
        JSON.stringify({ error: insertError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ success: true, userId: inviteData.user.id }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})