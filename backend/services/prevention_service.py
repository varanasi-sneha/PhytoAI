import os
from supabase import create_client, Client

SUPABASE_URL = os.environ.get('SUPABASE_URL') or 'https://eabarbrhjoptxagcnomy.supabase.co'
SUPABASE_KEY = os.environ.get('SUPABASE_KEY') or 'sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO'

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ── Exact PlantVillage class names (must match your model output) ─
SPINACH_CLASS_NAMES = [
    "Anthracnose(Malabar_Spinach)",
    "Bacterial-Spot(Malabar_Spinach)",
    "Downy-Mildew(Malabar_Spinach)",
    "Healthy-Leaf(Malabar_Spinach)",
    "Pest-Damage(Malabar_Spinach)",
]

def normalize_class_name(raw_name: str) -> str:
    if not raw_name:
        return raw_name

    # Exact match — return as-is
    if raw_name in SPINACH_CLASS_NAMES:
        return raw_name

    # Case-insensitive fallback
    for name in SPINACH_CLASS_NAMES:
        if name.lower() == raw_name.lower():
            return name

    return raw_name

def get_prevention_data(disease_name: str):
    try:
        normalized = normalize_class_name(disease_name)

        print("Incoming disease:", disease_name)
        print("Normalized disease:", normalized)

        # Exact match first
        response = (
            supabase.table("plant_diseases")
            .select("*")
            .eq("disease_name", normalized)
            .limit(1)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return response.data[0]

        # Fuzzy fallback
        response = (
            supabase.table("plant_diseases")
            .select("*")
            .ilike("disease_name", f"%{normalized}%")
            .limit(1)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return response.data[0]
        print("❌ No DB match found")
        return None

    except Exception as e:
        print(f"[prevention_service] Supabase error: {e}")
        return None


def get_all_diseases():
    try:
        response = (
            supabase.table("plant_diseases")
            .select("id, disease_name, plant_name, severity")
            .order("plant_name")
            .execute()
        )
        return response.data or []
    except Exception as e:
        print(f"[prevention_service] Error: {e}")
        return []