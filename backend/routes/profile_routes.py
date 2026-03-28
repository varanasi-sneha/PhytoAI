from flask import Blueprint, jsonify
from backend.middleware.supabase_auth import supabase_auth_required
from backend.utils.supabase_client import supabase

profile_bp = Blueprint("profile", __name__)

@profile_bp.route("/profile")
@supabase_auth_required
def get_profile(current_user):
    try:
        # Extract name from metadata (Supabase stores it here)
        full_name = current_user.user_metadata.get("full_name", "")

        first_name = ""
        last_name = ""

        if full_name:
            parts = full_name.split(" ")
            first_name = parts[0]
            if len(parts) > 1:
                last_name = parts[-1]

        return jsonify({
            "id": current_user.id,
            "email": current_user.email,
            "first_name": first_name,
            "last_name": last_name
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500