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