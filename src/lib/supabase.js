import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  // Vite will still render, but this helps developers diagnose missing env variables.
  console.warn("Missing Supabase environment variables for HEHA Swipe.");
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
