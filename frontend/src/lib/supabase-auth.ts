"use client";

import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const isSupabaseAuthConfigured = Boolean(supabaseUrl && supabaseAnonKey);

export const supabaseBrowser = isSupabaseAuthConfigured
  ? createClient(supabaseUrl ?? "", supabaseAnonKey ?? "", {
      auth: {
        flowType: "pkce",
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: "coordit.supabase.auth"
      }
    })
  : null;
