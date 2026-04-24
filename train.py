"""
Malabar Spinach Leaf Disease Classifier
MobileNetV2-based model for 5-class classification + OOD detection
Optimized for Kaggle GPU (30GB RAM, ~3.5 hours training budget)

Classes:
  0: Anthracnose
  1: Bacterial-Spot
  2: Downy-Mildew
  3: Healthy-Leaf
  4: Pest-Damage

Edge cases handled:
  - Blurry images (Laplacian variance)
  - Not-a-leaf images (OOD score via MSP + entropy)
  - Not-a-spinach-leaf (PlantVillage negative samples)
  - Low confidence predictions
"""

import os
import re
import shutil
import random
import math
import json
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
from PIL import Image, ImageFilter
import cv2

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler
from torchvision import transforms, models
from torch.optim.lr_scheduler import OneCycleLR
from sklearn.metrics import classification_report, confusion_matrix
import seaborn as sns
from tqdm import tqdm

# ─── CONFIG ──────────────────────────────────────────────────────────────────

SEED = 42
random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)

DATASET_ROOT   = Path("/kaggle/input/automated-disease-detection-in-malabar-spinach/Malabar Dataset/Malabar Dataset")
# PlantVillage negatives (non-spinach leaves) — used as OOD training signal
# Download via: kaggle datasets download -d emmarex/plantdisease
PLANTVILLAGE_ROOT = Path("/kaggle/input/plantdisease/PlantVillage")

WORK_DIR       = Path("/kaggle/working")
MODEL_OUT      = WORK_DIR / "malabar_mobilenet.pth"
LABELS_OUT     = WORK_DIR / "class_labels.json"
CONFIG_OUT     = WORK_DIR / "model_config.json"

IMG_SIZE       = 224
BATCH_SIZE     = 64       # fits comfortably in 30 GB
EPOCHS         = 40
LR_MAX         = 3e-3
WEIGHT_DECAY   = 1e-4
NUM_WORKERS    = 4

# OOD class index (appended as 5th class during training)
OOD_CLASS      = 5
NUM_CLASSES    = 6        # 5 disease + 1 OOD

# Blurriness threshold (Laplacian variance below this → reject)
BLUR_THRESHOLD = 80.0

# Confidence threshold below which we show "uncertain" warning
CONFIDENCE_THRESHOLD = 0.55

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {DEVICE}")

# ─── CLASS NAME NORMALISATION ─────────────────────────────────────────────────

# Maps every folder name variant → canonical class name
CANONICAL = {
    # Augmented folder names
    r"anthracnose.*":      "Anthracnose",
    r"bacterial.?spot.*":  "Bacterial-Spot",
    r"downy.?mildew.*":    "Downy-Mildew",
    r"healthy.?leaf.*":    "Healthy-Leaf",
    r"pest.?damage.*":     "Pest-Damage",
}

CLASS_NAMES  = ["Anthracnose", "Bacterial-Spot", "Downy-Mildew", "Healthy-Leaf", "Pest-Damage"]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASS_NAMES)}

def normalise_folder(name: str) -> str | None:
    """Return canonical class name for a folder, or None if it doesn't match."""
    low = name.lower()
    for pattern, canonical in CANONICAL.items():
        if re.match(pattern, low):
            return canonical
    return None

# ─── DATASET BUILDER ─────────────────────────────────────────────────────────

def collect_malabar_samples(root: Path) -> list[tuple[Path, int]]:
    """Walk all three sub-folders, normalise names, return (path, label) pairs."""
    samples = []
    folders = [
        root / "Leaf Augmented Data",
        root / "Leaf Original Data",
        root / "Plant Mix Orginal Data",  # flat images — skip (mixed, unlabelled)
    ]
    for folder in folders[:2]:          # ignore unlabelled Plant Mix folder
        if not folder.exists():
            print(f"  [WARN] Missing folder: {folder}")
            continue
        for cls_dir in sorted(folder.iterdir()):
            if not cls_dir.is_dir():
                continue
            canonical = normalise_folder(cls_dir.name)
            if canonical is None:
                print(f"  [WARN] Unrecognised folder: {cls_dir.name}")
                continue
            label = CLASS_TO_IDX[canonical]
            imgs  = list(cls_dir.glob("*.jpg")) + list(cls_dir.glob("*.png")) \
                  + list(cls_dir.glob("*.jpeg")) + list(cls_dir.glob("*.JPG"))
            samples.extend((p, label) for p in imgs)
            print(f"  {canonical:20s} ← {cls_dir.name:40s} ({len(imgs)} imgs)")
    return samples


def collect_ood_samples(pv_root: Path, n_per_class: int = 600) -> list[tuple[Path, int]]:
    """
    Grab non-Malabar-spinach images from PlantVillage as OOD negatives.
    We take n_per_class from a handful of visually different species.
    """
    OOD_SPECIES = [
        "Tomato", "Corn_(maize)", "Grape", "Apple", "Strawberry",
        "Blueberry", "Cherry_(including_sour)", "Peach", "Pepper,_bell",
    ]
    samples = []
    if not pv_root.exists():
        print("[WARN] PlantVillage not found — OOD class will have fewer samples.")
        return samples
    for species in OOD_SPECIES:
        for cls_dir in pv_root.iterdir():
            if not cls_dir.is_dir() or not cls_dir.name.startswith(species):
                continue
            imgs = list(cls_dir.glob("*.jpg")) + list(cls_dir.glob("*.JPG")) \
                 + list(cls_dir.glob("*.png"))
            chosen = random.sample(imgs, min(n_per_class, len(imgs)))
            samples.extend((p, OOD_CLASS) for p in chosen)
    print(f"  OOD samples from PlantVillage: {len(samples)}")
    return samples

# ─── TRANSFORMS ──────────────────────────────────────────────────────────────

def make_transforms(train: bool):
    mean = [0.485, 0.456, 0.406]
    std  = [0.229, 0.224, 0.225]
    if train:
        return transforms.Compose([
            transforms.RandomResizedCrop(IMG_SIZE, scale=(0.6, 1.0)),
            transforms.RandomHorizontalFlip(),
            transforms.RandomVerticalFlip(),
            transforms.RandomRotation(30),
            transforms.ColorJitter(brightness=0.4, contrast=0.4,
                                   saturation=0.3, hue=0.05),
            transforms.RandomGrayscale(p=0.05),
            # Simulate blur (real world blurry photos)
            transforms.RandomApply([transforms.GaussianBlur(kernel_size=5, sigma=(0.5, 2.0))], p=0.3),
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
            transforms.RandomErasing(p=0.2, scale=(0.02, 0.15)),
        ])
    else:
        return transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(IMG_SIZE),
            transforms.ToTensor(),
            transforms.Normalize(mean, std),
        ])


class LeafDataset(Dataset):
    def __init__(self, samples: list[tuple[Path, int]], transform=None):
        self.samples   = samples
        self.transform = transform

    def __len__(self): return len(self.samples)

    def __getitem__(self, idx):
        path, label = self.samples[idx]
        try:
            img = Image.open(path).convert("RGB")
        except Exception:
            img = Image.new("RGB", (IMG_SIZE, IMG_SIZE), (128, 128, 128))
        if self.transform:
            img = self.transform(img)
        return img, label

# ─── MODEL ───────────────────────────────────────────────────────────────────

class MalabarMobileNet(nn.Module):
    """
    MobileNetV2 backbone + custom classifier head.
    Lightweight enough for mobile inference.
    """
    def __init__(self, num_classes=NUM_CLASSES, dropout=0.35):
        super().__init__()
        backbone        = models.mobilenet_v2(weights=models.MobileNet_V2_Weights.IMAGENET1K_V1)
        in_features     = backbone.classifier[1].in_features
        backbone.classifier = nn.Identity()
        self.backbone   = backbone
        self.head       = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(in_features, 512),
            nn.SiLU(),
            nn.Dropout(dropout * 0.6),
            nn.Linear(512, num_classes),
        )

    def forward(self, x):
        feat  = self.backbone(x)
        logit = self.head(feat)
        return logit

    def features(self, x):
        return self.backbone(x)

# ─── TRAINING ────────────────────────────────────────────────────────────────

def build_weighted_sampler(labels: list[int]) -> WeightedRandomSampler:
    counts  = np.bincount(labels)
    weights = 1.0 / counts[labels]
    return WeightedRandomSampler(weights, len(weights), replacement=True)


def train_epoch(model, loader, criterion, optimizer, scheduler, scaler):
    model.train()
    total_loss, correct, n = 0, 0, 0
    for imgs, labels in tqdm(loader, desc="Train", leave=False):
        imgs, labels = imgs.to(DEVICE), labels.to(DEVICE)
        optimizer.zero_grad()
        with torch.amp.autocast("cuda"):
            logits = model(imgs)
            loss   = criterion(logits, labels)
        scaler.scale(loss).backward()
        scaler.unscale_(optimizer)
        nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        scaler.step(optimizer)
        scaler.update()
        scheduler.step()
        total_loss += loss.item() * len(labels)
        correct    += (logits.argmax(1) == labels).sum().item()
        n          += len(labels)
    return total_loss / n, correct / n


@torch.no_grad()
def eval_epoch(model, loader, criterion):
    model.eval()
    total_loss, correct, n = 0, 0, 0
    for imgs, labels in tqdm(loader, desc="Val  ", leave=False):
        imgs, labels = imgs.to(DEVICE), labels.to(DEVICE)
        with torch.amp.autocast("cuda"):
            logits = model(imgs)
            loss   = criterion(logits, labels)
        total_loss += loss.item() * len(labels)
        correct    += (logits.argmax(1) == labels).sum().item()
        n          += len(labels)
    return total_loss / n, correct / n

# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    print("\n=== Collecting samples ===")
    malabar_samples = collect_malabar_samples(DATASET_ROOT)
    ood_samples     = collect_ood_samples(PLANTVILLAGE_ROOT, n_per_class=500)

    all_samples = malabar_samples + ood_samples
    random.shuffle(all_samples)

    # Stats
    label_counts = np.bincount([s[1] for s in all_samples], minlength=NUM_CLASSES)
    print("\nClass distribution:")
    all_class_names = CLASS_NAMES + ["OOD"]
    for i, (name, cnt) in enumerate(zip(all_class_names, label_counts)):
        print(f"  [{i}] {name:20s}: {cnt:5d}")

    # Train / Val split (stratified by class)
    from sklearn.model_selection import train_test_split
    paths  = [s[0] for s in all_samples]
    labels = [s[1] for s in all_samples]
    tr_p, va_p, tr_l, va_l = train_test_split(
        paths, labels, test_size=0.15, stratify=labels, random_state=SEED
    )
    train_samples = list(zip(tr_p, tr_l))
    val_samples   = list(zip(va_p, va_l))
    print(f"\nTrain: {len(train_samples)}  |  Val: {len(val_samples)}")

    # Datasets & loaders
    train_ds = LeafDataset(train_samples, make_transforms(train=True))
    val_ds   = LeafDataset(val_samples,   make_transforms(train=False))

    sampler    = build_weighted_sampler(tr_l)
    train_dl   = DataLoader(train_ds, batch_size=BATCH_SIZE, sampler=sampler,
                            num_workers=NUM_WORKERS, pin_memory=True)
    val_dl     = DataLoader(val_ds,   batch_size=BATCH_SIZE, shuffle=False,
                            num_workers=NUM_WORKERS, pin_memory=True)

    # Model
    model     = MalabarMobileNet(num_classes=NUM_CLASSES).to(DEVICE)
    total_p   = sum(p.numel() for p in model.parameters())
    print(f"\nModel params: {total_p/1e6:.2f}M")

    # Loss — label smoothing helps generalisation
    criterion  = nn.CrossEntropyLoss(label_smoothing=0.1)
    optimizer  = torch.optim.AdamW(model.parameters(), lr=LR_MAX / 10,
                                   weight_decay=WEIGHT_DECAY)
    total_steps = EPOCHS * len(train_dl)
    scheduler  = OneCycleLR(optimizer, max_lr=LR_MAX, total_steps=total_steps,
                             pct_start=0.1, anneal_strategy="cos")
    scaler     = torch.amp.GradScaler("cuda")

    # Training loop
    best_val_acc = 0.0
    history      = {"train_loss": [], "train_acc": [], "val_loss": [], "val_acc": []}

    print("\n=== Training ===")
    for epoch in range(1, EPOCHS + 1):
        tr_loss, tr_acc = train_epoch(model, train_dl, criterion, optimizer, scheduler, scaler)
        va_loss, va_acc = eval_epoch(model, val_dl, criterion)
        history["train_loss"].append(tr_loss)
        history["train_acc"].append(tr_acc)
        history["val_loss"].append(va_loss)
        history["val_acc"].append(va_acc)
        print(f"Epoch {epoch:3d}/{EPOCHS}  "
              f"TrLoss={tr_loss:.4f}  TrAcc={tr_acc:.4f}  "
              f"VaLoss={va_loss:.4f}  VaAcc={va_acc:.4f}")

        if va_acc > best_val_acc:
            best_val_acc = va_acc
            torch.save({
                "epoch": epoch,
                "model_state": model.state_dict(),
                "val_acc": va_acc,
                "class_names": CLASS_NAMES,
                "ood_class_idx": OOD_CLASS,
            }, MODEL_OUT)
            print(f"  ✓ Saved best model (val_acc={va_acc:.4f})")

    print(f"\nBest val accuracy: {best_val_acc:.4f}")

    # ── Final evaluation ──────────────────────────────────────────────────────
    print("\n=== Final evaluation on validation set ===")
    ckpt  = torch.load(MODEL_OUT)
    model.load_state_dict(ckpt["model_state"])
    model.eval()

    all_preds, all_true = [], []
    with torch.no_grad():
        for imgs, labels in val_dl:
            logits = model(imgs.to(DEVICE))
            preds  = logits.argmax(1).cpu().numpy()
            all_preds.extend(preds)
            all_true.extend(labels.numpy())

    # Only report on Malabar classes (0-4) in the val set (ignore OOD)
    mask = np.array(all_true) < OOD_CLASS
    print(classification_report(
        np.array(all_true)[mask],
        np.array(all_preds)[mask],
        target_names=CLASS_NAMES,
        digits=4,
    ))

    # Confusion matrix
    cm = confusion_matrix(
        np.array(all_true)[mask],
        np.array(all_preds)[mask],
    )
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm, annot=True, fmt="d", xticklabels=CLASS_NAMES, yticklabels=CLASS_NAMES)
    plt.title("Confusion Matrix (val, Malabar classes)")
    plt.tight_layout()
    plt.savefig(WORK_DIR / "confusion_matrix.png", dpi=150)

    # Save metadata
    json.dump(CLASS_NAMES, open(LABELS_OUT, "w"))
    json.dump({
        "img_size": IMG_SIZE,
        "num_classes": 5,
        "ood_class_idx": OOD_CLASS,
        "class_names": CLASS_NAMES,
        "blur_threshold": BLUR_THRESHOLD,
        "confidence_threshold": CONFIDENCE_THRESHOLD,
        "mean": [0.485, 0.456, 0.406],
        "std":  [0.229, 0.224, 0.225],
    }, open(CONFIG_OUT, "w"), indent=2)
    print(f"\nSaved → {MODEL_OUT}\nSaved → {LABELS_OUT}\nSaved → {CONFIG_OUT}")


if __name__ == "__main__":
    main()