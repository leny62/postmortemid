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
| Reproducibility | Three full notebook runs from a fresh kernel on the same machine gave identical test metrics for every model |

Test results (52 animals, 454 genuine and 22,700 impostor comparisons; SIFT uses 10 sampled impostors per query). Intervals are from E0-d; the point estimates are the same in both runs.

| Model | ROC-AUC | EER [95% CI] | TAR at dev FAR 1% threshold [95% CI] | Realised FAR [95% CI] | Rank-1 |
|---|---|---|---|---|---|
| SIFT | 0.968 | 7.7% [3.3, 10.5] | 75.1% [60.9, 87.0] | 0.18% [0.00, 0.59] | n/a |
| LBP, app fallback (64 px, 4 x 4) | 0.936 | 11.2% [6.2, 17.0] | 78.4% [69.2, 86.7] | 0.50% [0.13, 1.12] | 92.5% |
| MobileNetV3-Large, ImageNet frozen | 0.968 | 6.6% [3.6, 10.4] | 88.5% [81.9, 94.1] | 0.50% [0.17, 0.99] | 92.5% |
| MobileNetV3-Large, softmax | 0.993 | 2.5% [0.9, 5.7] | 95.6% [91.3, 98.9] | 0.89% [0.35, 1.67] | 96.0% |
| MobileNetV3-Large, ArcFace (proposed) | 0.994 | 2.2% [0.5, 5.6] | 96.5% [92.4, 99.5] | 0.87% [0.32, 1.72] | 97.1% |

Notes:

- ArcFace and softmax intervals overlap; E0 does not separate them.
- At the exploratory 0.1% target, realised FAR was 0.12% (softmax) and 0.17% (ArcFace), above target.
- Open-set rejection at the FAR 1% threshold is 64.8% for ArcFace. A 1:N gallery search needs a stricter threshold than 1:1 verification.
- The weakest genuine scores come from blurred queries of one animal; 16 rejected genuine queries come from 4 animals.
- LBP dev thresholds exported to the app: tau(FAR 1%) = 0.9199, tau(FAR 0.1%) = 0.9260 (`e0-lbp-dev-v0.1`).

## E0-c: ArcFace exported to TFLite for the phone

| | |
|---|---|
| Date | 2 October 2026 |
| Model | E0-b ArcFace weights, retrained with `ml/scripts/train_arcface.py` (test metrics checked equal to the notebook before saving) |
| Export | `ml/scripts/export_tflite.py`, litert-torch 0.9.4 with torch 2.13 in an isolated environment, float32, 14.0 MB, ImageNet normalisation inside the model |
| Check | TFLite against PyTorch on 50 images: minimum cosine 1.000000 |

First attempt (not shipped): the phone resized with an area average, which repeats pixels when enlarging small crops. Test: ROC-AUC 0.982, EER 5.2%, TAR 92.3% at a realised FAR of 3.5% (target 1%). The inputs no longer looked like the training images.

Order of events: the first export printed test metrics, and the resize was changed after seeing them. The same comparison on dev animals alone gives the same answer (EER 4.4% with the area resize, 2.1% with bilinear; ROC-AUC 0.988 and 0.999), so the choice does not depend on the test set. Test animals have been scored by the notebook and by each export, never used for training or thresholds. `export_tflite.py` now scores dev animals only, unless run with `--score-test`.

Second attempt (shipped): antialiased bilinear resize, PIL's filter in floats, matching training. Dev thresholds tau(FAR 1%) = 0.3991 and tau(FAR 0.1%) = 0.5415 (`e0-arcface-tflite-dev-v0.1`). Test: ROC-AUC 0.993, EER 2.0%, TAR 96.3% at a realised FAR of 0.94%, TAR 93.0% at a realised FAR of 0.19% (target 0.1%), Rank-1 96.9%. Full numbers in `e0_tflite.json`.

On-device check (Android emulator on an Apple M5 Pro laptop, `flutter test integration_test`): output for a fixed test pattern matched the laptop (cosine 1.000000); 71 ms first inference, 21.5 ms mean over 10 runs, excluding image decoding. Not representative of a low-cost phone. Superseded by the timing in E0-d, after the interpreter was made long-lived.

App check on the emulator: a genuine test-split query scored 0.898 (Match) and an impostor 0.018 (No match).

## E0-d: evaluation fixes and app re-check

| | |
|---|---|
| Date | 2 October 2026 |
| Models and data | Unchanged from E0-b; every point estimate is identical |
| Bootstrap | 2,000 resamples (as in the proposal) instead of 1,000. Each resample draws animals and weights every comparison by how often its animals were drawn, so the template animal of an impostor pair is resampled too (subsets bootstrap, Bolle, Ratha and Pankanti, 2004). The EER and TAR intervals barely change; the realised-FAR interval, newly reported, is about 1.7 times wider than with query-only resampling |
| k comparison | Now on the same queries for every k (images from the 6th onwards; 46 test animals, 352 queries). ArcFace EER 3.1% (k = 1), 3.0% (k = 3), 2.2% (k = 5); LBP 14.5%, 13.0%, 11.9% |
| Near-duplicate sensitivity | ArcFace model fixed, dev and test images re-cleaned. Test EER 2.2% at 0 bits (701 genuine), 2.2% at 2 bits (454), 3.4% at 4 bits (229), 3.9% at 6 bits (115). The 2-bit cut was chosen after E0-a, so the reported numbers are optimistic for photos taken further apart |
| TFLite export | Re-run with the new script: identical model file (SHA-256 `27e24519...2353`) and thresholds; dev ROC-AUC 0.999, dev EER 2.1% |

On-device check after the interpreter was made long-lived (Android 17 emulator, same laptop): output for the fixed test pattern matched the laptop (cosine 1.000000); model inference 35.2 ms mean over 10 runs; first call 427 ms (starts the interpreter isolate); whole photo-to-embedding path for a 720 x 720 JPEG 279 ms mean over 5 runs. Release APK for arm64: 49 MB.

App check on the emulator (release build, test-split images): a genuine query scored 0.758 (Match) and an impostor 0.210 (No match). These are different query images from the E0-c check.

## App quality limits (from E0 data)

| | |
|---|---|
| Data | 2,278 public images with short side of at least 256 px |
| Limits | min side 256 px, brightness 50 to 220, sharpness (Laplacian variance at 256 px) at least 15 |
| Effect | 0.3% too dark, 0.2% too bright, 1.0% too blurry on these images |
| Notes | Pale, unpigmented muzzles score low on sharpness even when in focus. Check on pilot images. |
