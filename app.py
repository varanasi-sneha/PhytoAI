from backend.utils.supabase_client import supabase
from flask import Flask, render_template, request, jsonify
from flask_cors import CORS
import os
import uuid
import logging

# ── Configure logging ─────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s - %(message)s'
)
logger = logging.getLogger(__name__)

from backend.routes.profile_routes import profile_bp
from backend.config import Config
from backend.routes.prediction_routes import prediction_bp
from backend.routes.prevention_routes import prevention_bp
from backend.routes.history_routes import history_bp
from backend.routes.drug_classification_routes import drug_classification_bp

SERVER_RUN_ID = str(uuid.uuid4())

print("=" * 80)
print("🌱 PhytoAI Plant Disease Detection - Starting")
print("=" * 80)
logger.info(f"Server RUN_ID: {SERVER_RUN_ID}")
logger.info(f"Supabase URL: {os.getenv('SUPABASE_URL', 'using default')}")

# Initialize Flask App
app = Flask(__name__)
app.config.from_object(Config)

# ── Enable CORS for cross-origin requests with proper config for file uploads ──
CORS(
    app,
    resources={r"/api/*": {
        "origins": "*",
        "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"],
        "expose_headers": ["Content-Type"],
        "supports_credentials": False,
        "max_age": 3600
    }},
    send_wildcard=False
)
logger.info("✓ CORS configured for /api/* endpoints")

# Ensure upload directory exists
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
logger.info(f"✓ Upload folder ready: {os.path.abspath(app.config['UPLOAD_FOLDER'])}")

# Register API blueprints
app.register_blueprint(profile_bp, url_prefix="/api")
app.register_blueprint(prediction_bp, url_prefix='/api/predict')
app.register_blueprint(drug_classification_bp, url_prefix='/api/drug')
app.register_blueprint(prevention_bp)
app.register_blueprint(history_bp, url_prefix="/api")
logger.info("✓ All blueprints registered")
# ======================

# FRONTEND ROUTES

# ======================

@app.route('/')
def home():
    return render_template('homepage.html')

@app.route("/api/status", methods=["GET"])
def api_status():
    return jsonify({
        "status": "ok",
        "run_id": SERVER_RUN_ID
    }), 200


@app.route('/plant_detection')
@app.route('/plant_detection.html')
def plant_detection():
    return render_template('plant_detection.html')

@app.route('/drug_classification')
@app.route('/drug_classification.html')
def drug_classification():
    return render_template('drug_classification.html')
@app.route('/profile')
def profile():
    return render_template('profile.html')

# ======================

# RUN SERVER

# ======================

if __name__ == '__main__':
    print(app.url_map)
    app.run(host="0.0.0.0", port=5000, debug=True)
