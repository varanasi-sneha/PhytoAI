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

    if status_code != 200:
        return jsonify(prediction_data), status_code

    try:
        # Upsert by id to avoid duplicate-email conflict and keep FK path consistent.
        supabase.table('users').upsert({
        'id': current_user.id,
        'email': getattr(current_user, 'email', None)
        }, on_conflict='id').execute()
        supabase.table('scan_history').insert({
            'user_id': current_user.id,
            'prediction': prediction_data['disease'],
            'confidence': prediction_data['confidence']
        }).execute()

        return jsonify(prediction_data), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500
