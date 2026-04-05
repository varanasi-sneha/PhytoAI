import torch
import cv2
import numpy as np
from PIL import Image
from torchvision import transforms, models
import torch.nn as nn

# ── Constants ────────────────────────────────────────────────
MODEL_PATH         = "model/MobileNetV3_best.pth"
CONFIDENCE_THRESHOLD = 0.55   # below this → "unclear or unrecognized image"
BLUR_THRESHOLD       = 80.0   # below this → "image is too blurry"

# These must exactly match your training class folder names
SPINACH_CLASSES = [
    'Anthracnose(Malabar_Spinach)',
    'Bacterial-Spot(Malabar_Spinach)',
    'Downy-Mildew(Malabar_Spinach)',
    'Healthy-Leaf(Malabar_Spinach)',
    'Pest-Damage(Malabar_Spinach)',
]

# Clean display names for frontend
DISPLAY_NAMES = {
    'Anthracnose(Malabar_Spinach)':    'Anthracnose',
    'Bacterial-Spot(Malabar_Spinach)': 'Bacterial Spot',
    'Downy-Mildew(Malabar_Spinach)':   'Downy Mildew',
    'Healthy-Leaf(Malabar_Spinach)':   'Healthy Leaf',
    'Pest-Damage(Malabar_Spinach)':    'Pest Damage',
}

# ── Model loader (cached so it only loads once per server run) ──
_model       = None
_class_names = None
_device      = None

def _load_model():
    global _model, _class_names, _device
    if _model is not None:
        return _model, _class_names, _device

    _device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    checkpoint   = torch.load(MODEL_PATH, map_location=_device)
    _class_names = checkpoint.get("class_names", SPINACH_CLASSES)
    num_classes  = len(_class_names)

    # Build MobileNetV3-Large and match the classifier head from training
    m = models.mobilenet_v3_large(weights=None)
    in_f = m.classifier[3].in_features
    m.classifier[3] = nn.Sequential(
        nn.Dropout(0.4), nn.Linear(in_f, 256),
        nn.ReLU(),       nn.Dropout(0.3),
        nn.Linear(256, num_classes)
    )
    m.load_state_dict(checkpoint["model_state"])
    m.to(_device)
    m.eval()
    _model = m
    print(f"[predict] Model loaded on {_device} | classes: {_class_names}")
    return _model, _class_names, _device

# ── Helpers ──────────────────────────────────────────────────
def _is_blurry(image_path: str) -> bool:
    """Returns True if the image is too blurry to classify reliably."""
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        return True
    variance = cv2.Laplacian(img, cv2.CV_64F).var()
    return variance < BLUR_THRESHOLD

def _looks_like_plant(probs: torch.Tensor, threshold: float) -> bool:
    """
    If the top confidence is below threshold the image probably isn't
    a spinach leaf (wrong plant, random object, etc.)
    """
    return probs.max().item() >= threshold

# ── Main inference function ───────────────────────────────────
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406],
                         [0.229, 0.224, 0.225]),
])

def predict_image(image_path: str) -> dict:
    """
    Returns a dict with keys:
      disease, display_name, confidence, confidence_percentage,
      all_probabilities, valid (bool), error (str or None)
    """
    # ── 1. Blur check ────────────────────────────────────────
    if _is_blurry(image_path):
        return {
            "valid":                False,
            "error":                "unclear_image",
            "message":              "The image is too blurry or unreadable. Please upload a clear photo of the leaf.",
            "disease":              None,
            "display_name":         None,
            "confidence":           None,
            "confidence_percentage": None,
            "all_probabilities":    None,
        }

    # ── 2. Load & run model ──────────────────────────────────
    model, class_names, device = _load_model()

    try:
        image = Image.open(image_path).convert("RGB")
    except Exception:
        return {
            "valid":                False,
            "error":                "invalid_image",
            "message":              "Could not read the image. Please upload a valid JPG or PNG file.",
            "disease":              None,
            "display_name":         None,
            "confidence":           None,
            "confidence_percentage": None,
            "all_probabilities":    None,
        }

    tensor = transform(image).unsqueeze(0).to(device)

    with torch.no_grad():
        outputs      = model(tensor)
        probs        = torch.nn.functional.softmax(outputs, dim=1)[0]
        confidence, predicted_idx = torch.max(probs, 0)

    confidence_val = confidence.item()

    # ── 3. Confidence / not-a-spinach-leaf check ─────────────
    if not _looks_like_plant(probs, CONFIDENCE_THRESHOLD):
        return {
            "valid":                False,
            "error":                "not_a_spinach_leaf",
            "message":              f"This doesn't appear to be a Malabar Spinach leaf (confidence too low: {confidence_val*100:.1f}%). Please upload a clear photo of a spinach leaf.",
            "disease":              None,
            "display_name":         None,
            "confidence":           confidence_val,
            "confidence_percentage": f"{confidence_val*100:.1f}%",
            "all_probabilities":    None,
        }

    # ── 4. Valid prediction ───────────────────────────────────
    predicted_class = class_names[predicted_idx.item()]
    display_name    = DISPLAY_NAMES.get(predicted_class, predicted_class)

    # All class probabilities for frontend breakdown if needed
    all_probs = {
        DISPLAY_NAMES.get(class_names[i], class_names[i]): round(probs[i].item() * 100, 2)
        for i in range(len(class_names))
    }

    return {
        "valid":                True,
        "error":                None,
        "message":              None,
        "prediction":           predicted_class,   # raw, backwards compat
        "disease":              predicted_class,   # raw class name
        "display_name":         display_name,      # clean name for UI
        "confidence":           confidence_val,
        "confidence_percentage": f"{confidence_val*100:.1f}%",
        "all_probabilities":    all_probs,
        "plant_type":           "malabar_spinach",
    }

if __name__ == "__main__":
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else "test.jpg"
    result = predict_image(path)
    print(result)