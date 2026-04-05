import os
from supabase import create_client, Client

SUPABASE_URL = os.environ.get('SUPABASE_URL') or 'https://eabarbrhjoptxagcnomy.supabase.co'
SUPABASE_KEY = os.environ.get('SUPABASE_KEY') or 'sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO'

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ── Exact PlantVillage class names (must match your model output) ─
DISEASE_CLASS_NAMES = [
    "Apple___Apple_scab",
    "Apple___Black_rot",
    "Apple___Cedar_apple_rust",
    "Apple___healthy",
    "Blueberry___healthy",
    "Cherry_(including_sour)___Powdery_mildew",
    "Cherry_(including_sour)___healthy",
    "Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot",
    "Corn_(maize)___Common_rust_",
    "Corn_(maize)___Northern_Leaf_Blight",
    "Corn_(maize)___healthy",
    "Grape___Black_rot",
    "Grape___Esca_(Black_Measles)",
    "Grape___Leaf_blight_(Isariopsis_Leaf_Spot)",
    "Grape___healthy",
    "Orange___Haunglongbing_(Citrus_greening)",
    "Peach___Bacterial_spot",
    "Peach___healthy",
    "Pepper,_bell___Bacterial_spot",
    "Pepper,_bell___healthy",
    "Potato___Early_blight",
    "Potato___Late_blight",
    "Potato___healthy",
    "Raspberry___healthy",
    "Soybean___healthy",
    "Squash___Powdery_mildew",
    "Strawberry___Leaf_scorch",
    "Strawberry___healthy",
    "Tomato___Bacterial_spot",
    "Tomato___Early_blight",
    "Tomato___Late_blight",
    "Tomato___Leaf_Mold",
    "Tomato___Septoria_leaf_spot",
    "Tomato___Spider_mites Two-spotted_spider_mite",
    "Tomato___Target_Spot",
    "Tomato___Tomato_Yellow_Leaf_Curl_Virus",
    "Tomato___Tomato_mosaic_virus",
    "Tomato___healthy",
]


def normalize_class_name(raw_name: str) -> str:
    if not raw_name:
        return raw_name

    # Step 1: Replace spaces → underscore
    name = raw_name.replace(" ", "_")

    # Step 2: Convert single "_" → "___"
    if "___" not in name and "_" in name:
        parts = name.split("_", 1)
        if len(parts) == 2:
            name = parts[0] + "___" + parts[1]

    # Step 3: Exact match
    if name in DISEASE_CLASS_NAMES:
        return name

    # Step 4: Case-insensitive match
    for disease in DISEASE_CLASS_NAMES:
        if disease.lower() == name.lower():
            return disease

    return name


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