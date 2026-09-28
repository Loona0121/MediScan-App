// supabase/functions/rehost-product-image/index.ts
//
// Downloads an external product image server-side (no browser CORS) and
// uploads it to the public `product-images` bucket so Flutter web can
// display it from Supabase Storage.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { imageUrl } = await req.json()
    if (!imageUrl || typeof imageUrl !== 'string') {
      return new Response(
        JSON.stringify({ error: 'Missing imageUrl.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Confirm the caller is authenticated (anon key + user JWT).
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: userData, error: userError } = await supabaseUser.auth.getUser()
    if (userError || !userData.user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const response = await fetch(imageUrl, {
      headers: {
        // Some CDNs reject requests without a UA.
        'User-Agent': 'MediScanImageRehost/1.0',
        Accept: 'image/*,*/*',
      },
    })
    if (!response.ok) {
      return new Response(
        JSON.stringify({ error: `Failed to download image (${response.status}).` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const contentType = response.headers.get('content-type') ?? 'image/jpeg'
    let fileExt = 'jpg'
    if (contentType.includes('png')) fileExt = 'png'
    else if (contentType.includes('webp')) fileExt = 'webp'
    else if (contentType.includes('gif')) fileExt = 'gif'

    const bytes = new Uint8Array(await response.arrayBuffer())
    if (bytes.byteLength === 0) {
      return new Response(
        JSON.stringify({ error: 'Downloaded image was empty.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const fileName = `product_${Date.now()}.${fileExt}`
    const { error: uploadError } = await supabaseAdmin.storage
      .from('product-images')
      .upload(fileName, bytes, {
        contentType: contentType.split(';')[0].trim() || 'image/jpeg',
        upsert: true,
      })

    if (uploadError) {
      return new Response(
        JSON.stringify({ error: uploadError.message }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const { data: publicData } = supabaseAdmin.storage
      .from('product-images')
      .getPublicUrl(fileName)

    return new Response(
      JSON.stringify({ publicUrl: publicData.publicUrl }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
