from flask import Flask, render_template, request, jsonify
import os

from backend.config import Config
from backend.routes.prediction_routes import prediction_bp

# Initialize Flask App

app = Flask(__name__)
app.config.from_object(Config)

# Ensure upload directory exists

os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# Register API blueprints

app.register_blueprint(prediction_bp, url_prefix='/api/predict')

# ======================

# FRONTEND ROUTES

# ======================

@app.route('/')
def home():
    return render_template('homepage.html')

@app.route('/plant_detection')
@app.route('/plant_detection.html')
def plant_detection():
    return render_template('plant_detection.html')

@app.route('/drug_classification')
@app.route('/drug_classification.html')
def drug_classification():
    return render_template('drug_classification.html')

# ======================

# RUN SERVER

# ======================

if __name__ == '__main__':
    app.run(debug=True, port=5000)
