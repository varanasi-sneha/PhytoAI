import os
from supabase import create_client, Client

SUPABASE_URL = os.environ.get('SUPABASE_URL') or 'https://eabarbrhjoptxagcnomy.supabase.co'
SUPABASE_KEY = os.environ.get('SUPABASE_KEY') or 'sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO'

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ── Class names MUST match train.py exactly (from DISEASE_LABELS in predict.py) ─
# These are the 5 disease classes the model predicts
CLASS_NAMES = [
    "Anthracnose",
    "Bacterial-Spot",
    "Downy-Mildew",
    "Healthy-Leaf",
    "Pest-Damage",
]

def normalize_class_name(raw_name: str) -> str:
    """
    Normalize a class name to match the canonical form in CLASS_NAMES.
    Called by prediction_service.py after predict.py returns a disease label.
    Returns the canonical name if found, otherwise returns the input as-is.
    """
    if not raw_name:
        return raw_name

    # Exact match — return as-is
    if raw_name in CLASS_NAMES:
        return raw_name

    # Case-insensitive fallback
    for name in CLASS_NAMES:
        if name.lower() == raw_name.lower():
            return name

    # If still no match, return input (may indicate data integrity issue)
    return raw_name

def get_prevention_data(disease_name: str):
    """
    Fetch prevention data from Supabase for a given disease.
    
    Args:
        disease_name: The disease label from predict.py (e.g., "Downy-Mildew")
    
    Returns:
        dict with disease prevention info, or None if not found
    """
    try:
        # Normalize the disease name to canonical form
        normalized = normalize_class_name(disease_name)

        if not normalized:
            print(f"❌ Empty disease name after normalization: {disease_name}")
            return None

        print(f"[prevention_service] Querying disease: {normalized}")

        # Exact match query first (most reliable)
        response = (
            supabase.table("plant_diseases")
            .select("*")
            .eq("disease_name", normalized)
            .limit(1)
            .execute()
        )
        
        if response.data and len(response.data) > 0:
            print(f"[prevention_service] ✓ Found exact match: {normalized}")
            return response.data[0]

        # Fuzzy fallback if exact match fails
        response = (
            supabase.table("plant_diseases")
            .select("*")
            .ilike("disease_name", f"%{normalized}%")
            .limit(1)
            .execute()
        )
        
        if response.data and len(response.data) > 0:
            print(f"[prevention_service] ✓ Found fuzzy match: {response.data[0]['disease_name']}")
            return response.data[0]
        
        print(f"❌ [prevention_service] No database match found for: {normalized}")
        return None

    except Exception as e:
        print(f"❌ [prevention_service] Database error: {e}")
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