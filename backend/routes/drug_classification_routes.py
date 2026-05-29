from flask import Blueprint, request, jsonify, Response
from backend.services.drug_classification_service import DrugClassificationService
from backend.middleware.supabase_auth import supabase_auth_required
import os
import json
import ssl
import http.client
import urllib.request
import urllib.parse
from dotenv import load_dotenv
load_dotenv()

drug_classification_bp = Blueprint('drug_classification', __name__)


# ── POST /api/drug/classify ────────────────────────────────────────────────
@drug_classification_bp.route('/classify', methods=['POST'])
@supabase_auth_required
def classify_compound(current_user):
    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 400

    data       = request.get_json()
    user_input = (data.get("input") or data.get("smiles") or "").strip()

    if not user_input:
        return jsonify({
            "error"  : "missing_input",
            "message": "Please provide an 'input' field (compound name, SMILES, or CAS number)."
        }), 400

    # ── Case 1: User explicitly confirmed a medicine's active compound ──────
    confirm_medicine = data.get("confirm_medicine", False)
    if confirm_medicine:
        result = DrugClassificationService.predict(user_input)
        result["status"]     = "classified" if result.get("valid") else "error"
        result["input_type"] = "smiles"
        if not result.get("valid"):
            return jsonify({"error": result["error"], "message": result["message"]}), 422
        return jsonify(result), 200

    # ── Case 2: preview_only ───────────────────────────────────────────────
    preview_only = data.get("preview_only", False)
    if preview_only:
        itype = DrugClassificationService.detect_input_type(user_input)

        if itype == "smiles":
            return jsonify({
                "status" : "error",
                "message": "SMILES inputs don't need preview — classify directly."
            }), 400

        resolved = DrugClassificationService.resolve_name_to_smiles(user_input)

        if not resolved["found"]:
            if resolved.get("is_medicine_hint"):
                return jsonify({
                    "status"         : "medicine_detected",
                    "input_type"     : "medicine",
                    "medicine_name"  : user_input,
                    "active_compound": user_input,
                    "smiles"         : "",
                    "drug_indication": f"Formulated pharmaceutical product: {user_input}",
                    "message"        : f"'{user_input}' appears to be a pharmaceutical formulation.",
                    "suggestions"    : resolved.get("suggestions", []),
                }), 200
            return jsonify({
                "status"     : "not_found",
                "input_type" : itype,
                "message"    : resolved.get("message", f"'{user_input}' not found in database."),
                "suggestions": resolved.get("suggestions", [])
            }), 404

        if resolved.get("is_medicine"):
            return jsonify({
                "status"         : "medicine_detected",
                "input_type"     : "medicine",
                "medicine_name"  : user_input,
                "active_compound": resolved["active_compound"],
                "smiles"         : resolved["smiles"],
                "drug_indication": resolved["drug_indication"],
                "message"        : f"'{user_input}' is a pharmaceutical compound."
            }), 200

        if DrugClassificationService.is_inorganic(resolved["smiles"]):
            return jsonify({
                "status"        : "inorganic",
                "input_type"    : "compound_name",
                "resolved_name" : resolved["canonical_name"],
                "smiles"        : resolved["smiles"],
                "iupac_name"    : resolved.get("iupac_name", ""),
                "message"       : "Detected as inorganic compound (no carbon present).",
                "classification": "Inorganic"
            }), 200

        return jsonify({
            "status"        : "resolved",
            "input_type"    : itype,
            "resolved_name" : resolved.get("canonical_name", user_input),
            "iupac_name"    : resolved.get("iupac_name", ""),
            "smiles"        : resolved["smiles"],
            "cid"           : resolved.get("cid"),
        }), 200

    # ── Case 3: Full pipeline ───────────────────────────────────────────────
    result = DrugClassificationService.resolve_and_predict(user_input)
    status = result.get("status")

    if status == "medicine_detected":
        return jsonify(result), 200
    if status == "not_found":
        return jsonify(result), 404
    if status == "inorganic":
        return jsonify(result), 200
    if status == "error" or not result.get("valid", True):
        return jsonify({
            "status" : "error",
            "error"  : result.get("error", "unknown"),
            "message": result.get("message", "Classification failed.")
        }), 422

    return jsonify(result), 200


# ── POST /api/drug/know-more ───────────────────────────────────────────────
@drug_classification_bp.route('/know-more', methods=['POST'])
@supabase_auth_required
def know_more(current_user):
    """
    Know More panel — uses Groq API (free, works in India).
    Get your free key at: console.groq.com
    Add to .env:  GROQ_API_KEY=gsk_...

    Accepts the following fields from the frontend (in priority order):
      active_compound_name  — explicit override (not currently sent by frontend)
      resolved_name         — PubChem canonical name / name from preview step
      compound_label        — generic label fallback
      input                 — original user input (last resort)

    For SMILES and CAS inputs the frontend now sends `compound_label` populated
    with the raw user input as a final fallback, so the prompt will always have
    something meaningful to work with.

    FIX (v3.2): If compound_label is detected as a SMILES, CAS, or InChIKey,
    we resolve it to a human-readable name via PubChem before building the
    prompt — preventing the LLM from hallucinating compound info from raw
    structural strings.
    """
    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 400

    # Choose the best human-readable compound name
    data = request.get_json()
    compound_label = (
        data.get("active_compound_name")   # e.g. "Tetracycline"
        or data.get("resolved_name")       # PubChem canonical name
        or data.get("compound_label")      # fallback label
        or data.get("input")               # original user input
        or "the compound"
    ).strip()

    smiles = (data.get("smiles") or "").strip()
    class_name = (data.get("class_name") or "Unknown").strip()
    confidence_pct = data.get("confidence_percentage", 0)

    # ── FIX: Resolve SMILES / CAS / InChIKey labels to real compound names ──
    # When the frontend falls back to the raw user input (e.g. a SMILES string
    # or CAS number) as compound_label, the LLM hallucinates. Detect this and
    # resolve to a proper name via PubChem before building the prompt.
    itype = DrugClassificationService.detect_input_type(compound_label)

    if itype in ("smiles", "cas", "inchikey"):
        resolved_label = None
        try:
            if itype == "smiles":
                # PubChem SMILES → Title / IUPACName
                encoded = urllib.parse.quote(compound_label, safe='')
                url = (
                    f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles"
                    f"/{encoded}/property/IUPACName,Title/JSON"
                )
                props_data = DrugClassificationService._pubchem_get(url)
                if props_data:
                    p = props_data["PropertyTable"]["Properties"][0]
                    resolved_label = p.get("Title") or p.get("IUPACName")
            else:
                # CAS / InChIKey → CID → Title / IUPACName
                cid = DrugClassificationService._resolve_name_to_cid(compound_label)
                if cid:
                    props = DrugClassificationService._fetch_properties_by_cid(cid)
                    if props:
                        resolved_label = props.get("Title") or props.get("IUPACName")
        except Exception as e:
            print(f"[know-more] PubChem resolution failed for '{compound_label}': {e}")

        if resolved_label:
            compound_label = resolved_label
        # If resolution failed we fall through with the original label;
        # the prompt will still include the SMILES so the LLM has structural context.

    # ── Fallback: if label is still generic/empty, try resolving from smiles field ──
    if compound_label in ("the compound", "") and smiles:
        try:
            encoded = urllib.parse.quote(smiles, safe='')
            url = (
                f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles"
                f"/{encoded}/property/IUPACName,Title/JSON"
            )
            props_data = DrugClassificationService._pubchem_get(url)
            if props_data:
                p = props_data["PropertyTable"]["Properties"][0]
                compound_label = p.get("Title") or p.get("IUPACName") or compound_label
        except Exception as e:
            print(f"[know-more] SMILES field fallback resolution failed: {e}")

    api_key = os.environ.get("GROQ_API_KEY", "")
    if not api_key:
        return jsonify({
            "error": "GROQ_API_KEY not set. Get a free key at console.groq.com and add it to your .env file."
        }), 500

    prompt = (
    f"You are a biochemistry expert. A user classified a compound using PhytoAI.\n\n"
    f"Compound name: {compound_label}\n"
    f"SMILES: {smiles}\n\n"
    f"IMPORTANT: {compound_label} is a well-known, real compound. "
    f"Base your response strictly on established scientific literature about {compound_label}. "
    f"Do NOT invent or speculate about properties. If unsure, say so.\n\n"
    f"Give a rich, structured response covering:\n"
    f"1. **What is it?** — brief description, common names, discovery/history\n"
    f"2. **Key properties** — molecular weight, solubility, stability\n"
    f"3. **Bioactivity & uses** — pharmacological effects, medicinal uses, industrial uses\n"
    f"4. **Interesting facts** — 2–3 surprising or notable facts\n\n"
    f"Be concise but informative. Use markdown. Keep each section 2–4 sentences max.\n"
    f"Strict rules:\n"
    f"- NEVER mention where the compound comes from (no plants, animals, organisms, species, or natural sources)\n"
    f"- NEVER mention biological origin, source organism, or which living thing produces it\n"
    f"- NEVER fabricate properties, names, or history — only use known facts\n"
)

    try:
        payload = json.dumps({
            "model"      : "llama-3.1-8b-instant",
            "messages"   : [{"role": "user", "content": prompt}],
            "max_tokens" : 1024,
            "temperature": 0.7,
        })

        context = ssl.create_default_context()
        conn    = http.client.HTTPSConnection("api.groq.com", context=context)
        conn.request(
            "POST",
            "/openai/v1/chat/completions",
            body=payload,
            headers={
                "Content-Type" : "application/json",
                "Authorization": f"Bearer {api_key}",
                "User-Agent"   : "PhytoAI/1.0",
            }
        )

        resp   = conn.getresponse()
        result = json.loads(resp.read().decode("utf-8"))
        conn.close()

        if resp.status != 200:
            print("Groq error:", result)
            return jsonify({"error": f"Groq API error {resp.status}", "detail": result}), resp.status

        text = result["choices"][0]["message"]["content"]
        return jsonify({"text": text}), 200

    except Exception as e:
        print("Unexpected error in know_more:", str(e))
        return jsonify({"error": "Unexpected error", "detail": str(e)}), 500


# ── GET /api/drug/autocomplete?q=caf ──────────────────────────────────────
@drug_classification_bp.route('/autocomplete', methods=['GET'])
@supabase_auth_required
def autocomplete(current_user):
    q = (request.args.get("q") or "").strip()
    if len(q) < 2:
        return jsonify({"suggestions": []}), 200
    suggestions = DrugClassificationService.get_autocomplete_suggestions(q, limit=6)
    return jsonify({"suggestions": suggestions}), 200


# ── GET /api/drug/depict?smiles=... ───────────────────────────────────────
@drug_classification_bp.route('/depict', methods=['GET'])
@supabase_auth_required
def depict_smiles(current_user):
    import urllib.parse

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