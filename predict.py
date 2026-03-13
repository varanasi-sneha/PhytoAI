import torch
from PIL import Image
from torchvision import transforms
from utils.model_utils import create_model

print("Starting script...")

def predict_image(image_path):

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    checkpoint = torch.load("model/plant_disease_model_final.pth", map_location=device)

    class_names = checkpoint["class_names"]

    model = create_model(len(class_names))
    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(device)
    model.eval()


    transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225]
    )
    ])

    image = Image.open(image_path).convert("RGB")
    image = transform(image).unsqueeze(0).to(device)

    with torch.no_grad():
        outputs = model(image)
        # Calculate probabilities using softmax
        probabilities = torch.nn.functional.softmax(outputs, dim=1)
        # Get the highest probability and its index
        confidence, predicted = torch.max(probabilities, 1)

    predicted_class = class_names[predicted.item()]
    confidence_val = confidence.item()

    return {
        "prediction": predicted_class, # maintaining backwards compatibility partially
        "disease": predicted_class,
        "confidence": confidence_val,
        "confidence_percentage": f"{confidence_val * 100:.1f}%"
    }
if __name__ == "__main__":
    image_path = "test.jpg"  # put a sample leaf image here
    prediction = predict_image(image_path)
    print("Prediction:", prediction)