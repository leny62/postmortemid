"""MobileNetV3-Large embedding network with ArcFace or softmax training heads."""

import math

import torch
import torch.nn.functional as F
from torch import nn
from torchvision.models import MobileNet_V3_Large_Weights, mobilenet_v3_large

BACKBONE_CHANNELS = 960


def imagenet_backbone() -> nn.Module:
    return mobilenet_v3_large(weights=MobileNet_V3_Large_Weights.IMAGENET1K_V2).features


class FrozenImageNetEncoder(nn.Module):
    """Pretrained MobileNetV3-Large with no cattle training: the transfer baseline."""

    def __init__(self) -> None:
        super().__init__()
        self.features = imagenet_backbone()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return F.adaptive_avg_pool2d(self.features(x), 1).flatten(1)


class MuzzleEmbedder(nn.Module):
    def __init__(self, embedding_dim: int = 512) -> None:
        super().__init__()
        self.features = imagenet_backbone()
        self.project = nn.Sequential(
            nn.Dropout(0.2),
            nn.Linear(BACKBONE_CHANNELS, embedding_dim),
            nn.BatchNorm1d(embedding_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        pooled = F.adaptive_avg_pool2d(self.features(x), 1).flatten(1)
        return self.project(pooled)


class ArcFaceHead(nn.Module):
    """Additive angular margin (Deng et al., 2019)."""

    def __init__(self, embedding_dim: int, num_classes: int, scale: float, margin: float) -> None:
        super().__init__()
        self.weight = nn.Parameter(torch.empty(num_classes, embedding_dim))
        nn.init.xavier_uniform_(self.weight)
        self.scale = scale
        self.margin = margin

    def forward(self, emb: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
        cos = F.linear(F.normalize(emb), F.normalize(self.weight)).clamp(-1 + 1e-7, 1 - 1e-7)
        target_cos = torch.cos(torch.acos(cos) + self.margin)
        # When theta + m passes pi the margin would increase the logit instead
        # of decreasing it, so fall back to the CosFace-style linear penalty.
        threshold = math.cos(math.pi - self.margin)
        fallback = cos - math.sin(math.pi - self.margin) * self.margin
        target_cos = torch.where(cos > threshold, target_cos, fallback)
        one_hot = F.one_hot(labels, cos.shape[1]).bool()
        return self.scale * torch.where(one_hot, target_cos, cos)


class SoftmaxHead(nn.Module):
    def __init__(self, embedding_dim: int, num_classes: int) -> None:
        super().__init__()
        self.fc = nn.Linear(embedding_dim, num_classes)

    def forward(self, emb: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
        return self.fc(emb)
