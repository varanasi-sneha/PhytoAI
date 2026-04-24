from flask import Blueprint, request, jsonify
from backend.services.drug_classification_service import DrugClassificationService
from backend.middleware.supabase_auth import supabase_auth_required
from backend.utils.supabase_client import supabase

drug_classification_bp = Blueprint('drug_classification', __name__)


# ── POST /api/drug/classify ────────────────────────────────────────────────
@drug_classification_bp.route('/classify', methods=['POST'])
@supabase_auth_required
def classify_compound(current_user):
    """
    Classify a compound. Accepts SMILES, compound name, CAS number,
    InChIKey, or medicine/drug name. Handles all input types and edge cases.

    Request JSON:
      { "input": "caffeine" }          ← compound name
      { "input": "Tylenol" }           ← medicine → returns medicine_detected
      { "input": "CC(=O)Oc1ccc..." }   ← SMILES
      { "input": "58-08-2" }           ← CAS number
      { "input": "smiles_here", "confirm_medicine": true }  ← user confirmed

    Response status values:
      "classified"       → result ready, return prediction
      "medicine_detected"→ it's a drug, ask user to confirm
      "not_found"        → suggest alternatives
      "error"            → something went wrong
    """
    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 400

    data  = request.get_json()
    user_input = (data.get("input") or data.get("smiles") or "").strip()

    if not user_input:
        return jsonify({
            "error"  : "missing_input",
            "message": "Please provide an 'input' field (compound name, SMILES, or CAS number)."
        }), 400

    # If user explicitly confirmed classifying a medicine's active compound
    # (sent from frontend "Classify active compound" button), treat as SMILES
    confirm_medicine = data.get("confirm_medicine", False)
    if confirm_medicine:
        result = DrugClassificationService.predict(user_input)
        result["status"]     = "classified" if result.get("valid") else "error"
        result["input_type"] = "smiles"
        if not result.get("valid"):
            return jsonify({"error": result["error"], "message": result["message"]}), 422
        _save_history(current_user, user_input, result)
        return jsonify(result), 200

    # Full resolution pipeline
    result = DrugClassificationService.resolve_and_predict(user_input)

    status = result.get("status")

    # Medicine detected → return 200 with medicine payload (no classification yet)
    if status == "medicine_detected":
        return jsonify(result), 200

    # Not found → return 404 with suggestions
    if status == "not_found":
        return jsonify(result), 404

    # Error states
    if status == "error" or not result.get("valid", True):
        return jsonify({
            "status" : "error",
            "error"  : result.get("error", "unknown"),
            "message": result.get("message", "Classification failed.")
        }), 422

    # Successful classification
    _save_history(current_user, user_input, result)
    return jsonify(result), 200


# ── GET /api/drug/autocomplete?q=caf ──────────────────────────────────────
@drug_classification_bp.route('/autocomplete', methods=['GET'])
@supabase_auth_required
def autocomplete(current_user):
    """
    Returns up to 6 compound name suggestions from PubChem autocomplete.
    Used for the live search dropdown on the frontend.
    """
    q = (request.args.get("q") or "").strip()
    if len(q) < 2:
        return jsonify({"suggestions": []}), 200

    suggestions = DrugClassificationService.get_autocomplete_suggestions(q, limit=6)
    return jsonify({"suggestions": suggestions}), 200


# ── GET /api/drug/depict?smiles=... ───────────────────────────────────────
@drug_classification_bp.route('/depict', methods=['GET'])
@supabase_auth_required
def depict_smiles(current_user):
    """
    Proxy PubChem's 2D structure depiction PNG.
    Returns the image directly so frontend doesn't need CORS workarounds.
    """
    from flask import Response
    import urllib.request, urllib.parse

    smiles = (request.args.get("smiles") or "").strip()
    if not smiles:
        return jsonify({"error": "smiles required"}), 400

    encoded = urllib.parse.quote(smiles, safe='')
    url = (
        f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles"
        f"/{encoded}/PNG?image_size=300x200"
    )
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "PhytoAI/1.0"})
        with urllib.request.urlopen(req, timeout=6) as r:
            img_data = r.read()
        return Response(img_data, mimetype="image/png")
    except Exception as e:
        return jsonify({"error": str(e)}), 502


# ── Private helper ─────────────────────────────────────────────────────────
def _save_history(current_user, user_input: str, result: dict):
    """Save classification result to Supabase. Silently ignores failures."""
    try:
        supabase.table("users").upsert({
            "id"   : current_user.id,
            "email": current_user.email,
            "name" : current_user.user_metadata.get("full_name"),
        }, on_conflict="id").execute()

        supabase.table("drug_classification_history").insert({
            "user_id"      : current_user.id,
            "input"        : user_input,
            "smiles"       : result.get("smiles"),
            "prediction"   : result.get("class_short"),
            "confidence"   : result.get("confidence"),
            "probabilities": result.get("probabilities"),
            "input_type"   : result.get("input_type"),
            "resolved_name": result.get("resolved_name"),
        }).execute()
    except Exception as e:
        print(f"⚠️  Supabase save error: {e}")