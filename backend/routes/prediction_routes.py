from backend.utils.supabase_client import supabase
from flask import Blueprint, request, jsonify
from backend.services.prediction_service import PredictionService
from backend.middleware.supabase_auth import supabase_auth_required

prediction_bp = Blueprint('prediction', __name__)

@prediction_bp.route('/', methods=['POST'])
@supabase_auth_required
def predict(current_user):
    # 'current_user' is injected by @supabase_auth_required
    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400
        
    file = request.files['image']
    prediction_data, status_code = PredictionService.process_prediction(file)
    
    # Keep the structure matching what we previously returned/expected on frontend
    if status_code == 200:
        supabase.table("scan_history").insert({
        "user_id": current_user,
        "prediction": prediction_data["disease"],
        "confidence": prediction_data["confidence"]
        }).execute()
        return jsonify(prediction_data), 200
    else:
        return jsonify(prediction_data), status_code
