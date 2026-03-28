import os
from werkzeug.utils import secure_filename
from backend.config import Config
from predict import predict_image
from backend.services.prevention_service import get_prevention_data
from backend.services.prevention_service import normalize_class_name

class PredictionService:
    
    @staticmethod
    def allowed_file(filename):
        return '.' in filename and filename.rsplit('.', 1)[1].lower() in {'png', 'jpg', 'jpeg'}
    
    @staticmethod
    def process_prediction(file):
        if not file or file.filename == '':
            return {"error": "No selected file"}, 400
            
        if not PredictionService.allowed_file(file.filename):
            return {"error": "Invalid file type. Please upload a JPG or PNG."}, 400
            
        filename = secure_filename(file.filename)
        filepath = os.path.join(Config.UPLOAD_FOLDER, filename)
        file.save(filepath)
        
        try:
            # Predict using our updated model inference module
            prediction_data = predict_image(filepath)

            disease_name = prediction_data.get("disease") or prediction_data.get("class") or prediction_data.get("label")

            if disease_name:
                normalized_name = normalize_class_name(disease_name)
                prediction_data["disease"] = normalized_name   # ✅ FORCE CORRECT FORMAT

                prevention = get_prevention_data(normalized_name)
                if prevention:
                    prediction_data["prevention"] = prevention
            # Clean up uploaded image
            os.remove(filepath)
            
            return prediction_data, 200
        except Exception as e:
            if os.path.exists(filepath):
                os.remove(filepath)
            return {"error": f"Error processing image: {str(e)}"}, 500
