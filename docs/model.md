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

Thresholds are applied unchanged to test animals, and the FAR actually reached on test animals is reported next to the target. With the current dev set, tau(FAR 0.1%) rests on only a few impostor scores, so it is exploratory. The thresholds are not scientifically final. They will be set again on the paired study data.

## Versioning

Every verification stored by the app records three versions:

| Version | Example | Meaning |
|---|---|---|
| Model | `pmid-lbp-demo-v0.1` | Encoder that produced the embeddings |
| Threshold file | `e0-lbp-dev-v0.1` | Where tau(FAR 1%) and tau(FAR 0.1%) came from |
| App | `0.1.0+1` | Flutter build |

A template can only be compared with a query from the same model version.

## What runs on the phone today

The app currently uses `pmid-lbp-demo-v0.1`, a uniform LBP histogram descriptor (64 x 64 grayscale, 4 x 4 grid, 944 dimensions), because the MobileNetV3 model has not yet been exported to TensorFlow Lite. LBP is a real, measured baseline in the notebook, and its thresholds come from the same E0 dev animals, but it is weaker than the CNN models and it is **not** the research model. The app says this on the home screen and on every result.

## Current limitations

- All measurements are live-to-live on public data. Post-mortem performance is unknown.
- No detector yet; the app uses the centre square of the photo, which the camera guide asks the user to fill with the muzzle.
- The ArcFace model is trained and evaluated in Python but not yet on the phone.
- The quality limits are starting values from public images and will be checked against pilot images.
