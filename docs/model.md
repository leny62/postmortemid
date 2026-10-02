# Model

## Biometric input

The biometric is the muzzle print, the pattern of ridges and beads on the hairless skin of a cow's nose. The face is the planned comparator. In the full pipeline a smartphone photo goes through a detector that crops the muzzle (or the face). The public data used now are already crops, so the detector is not part of this demonstration.

## Embedding model (proposed)

```
muzzle crop
  -> 224 x 224, ImageNet normalisation
  -> MobileNetV3-Large features (ImageNet weights)
  -> global average pool (960)
  -> dropout 0.2 -> linear 960 to 512 -> batch norm
  -> L2 normalisation = embedding
```

It is trained with an ArcFace angular-margin head (scale 30, margin 0.3) over the training animals. The head is used only during training. After training, the network can embed any animal, including ones it has never seen, which is what verification needs.

Why these choices:

- **MobileNetV3-Large** fits on a low-cost Android phone, and its ImageNet weights mean far fewer labelled animals are needed than training from scratch. The paired study will have 100 to 150 animals. It was not chosen because it is the most accurate backbone.
- **ArcFace** separates identities by angle on a hypersphere. A softmax-trained copy of the same network is kept as a baseline, so the effect of the margin can be measured.
- **Scale 30, margin 0.3** are common defaults from metric-learning code, fixed before the reported run and not tuned. Deng et al. (2019) used scale 64 and margin 0.5 on large face datasets, and the AdaCos analysis (Zhang et al., 2019) suggests a smaller fixed scale for few classes, about sqrt(2) * ln(C - 1), roughly 7 for 157 animals. ArcFace and softmax are not separated in E0, so a dev-only sweep is left for the study data.
- **No horizontal flip** in augmentation. A mirrored muzzle is a different ridge pattern.

Training settings are in `ml/configs/e0.json`: 15 epochs, batch 48, AdamW with a one-cycle learning rate up to 5e-4, weight decay 1e-4, seed 42. Training on 157 animals takes about 5 minutes on an Apple M-series GPU.

## Templates and similarity

At enrolment the embeddings of k live images (k = 3 now) are L2-normalised, averaged and normalised again. A query is compared with the claimed animal's template by cosine similarity.

## Decision thresholds

Two thresholds are set on development animals only:

- tau(FAR 1%): the lowest score at which at most 1% of dev impostor comparisons are accepted
- tau(FAR 0.1%): the same at 0.1%

| Score | Decision |
|---|---|
| score >= tau(FAR 0.1%) | Match |
| tau(FAR 1%) <= score < tau(FAR 0.1%) | Review: a person looks at the case |
| score < tau(FAR 1%) | No match |

Thresholds are applied unchanged to test animals, and the FAR actually reached on test animals is reported next to the target. With the current dev set, tau(FAR 0.1%) is set by the 30th highest of 29,682 dev impostor scores, so it is exploratory.

TAR and FAR here are comparison-level rates: each query image compared once with one template, with images rejected by the quality check not counted. In ISO/IEC 19795-1 terms they are 1 - FNMR and FMR. A template made from 3 images is a multi-sample enrolment template (the mean of their embeddings). The thresholds are not scientifically final. They will be set again on the paired study data.

## Versioning

Every verification stored by the app records three versions:

| Version | Example | Meaning |
|---|---|---|
| Model | `pmid-mnv3-arcface-e0-v0.1` | Encoder that produced the embeddings |
| Threshold file | `e0-arcface-tflite-dev-v0.1` | Where tau(FAR 1%) and tau(FAR 0.1%) came from |
| App | `0.1.0+1` | Flutter build |

A template can only be compared with a query from the same model version.

## What runs on the phone today

The app runs `pmid-mnv3-arcface-e0-v0.1.tflite`, the ArcFace model above, exported to TensorFlow Lite in float32 (14.0 MB). LiteRT, the runtime used, is the current name of TensorFlow Lite; the model format is the same. ImageNet normalisation is part of the exported model. The phone resizes the whole image to 224 x 224 with an antialiased bilinear filter, the same filter PIL uses and close to the training resize.

The export was checked in three steps:

1. TFLite against PyTorch on 50 images: cosine similarity 1.000000 at the lowest.
2. Dev and test animals scored again with the TFLite model and the phone's resize. Thresholds for the app (tau(FAR 1%) = 0.399, tau(FAR 0.1%) = 0.541) come from dev animals. On test animals: ROC-AUC 0.993, EER 2.0%, TAR 96.3% at a realised FAR of 0.94%, close to the notebook's PyTorch numbers.
3. On the Android emulator, the on-device embedding of a fixed test pattern matched the laptop's (cosine 1.000000). Model inference took about 35 ms, and the whole photo-to-embedding path for a 720 x 720 JPEG about 280 ms; the first call, which starts the interpreter, about 430 ms. This is an emulator on a laptop, not a low-cost phone.

A first export used an area-average resize instead. It repeats pixels when enlarging, and since half the public crops are smaller than 224 px, the inputs looked different from training: test EER rose to 5.2% and the realised FAR at the 1% target was 3.5%. The resize was changed after these test numbers had been seen. Dev animals alone show the same gap (EER 4.4% with the area resize against 2.1% with bilinear), so the choice does not depend on the test set. Both runs are in `ml/experiments/README.md`, and the export script now scores test animals only when asked (`--score-test`).

The LBP histogram encoder (`pmid-lbp-demo-v0.1`) is still in the app as a fallback and can be selected with `export_app_manifest.py --encoder lbp`.

## Current limitations

- All measurements are live-to-live on public data. Post-mortem performance is unknown.
- No detector yet. Camera photos are cropped to the square guide the user fills with the muzzle; imported images are used whole, like the public crops.
- Inference time on a low-cost phone has not been measured yet, and reduced-precision weights have not been tried. LiteRT recommends checking accuracy after quantisation; for this model that means re-running the export scoring and re-setting the dev thresholds.
- The blur check uses the variance of the Laplacian (Pech-Pacheco et al., 2000), which also responds to contrast: pale, unpigmented muzzles score low even when in focus. A contrast-normalised measure is a candidate once pilot images exist.
- The quality limits are starting values from public images and will be checked against pilot images.
