import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'sup3r-s3cr3t-k3y-phytoai-2026'

    SUPABASE_URL = os.environ.get('SUPABASE_URL') or 'https://eabarbrhjoptxagcnomy.supabase.co'
    SUPABASE_KEY = os.environ.get('SUPABASE_KEY') or 'sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO'

    UPLOAD_FOLDER = 'uploads'
