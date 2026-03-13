from torchvision import datasets, transforms, models
from torch.utils.data import DataLoader, random_split
import torch
import torch.nn as nn
import os

# Ensure model directory exists
os.makedirs('model', exist_ok=True)

train_transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.RandomHorizontalFlip(),
    transforms.RandomRotation(20),
    transforms.ToTensor(),
])

# Create the full dataset
try:
    full_dataset = datasets.ImageFolder(root='PlantVillage', transform=train_transform)
    NUM_CLASSES = len(full_dataset.classes)
    
    # Train-val split
    train_size = int(0.8 * len(full_dataset))
    val_size = len(full_dataset) - train_size
    train_dataset, val_dataset = random_split(full_dataset, [train_size, val_size])

    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=32, shuffle=False)
except FileNotFoundError:
    print("Warning: PlantVillage directory not found. Using dummy classes for setup validation.")
    NUM_CLASSES = 5
    full_dataset = type('Dummy', (object,), {'classes': ['ClassA', 'ClassB', 'ClassC', 'ClassD', 'ClassE']})()
    train_loader = []
    val_loader = []

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

model = models.resnet18(weights=models.ResNet18_Weights.IMAGENET1K_V1)

for param in model.parameters():
    param.requires_grad = False

model.fc = nn.Linear(model.fc.in_features, NUM_CLASSES)
model = model.to(device)

criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.fc.parameters(), lr=1e-3)

epochs = 10

for epoch in range(epochs):
    model.train()
    running_loss = 0

    for images, labels in train_loader:
        images, labels = images.to(device), labels.to(device)

        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()

        running_loss += loss.item()

    if len(train_loader) > 0:
        # Validation
        model.eval()
        correct = 0
        total = 0

        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(device), labels.to(device)
                outputs = model(images)
                _, predicted = torch.max(outputs, 1)

                total += labels.size(0)
                correct += (predicted == labels).sum().item()

        val_accuracy = 100 * correct / (total if total > 0 else 1)

        print(f"Epoch {epoch+1}/{epochs}")
        print(f"Loss: {running_loss/len(train_loader):.4f}")
        print(f"Validation Accuracy: {val_accuracy:.2f}%")
        print("-----------------------")

# Fine tuning
for param in model.layer4.parameters():
    param.requires_grad = True

optimizer = torch.optim.Adam(model.parameters(), lr=1e-5)

fine_tune_epochs = 5

for epoch in range(fine_tune_epochs):
    model.train()
    running_loss = 0

    for images, labels in train_loader:
        images, labels = images.to(device), labels.to(device)

        optimizer.zero_grad()
        outputs = model(images)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()

        running_loss += loss.item()

    if len(train_loader) > 0:
        model.eval()
        correct = 0
        total = 0

        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(device), labels.to(device)
                outputs = model(images)
                _, predicted = torch.max(outputs, 1)

                total += labels.size(0)
                correct += (predicted == labels).sum().item()

        val_accuracy = 100 * correct / (total if total > 0 else 1)

        print(f"Fine-tune Epoch {epoch+1}/{fine_tune_epochs}")
        print(f"Loss: {running_loss/len(train_loader):.4f}")
        print(f"Validation Accuracy: {val_accuracy:.2f}%")
        print("-----------------------")

save_data = {
    "model_state_dict": model.state_dict(),
    "class_names": full_dataset.classes
}

torch.save(save_data, "model/plant_disease_model_final.pth")
print("Saved model checkpoint successfully.")