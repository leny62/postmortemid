# Experiment log

One entry per meaningful run, including runs that were replaced. Full numbers for the current run are in `e0_results.json`, written by the notebook.

## E0-a: first protocol (superseded, dev only)

| | |
|---|---|
| Date | 2 October 2026 |
| Dataset | Xiong et al. (2022), 7 duplicate folders removed: 261 animals, 4,824 images |
| Split | Identity-disjoint 157 / 52 / 52, seed 42 |
| Protocol | k = 3 enrolment images chosen at random per animal; no near-duplicate removal |
| Models | LBP (4 settings), frozen ImageNet MobileNetV3-Large, MobileNetV3-Large with ArcFace and with softmax (15 epochs) |
| Result (dev only) | LBP 64/4 EER 6.9%; ImageNet EER 3.3%; softmax EER 1.2%, TAR@FAR1% 98.4%; ArcFace EER 1.2%, TAR@FAR1% 98.7%. Dev ROC-AUC was already 0.997 after one ArcFace epoch. |
| Notes | The task looked too easy. About 7% of same-animal image pairs were within 2 bits of each other on a 64-bit difference hash, while no sampled cross-animal pair was, so many queries had a near copy in their own template. Replaced by E0-b. Test animals were never scored under this protocol. |

## E0-b: current protocol (reported)

| | |
|---|---|
| Date | 2 October 2026 |
| Dataset | As E0-a, plus within-animal near-duplicate removal (dHash within 2 bits): 261 animals, 3,395 images |
| Split | Identity-disjoint 157 train / 52 dev / 52 test animals, seed 42 (`ml/data/splits/e0_images.csv`) |
| Protocol | First 3 images in capture order enrol, later images query; all-vs-all within split; thresholds from dev impostors |
| Config | `ml/configs/e0.json` |
| Environment | Python 3.12.13, PyTorch 2.14.1, Apple MPS |
| Reproducibility | Two full notebook runs from a fresh kernel gave identical test metrics for every model |

Test results (52 animals, 454 genuine and 22,700 impostor comparisons; SIFT uses 10 sampled impostors per query):

| Model | ROC-AUC | EER [95% CI] | TAR at dev FAR 1% threshold [95% CI] | Realised FAR | Rank-1 |
|---|---|---|---|---|---|
| SIFT | 0.968 | 7.7% [3.8, 10.2] | 75.1% [61.6, 87.1] | 0.18% | n/a |
| LBP, on-device demo (64 px, 4 x 4) | 0.936 | 11.2% [6.3, 16.4] | 78.4% [69.2, 86.8] | 0.50% | 92.5% |
| MobileNetV3-Large, ImageNet frozen | 0.968 | 6.6% [3.6, 10.2] | 88.5% [82.1, 94.1] | 0.50% | 92.5% |
| MobileNetV3-Large, softmax | 0.993 | 2.5% [0.9, 5.7] | 95.6% [91.3, 99.0] | 0.89% | 96.0% |
| MobileNetV3-Large, ArcFace (proposed) | 0.994 | 2.2% [0.7, 5.5] | 96.5% [92.5, 99.5] | 0.87% | 97.1% |

Notes:

- ArcFace and softmax intervals overlap; E0 does not separate them.
- At the exploratory 0.1% target, realised FAR was 0.12% (softmax) and 0.17% (ArcFace), above target.
- Open-set rejection at the FAR 1% threshold is 64.8% for ArcFace. A 1:N gallery search needs a stricter threshold than 1:1 verification.
- The weakest genuine scores come from blurred queries of one animal; 16 rejected genuine queries come from 4 animals.
- LBP dev thresholds exported to the app: tau(FAR 1%) = 0.9199, tau(FAR 0.1%) = 0.9260 (`e0-lbp-dev-v0.1`).

## App quality limits (from E0 data)

| | |
|---|---|
| Data | 2,278 public images with short side of at least 256 px |
| Limits | min side 256 px, brightness 50 to 220, sharpness (Laplacian variance at 256 px) at least 15 |
| Effect | 0.3% too dark, 0.2% too bright, 1.0% too blurry on these images |
| Notes | Pale, unpigmented muzzles score low on sharpness even when in focus. Check on pilot images. |
