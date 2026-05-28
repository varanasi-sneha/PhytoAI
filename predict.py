"""
predict.py — Inference engine for Malabar Spinach disease classifier

Response contract (matches prediction_routes.py / plant_detection.js):

SUCCESS (200):
{
  "disease":               "Downy-Mildew",       ← saved to scan_history.prediction
  "display_name":          "Downy Mildew",        ← saved to scan_history.display_name
  "plant_type":            "malabar_spinach",     ← saved to scan_history.plant_type
  "confidence":            0.724,                 ← saved to scan_history.confidence
  "confidence_percentage": "72.4%",               ← shown in plant_detection.js
  "is_low_confidence":     false,
  "is_blurry":             false,
  "blur_score":            142.3,
  "distribution": {                               ← bar chart in plant_detection.js
    "Anthracnose": 5.1, "Bacterial-Spot": 9.3,
    "Downy-Mildew": 72.4, "Healthy-Leaf": 3.8, "Pest-Damage": 9.4
  },
  "message": "..."
}

ERROR (422):
{
  "error":                 "not_a_spinach_leaf" | "unclear_image" | "invalid_image",
  "message":               "...",
  "confidence_percentage": "...",
  "distribution":          {...}   ← present for OOD/blurry, absent for file errors
}
"""

import io
import logging
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from PIL import Image

import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import transforms, models

logger = logging.getLogger(__name__)

# ─── Constants ────────────────────────────────────────────────────────────────

IMG_SIZE           = 224
BLUR_THRESHOLD     = 80.0    # Laplacian variance — below this → blurry
CONFIDENCE_THRESH  = 0.55    # max-softmax below this → low-confidence
OOD_ENTROPY_THRESH = 1.6     # Shannon entropy above this → OOD
OOD_CLASS_IDX      = 5       # index of OOD class in the 6-class model
MEAN               = [0.485, 0.456, 0.406]
STD                = [0.229, 0.224, 0.225]

DISEASE_LABELS = [
    "Anthracnose",
    "Bacterial-Spot",
    "Downy-Mildew",
    "Healthy-Leaf",
    "Pest-Damage",
]

# These are stored in scan_history.display_name and shown in the UI
DISPLAY_NAMES = {
    "Anthracnose":    "Anthracnose",
    "Bacterial-Spot": "Bacterial Spot",
    "Downy-Mildew":   "Downy Mildew",
    "Healthy-Leaf":   "Healthy Leaf",
    "Pest-Damage":    "Pest Damage",
}

PLANT_TYPE = "malabar_spinach"   # stored in scan_history.plant_type


# ─── Response builders ────────────────────────────────────────────────────────

def _success_response(
    disease: str,
    confidence: float,          # 0-1 float
    distribution: dict,
    blur_score: float,
    is_blurry: bool,
    is_low_confidence: bool,
    message: str,
) -> dict:
    """
    200-level payload.
    All keys that prediction_routes.py reads for scan_history are present.
    """
    return {
        # ── Saved to Supabase scan_history ────────────────────────────────────
        "disease":      disease,
        "display_name": DISPLAY_NAMES[disease],
        "plant_type":   PLANT_TYPE,
        "confidence":   round(confidence, 4),
        # ── Shown in plant_detection.js ───────────────────────────────────────
        "confidence_percentage": f"{confidence * 100:.1f}%",
        "is_low_confidence":     is_low_confidence,
        "is_blurry":             is_blurry,
        "blur_score":            round(blur_score, 2),
        "distribution":          distribution,
        "message":               message,
    }


def _error_response(
    error_type: str,            # "unclear_image" | "not_a_spinach_leaf" | "invalid_image"
    message: str,
    confidence_percentage: str = "N/A",
    distribution: dict | None = None,
) -> dict:
    """
    422-level payload.
    error_type strings match the if-branches in plant_detection.js detectBtn handler.
    """
    payload: dict = {
        "error":                 error_type,
        "message":               message,
        "confidence_percentage": confidence_percentage,
    }
    if distribution is not None:
        payload["distribution"] = distribution
    return payload


# ─── Model (must match train.py architecture exactly) ────────────────────────

class MalabarMobileNet(nn.Module):
    def __init__(self, num_classes: int = 6, dropout: float = 0.35):
        super().__init__()
        backbone = models.mobilenet_v2(weights=None)
        in_features = backbone.classifier[1].in_features
        backbone.classifier = nn.Identity()
        self.backbone = backbone
        self.head = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(in_features, 512),
            nn.SiLU(),
            nn.Dropout(dropout * 0.6),
            nn.Linear(512, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.head(self.backbone(x))


# ─── Predictor ────────────────────────────────────────────────────────────────

class MalabarPredictor:

    def __init__(self, model_path: str, device: str = "cpu"):
        self.device = torch.device(device)
        self.model  = MalabarMobileNet(num_classes=6).to(self.device)
        ckpt        = torch.load(model_path, map_location=self.device, weights_only=True)
        self.model.load_state_dict(ckpt["model_state"])
        self.model.eval()
        logger.info(
            "MalabarPredictor ready — checkpoint val_acc=%.4f  device=%s",
            ckpt.get("val_acc", float("nan")), self.device
        )

        self.transform = transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(IMG_SIZE),
            transforms.ToTensor(),
            transforms.Normalize(MEAN, STD),
        ])

    # ── Static image quality helpers ──────────────────────────────────────────

    @staticmethod
    def _blur_score(img: Image.Image) -> float:
        """Laplacian variance — lower means blurrier."""
        gray = np.array(img.convert("L"))
        return float(cv2.Laplacian(gray, cv2.CV_64F).var())

    @staticmethod
    def _has_leaf_colour(img: Image.Image) -> bool:
        """
        Check that ≥ 3 % of pixels fall in the green HSV hue band.
        Quickly rejects non-plant photos (hands, paper, sky, random objects).
        """
        hsv   = cv2.cvtColor(np.array(img.convert("RGB")), cv2.COLOR_RGB2HSV)
        mask  = cv2.inRange(hsv, (35, 30, 30), (85, 255, 255))
        ratio = mask.sum() / (mask.size * 255)
        return ratio > 0.03

    @staticmethod
    def _entropy(probs: torch.Tensor) -> float:
        """Shannon entropy (nats) of a probability vector."""
        return float(-(probs * torch.log(probs + 1e-8)).sum().item())

    # ── Main prediction ───────────────────────────────────────────────────────

    def predict(self, image_input) -> tuple[dict, int]:
        """
        Accept: Flask FileStorage | bytes/bytearray | str/Path | PIL.Image
        Return: (response_dict, http_status_code)

        Status codes:
          200  → valid prediction (may include blurry/low-confidence warnings)
          422  → bad image, OOD, or blurry+low-conf combined
        The caller (PredictionService / prediction_routes) handles 500.
        """
        # ── 1. Load image ─────────────────────────────────────────────────────
        try:
            if isinstance(image_input, (str, Path)):
                pil = Image.open(image_input).convert("RGB")
            elif isinstance(image_input, (bytes, bytearray)):
                pil = Image.open(io.BytesIO(image_input)).convert("RGB")
            elif isinstance(image_input, Image.Image):
                pil = image_input.convert("RGB")
            else:
                # Flask FileStorage or file-like object
                raw = image_input.read()
                pil = Image.open(io.BytesIO(raw)).convert("RGB")
        except Exception as exc:
            logger.warning("Image load error: %s", exc)
            return _error_response(
                "invalid_image",
                "Could not read the image. Please upload a valid JPG or PNG file.",
            ), 422

        # ── 2. Minimum-size sanity check ──────────────────────────────────────
        w, h = pil.size
        if w < 32 or h < 32:
            return _error_response(
                "invalid_image",
                "Image is too small. Please upload a photo at least 64 × 64 pixels.",
            ), 422

        # ── 3. Blur score ─────────────────────────────────────────────────────
        blur  = self._blur_score(pil)
        is_blurry = blur < BLUR_THRESHOLD

        # ── 4. Colour check (fast OOD gate before model inference) ────────────
        has_green = self._has_leaf_colour(pil)

        # ── 5. Model forward pass ─────────────────────────────────────────────
        tensor = self.transform(pil).unsqueeze(0).to(self.device)
        with torch.no_grad():
            logits  = self.model(tensor)            # shape: (1, 6)
            probs6  = F.softmax(logits, dim=1)[0]   # 6-class probs
            ood_p   = float(probs6[OOD_CLASS_IDX].item())
            probs5  = probs6[:OOD_CLASS_IDX]        # 5 disease probs

        # Re-normalise disease probs to sum = 1 (independent of OOD logit)
        probs5_norm = probs5 / probs5.sum()
        ent         = self._entropy(probs6)
        pred_idx    = int(probs5_norm.argmax().item())
        conf        = float(probs5_norm[pred_idx].item())   # 0-1

        # Distribution dict — percentages rounded to 2 dp for bar chart
        dist = {
            cls: round(float(probs5_norm[i].item()) * 100, 2)
            for i, cls in enumerate(DISEASE_LABELS)
        }
        conf_pct = f"{conf * 100:.1f}%"

        # ── 6. OOD checks ─────────────────────────────────────────────────────
        if not has_green:
            return _error_response(
                "not_a_spinach_leaf",
                "No leaf-like colour detected. Please upload a clear photo of a "
                "Malabar spinach leaf against a plain background.",
                confidence_percentage=conf_pct,
                distribution=dist,
            ), 422

        if ood_p > 0.45 or ent > OOD_ENTROPY_THRESH:
            return _error_response(
                "not_a_spinach_leaf",
                "This image does not appear to be a Malabar spinach leaf. "
                "Please upload a clear, close-up photo of a Malabar spinach leaf.",
                confidence_percentage=conf_pct,
                distribution=dist,
            ), 422

        # ── 7. Blurry + low-confidence combined → reject ──────────────────────
        # If the model can't make sense of a blurry image, tell the user to retake.
        # If it's blurry but still confident, we proceed with a warning flag.
        if is_blurry and conf < CONFIDENCE_THRESH:
            return _error_response(
                "unclear_image",
                f"The image is too blurry (sharpness score: {blur:.0f}) and the model "
                f"is only {conf * 100:.1f}% confident. Please retake the photo in good "
                "lighting with the leaf filling the frame.",
                confidence_percentage=conf_pct,
                distribution=dist,
            ), 422

        # ── 8. Valid prediction ───────────────────────────────────────────────
        disease        = DISEASE_LABELS[pred_idx]
        is_low_conf    = conf < CONFIDENCE_THRESH

        if is_blurry:
            msg = (
                f"⚠️ Image is slightly blurry (sharpness: {blur:.0f}). "
                f"Most likely: {DISPLAY_NAMES[disease]} ({conf * 100:.1f}% confidence). "
                "Better lighting may improve accuracy."
            )
        elif is_low_conf:
            msg = (
                f"⚠️ Low confidence ({conf * 100:.1f}%). "
                f"Possible {DISPLAY_NAMES[disease]}, but consider a clearer close-up "
                "or consult an agronomist."
            )
        else:
            msg = (
                f"{DISPLAY_NAMES[disease]} detected with {conf * 100:.1f}% confidence."
            )

        return _success_response(
            disease           = disease,
            confidence        = conf,
            distribution      = dist,
            blur_score        = blur,
            is_blurry         = is_blurry,
            is_low_confidence = is_low_conf,
            message           = msg,
        ), 200


# ─── Module-level singleton ────────────────────────────────────────────────────

_predictor: Optional[MalabarPredictor] = None


def get_predictor(
    model_path: str = "malabar_mobilenet.pth",
    device: str = "cpu",
) -> MalabarPredictor:
    """Return a cached MalabarPredictor (loaded once per process)."""
    global _predictor
    if _predictor is None:
        _predictor = MalabarPredictor(model_path, device)
    return _predictor


# ─── predict_image() — called by prediction_service.py ───────────────────────
#
# prediction_service.py contract:
#
#   result = predict_image(filepath)           # always a plain dict, no status code
#
#   result["valid"]  → True  on success, False on any error
#
#   On valid=False:
#     result["error"]   → "unclear_image" | "not_a_spinach_leaf" | "invalid_image"
#     result["message"] → human-readable string
#     result["confidence"]            (present for not_a_spinach_leaf)
#     result["confidence_percentage"] (present for not_a_spinach_leaf)
#
#   On valid=True (all keys prediction_routes.py saves to scan_history):
#     result["disease"]               e.g. "Downy-Mildew"
#     result["display_name"]          e.g. "Downy Mildew"
#     result["plant_type"]            "malabar_spinach"
#     result["confidence"]            0.724  (float 0-1)
#     result["confidence_percentage"] "72.4%"
#     result["is_blurry"]             bool
#     result["blur_score"]            float
#     result["is_low_confidence"]     bool
#     result["distribution"]          {class: pct, ...}
#     result["message"]               str

def predict_image(filepath: str) -> dict:
    """
    Adapter for prediction_service.py.
    Accepts a saved file path, returns a flat dict with a 'valid' key.
    Never raises — all errors are returned as valid=False payloads.
    """
    import os
    # ── Default to model/ subdirectory, can be overridden by MODEL_PATH env var
    default_model = os.path.join("model", "malabar_mobilenet.pth")
    model_path = os.environ.get("MODEL_PATH", default_model)
    device     = os.environ.get("DEVICE", "cpu")

    logger.info(f"Loading model from: {os.path.abspath(model_path)}")
    
    try:
        predictor = get_predictor(model_path, device)
    except Exception as exc:
        logger.exception("❌ Model load failed: %s", exc)
        logger.error(f"Attempted path: {os.path.abspath(model_path)}")
        logger.error(f"File exists: {os.path.exists(model_path)}")
        return {
            "valid":   False,
            "error":   "invalid_image",
            "message": "Model could not be loaded. Please contact support.",
        }

    response, status_code = predictor.predict(filepath)

    if status_code == 200:
        # Merge 'valid' flag into the success dict — prediction_service checks it
        return {"valid": True, **response}
    else:
        # Error dict already has "error" and "message" keys; just add valid=False
        return {"valid": False, **response}