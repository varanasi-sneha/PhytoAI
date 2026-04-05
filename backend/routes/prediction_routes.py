from backend.utils.supabase_client import supabase
from flask import Blueprint, request, jsonify
from backend.services.prediction_service import PredictionService
from backend.middleware.supabase_auth import supabase_auth_required

prediction_bp = Blueprint('prediction', __name__)

@prediction_bp.route('/', methods=['POST'])
@prediction_bp.route('', methods=['POST'])
@supabase_auth_required
def predict(current_user):
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400

    file = request.files['image']
    prediction_data, status_code = PredictionService.process_prediction(file)

    # ── If prediction was invalid, return error immediately ──
    # Do NOT save to scan_history for invalid/unclear/non-spinach images
    if status_code != 200:
        return jsonify(prediction_data), status_code

    try:
        # Upsert user record
        supabase.table("users").upsert({
            "id":    current_user.id,
            "email": current_user.email,
            "name":  current_user.user_metadata.get("full_name")
        }, on_conflict="id").execute()

        # Save to scan_history — now includes plant_type and display_name
        supabase.table('scan_history').insert({
            'user_id':      current_user.id,
            'prediction':   prediction_data['disease'],
            'display_name': prediction_data.get('display_name'),
            'confidence':   prediction_data['confidence'],
            'plant_type':   prediction_data.get('plant_type', 'malabar_spinach'),
        }).execute()

        return jsonify(prediction_data), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500