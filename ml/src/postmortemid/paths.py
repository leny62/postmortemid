from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ML = REPO / "ml"
DATA = ML / "data"
RAW = DATA / "raw"
CACHE = DATA / "cache"
SPLITS = DATA / "splits"
CONFIGS = ML / "configs"
EXPERIMENTS = ML / "experiments"
ARTIFACTS = ML / "artifacts"
MOBILE_MODEL_ASSETS = REPO / "mobile" / "assets" / "model"
