from flask import Blueprint, jsonify
from backend.middleware.supabase_auth import supabase_auth_required
from backend.utils.supabase_client import supabase

history_bp = Blueprint("history", __name__)

@history_bp.route("/history")
@supabase_auth_required
def get_history(current_user):

    response = supabase.table("scan_history")\
        .select("*")\
        .eq("user_id", current_user.id)\
        .order("created_at", desc=True)\
        .execute()

    return jsonify(response.data)

@history_bp.route("/update-profile", methods=["POST"])
@supabase_auth_required
def update_profile(current_user):
    from flask import request, jsonify

    data = request.json

    supabase.table("users").update({
        "first_name": data.get("first_name"),
        "last_name": data.get("last_name")
    }).eq("id", current_user.id).execute()

    return jsonify({"message": "updated"})