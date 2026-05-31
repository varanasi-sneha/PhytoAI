import os
from werkzeug.utils import secure_filename
from backend.config import Config
from predict import predict_image
from backend.services.prevention_service import get_prevention_data
from backend.services.prevention_service import normalize_class_name


class PredictionService:

    @staticmethod
    def allowed_file(filename):
        return '.' in filename and \
               filename.rsplit('.', 1)[1].lower() in {'png', 'jpg', 'jpeg'}

    @staticmethod
    def process_prediction(file):
        # ── Basic file checks ────────────────────────────────
        if not file or file.filename == '':
            return {
                "error": "invalid_image",
                "message": "No image file was selected. Please upload a JPG or PNG image."
            }, 400

        if not PredictionService.allowed_file(file.filename):
            return {
                "error": "invalid_file_type",
                "message": "Invalid file type. Please upload a JPG or PNG image."
            }, 400

        filename = secure_filename(file.filename)
        filepath = os.path.join(Config.UPLOAD_FOLDER, filename)
        file.save(filepath)

        try:
            prediction_data = {
    "valid": True,
    "disease": "Test Disease",
    "display_name": "Test Disease",
    "plant_type": "malabar_spinach",
    "confidence": 0.95,
    "confidence_percentage": "95%"
}

            # ── Handle invalid predictions ───────────────────
            if not prediction_data.get("valid"):
                if os.path.exists(filepath):
                    os.remove(filepath)
                error_type = prediction_data.get("error")

                if error_type == "unclear_image":
                    return {
                        "error": "unclear_image",
                        "message": prediction_data.get("message", "The image is too blurry. Please upload a clearer photo."),
                        "confidence_percentage": prediction_data.get("confidence_percentage"),
                        "distribution": prediction_data.get("distribution"),
                    }, 422

                if error_type == "not_a_spinach_leaf":
                    return {
                        "error": "not_a_spinach_leaf",
                        "message": prediction_data.get("message", "This doesn't appear to be a Malabar Spinach leaf."),
                        "confidence": prediction_data.get("confidence"),
                        "confidence_percentage": prediction_data.get("confidence_percentage"),
                        "distribution": prediction_data.get("distribution"),
                    }, 422

                if error_type == "invalid_image":
                    return {
                        "error": "invalid_image",
                        "message": prediction_data.get("message", "Could not read the image. Please upload a valid JPG or PNG.")
                    }, 400

                # Fallback for any other invalid case
                return {
                    "error": "prediction_failed",
                    "message": prediction_data.get("message", "Could not process this image. Please try again.")
                }, 422

            # ── Valid prediction — attach prevention data ─────
            disease_name = prediction_data.get("disease")
            if disease_name:
                normalized_name = normalize_class_name(disease_name)
                prediction_data["disease"] = normalized_name

                prevention = get_prevention_data(normalized_name)
                if prevention:
                    prediction_data["prevention"] = prevention

            if os.path.exists(filepath):
                os.remove(filepath)
            return prediction_data, 200

        except Exception as e:
            if os.path.exists(filepath):
                os.remove(filepath)
            return {
                "error": "prediction_error",
                "message": f"Error processing image: {str(e)}"
            }, 500