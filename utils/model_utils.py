import torch
import torch.nn as nn
from torchvision import models

def create_model(num_classes):
    model = models.resnet18(pretrained=False)
    model.fc = nn.Linear(model.fc.in_features, num_classes)
    return model