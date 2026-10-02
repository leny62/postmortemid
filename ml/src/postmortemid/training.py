"""Training and embedding extraction for the MobileNetV3 models."""

import random
from collections.abc import Callable
from dataclasses import asdict, dataclass

import numpy as np
import torch
import torch.nn.functional as F
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision.transforms import v2

from postmortemid.models import ArcFaceHead, MuzzleEmbedder, SoftmaxHead

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


@dataclass(frozen=True)
class TrainConfig:
    loss: str = "arcface"
    epochs: int = 15
    batch_size: int = 48
    lr: float = 5e-4
    weight_decay: float = 1e-4
    embedding_dim: int = 512
    image_size: int = 224
    arc_scale: float = 30.0
    arc_margin: float = 0.3
    seed: int = 42

    def to_dict(self) -> dict:
        return asdict(self)


def seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def pick_device() -> torch.device:
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def eval_transform(image_size: int) -> v2.Compose:
    return v2.Compose(
        [
            v2.Resize((image_size, image_size), antialias=True),
            v2.ToDtype(torch.float32, scale=True),
            v2.Normalize(IMAGENET_MEAN, IMAGENET_STD),
        ]
    )


def train_transform(image_size: int) -> v2.Compose:
    # No horizontal flip: a mirrored muzzle is a different ridge pattern, so
    # flipping would teach the model that two distinct patterns are the same animal.
    return v2.Compose(
        [
            v2.RandomResizedCrop(image_size, scale=(0.7, 1.0), ratio=(0.85, 1.15), antialias=True),
            v2.RandomRotation(10.0),
            v2.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2),
            v2.ToDtype(torch.float32, scale=True),
            v2.Normalize(IMAGENET_MEAN, IMAGENET_STD),
        ]
    )


class ImageArrayDataset(Dataset):
    """Images held as a uint8 array of shape (N, H, W, 3)."""

    def __init__(self, images: np.ndarray, labels: np.ndarray, transform: Callable) -> None:
        self.images = images
        self.labels = labels
        self.transform = transform

    def __len__(self) -> int:
        return len(self.images)

    def __getitem__(self, i: int) -> tuple[torch.Tensor, int]:
        x = torch.from_numpy(np.array(self.images[i])).permute(2, 0, 1)
        return self.transform(x), int(self.labels[i])


@torch.no_grad()
def embed(
    model: nn.Module, images: np.ndarray, image_size: int, device: torch.device, batch: int = 64
) -> np.ndarray:
    model.eval().to(device)
    loader = DataLoader(
        ImageArrayDataset(images, np.zeros(len(images)), eval_transform(image_size)),
        batch_size=batch,
    )
    out = [model(x.to(device)).float().cpu() for x, _ in loader]
    return F.normalize(torch.cat(out), dim=1).numpy()


def train_embedder(
    images: np.ndarray,
    labels: np.ndarray,
    cfg: TrainConfig,
    device: torch.device,
    on_epoch_end: Callable[[int, MuzzleEmbedder], dict] | None = None,
) -> tuple[MuzzleEmbedder, list[dict]]:
    """Train on identities in `labels` (0..C-1). Returns the final model and per-epoch history."""
    seed_everything(cfg.seed)
    num_classes = int(labels.max()) + 1
    model = MuzzleEmbedder(cfg.embedding_dim).to(device)
    if cfg.loss == "arcface":
        head = ArcFaceHead(cfg.embedding_dim, num_classes, cfg.arc_scale, cfg.arc_margin)
    elif cfg.loss == "softmax":
        head = SoftmaxHead(cfg.embedding_dim, num_classes)
    else:
        raise ValueError(f"unknown loss {cfg.loss}")
    head.to(device)

    loader = DataLoader(
        ImageArrayDataset(images, labels, train_transform(cfg.image_size)),
        batch_size=cfg.batch_size,
        shuffle=True,
        drop_last=True,
        generator=torch.Generator().manual_seed(cfg.seed),
    )
    params = list(model.parameters()) + list(head.parameters())
    optimiser = torch.optim.AdamW(params, lr=cfg.lr, weight_decay=cfg.weight_decay)
    schedule = torch.optim.lr_scheduler.OneCycleLR(
        optimiser, max_lr=cfg.lr, total_steps=cfg.epochs * len(loader), pct_start=0.15
    )

    history = []
    for epoch in range(cfg.epochs):
        model.train()
        head.train()
        total, correct, loss_sum = 0, 0, 0.0
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            logits = head(model(x), y)
            loss = F.cross_entropy(logits, y)
            optimiser.zero_grad()
            loss.backward()
            optimiser.step()
            schedule.step()
            loss_sum += loss.item() * len(y)
            correct += (logits.argmax(1) == y).sum().item()
            total += len(y)
        record = {"epoch": epoch + 1, "train_loss": loss_sum / total, "train_acc": correct / total}
        if on_epoch_end is not None:
            record |= on_epoch_end(epoch + 1, model)
        history.append(record)
    return model, history
