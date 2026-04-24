"""
prediction_routes.py

Data flow:
  1. POST /api/predict/
  2. supabase_auth_required middleware validates JWT → injects current_user
  3. PredictionService.process_prediction(file)
       → calls predict.py → MobileNetV3 model inference
       → returns (dict, 200) or (dict, 422)
  4. On 200: upsert user + insert scan_history row
  5. On non-200: return error JSON immediately (no DB write)

Keys written to scan_history:
  prediction   ← data['disease']          e.g. "Downy-Mildew"
  display_name ← data['display_name']     e.g. "Downy Mildew"
  confidence   ← data['confidence']       e.g. 0.7240
  plant_type   ← data['plant_type']       "malabar_spinach"

predict.py guarantees all four keys are present on every 200 response.
"""

from backend.utils.supabase_client import supabase
from flask import Blueprint, request, jsonify
from backend.services.prediction_service import PredictionService
from backend.middleware.supabase_auth import supabase_auth_required
import logging

logger = logging.getLogger(__name__)
prediction_bp = Blueprint('prediction', __name__)


@prediction_bp.route('/', methods=['POST'])
@prediction_bp.route('', methods=['POST'])
@supabase_auth_required
def predict(current_user):
    # ── Log request details for debugging ─────────────────────────────────────
    logger.info(f"Prediction request from user: {current_user.id}")
    logger.info(f"Request method: {request.method}")
    logger.info(f"Request content-type: {request.content_type}")
    logger.info(f"Files in request: {list(request.files.keys())}")
    
    if 'image' not in request.files:
        logger.error(f"❌ No 'image' file in request. Available keys: {list(request.files.keys())}")
        return jsonify({
            'error': 'invalid_image',
            'message': 'No image file provided. Please upload an image.'
        }), 400

    file = request.files['image']
    if not file or file.filename == '':
        logger.error("❌ Empty file provided")
        return jsonify({
            'error': 'invalid_image',
            'message': 'No image file selected. Please upload a valid image.'
        }), 400

    logger.info(f"Processing prediction for file: {file.filename}")
    prediction_data, status_code = PredictionService.process_prediction(file)

    # ── If prediction was invalid, return error immediately ──────────────────
    # Do NOT save to scan_history for invalid/unclear/non-spinach images
    if status_code != 200:
        logger.warning(f"Prediction rejected with status {status_code}: {prediction_data.get('error')}")
        return jsonify(prediction_data), status_code

    try:
        logger.info(f"Saving prediction to database: {prediction_data.get('disease')}")
        
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

        logger.info(f"✓ Prediction saved for user {current_user.id}")
        return jsonify(prediction_data), 200

    except Exception as e:
        logger.exception(f"❌ Database error: {e}")
        return jsonify({
            'error': 'database_error',
            'message': f'Failed to save prediction: {str(e)}'
        }), 500