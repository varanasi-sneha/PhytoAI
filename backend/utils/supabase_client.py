from supabase import create_client

SUPABASE_URL = "https://eabarbrhjoptxagcnomy.supabase.co"
SUPABASE_KEY = "sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

print("Supabase connected")