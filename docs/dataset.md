# Dataset

## Public data used now

| | |
|---|---|
| Name | Beef Cattle Muzzle/Noseprint database for individual identification |
| Authors | Yijie Xiong, Guoming Li, Galen Erickson (University of Nebraska-Lincoln) |
| Record | Zenodo, [doi:10.5281/zenodo.6324361](https://doi.org/10.5281/zenodo.6324361) |
| Paper | Li, G., Erickson, G. E., and Xiong, Y. (2022). Individual beef cattle identification using muzzle images and deep learning techniques. *Animals*, 12(11), 1453. |
| Licence | [Creative Commons Attribution 4.0 (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) |
| Archive | `BeefCattle_Muzzle_database.zip`, 643,745,309 bytes, SHA-256 `0a4b519f300e0d96727c60f4515fd8cb6e2c74eaaa1f6fdc43d23b8e44693c1c` |
| Content | 4,923 JPEG muzzle crops in 268 folders, one folder per animal, 4 to 70 images each |
| Capture | Live feedlot cattle in the US Midwest, photographed from outside the pens between 11 March and 31 July 2021 with a Fujifilm X-T4 and a 70-300 mm lens (Li et al., 2022). Only 272 of the 4,923 crops keep EXIF data; those name a Fujifilm X-M1 (224) and a DJI Pocket (48). |

### Getting the data

```bash
uv run python ml/scripts/download_dataset.py
uv run python ml/scripts/prepare_data.py
```

The first command downloads the archive into `ml/data/raw/`, checks the SHA-256 and unpacks it. The second rebuilds the cleaned image table and split. The raw images are not committed to this repository.

Changes made under the CC BY 4.0 licence: no image is modified or redistributed as a file. This repository adds derived file-level metadata (file names, sizes, hashes, frame numbers) and split labels in `ml/data/splits/`. A few images appear, resized, in the notebook outputs and the app screenshots for illustration.

## Cleaning

### Duplicate identities

BC, Chaudhary and Nepal (2026) report 19 folders in this database that hold the same animal as another folder. Their paper says the list is released with their code, but the repository it links to could not be found on 2 October 2026. The cleaning here is therefore independent.

File names include the camera frame number (`cattle_0100_DSCF3856.jpg`). 50 pairs of folders contain crops of the same frame. That can mean the same animal filed twice, or two animals standing in one photo. For each pair, SIFT keypoints are matched between the same-frame crops (up to 6 frames). Crops of the same pixels give 12 to 147 median RANSAC inliers. Crops of different animals give 0 to 5. Pairs with a median of 10 or more are treated as one animal. This gives 7 duplicate folders across 6 animals:

```
cattle_2100, cattle_4451, cattle_5408, cattle_5508, cattle_6011, cattle_6283, cattle_8095
```

In each group the folder with the most images is kept. The full screen is in `ml/data/splits/shared_frame_screen.csv`.

BC et al. also flagged duplicates by camera-frame provenance, then confirmed them by visual review, and removed 19 folders (280 images). Their list was not available, so the overlap with these 7 is unknown. The difference probably lies in the decision rule: this screen needs identical frame numbers and a median of at least 10 SIFT inliers, and it does not look at folders whose frames are adjacent but not shared (for example `cattle_6458` and `cattle_6479`, both test animals, with frames 6981 to 7006 and 7029 to 7043). Some duplicates are therefore probably still present. The effect on results is discussed in the notebook (Sections 3.1 and 8).

### Near-duplicate images

Consecutive frames of a still animal are often almost identical. Within each animal, an image is removed if its 64-bit difference hash is within 2 bits of an image already kept (earliest frame first). This removes 1,429 images. Among 59,695 sampled pairs of different animals, none fall within 2 bits, so the cut removes near copies rather than ordinary variation. The 2-bit cut was chosen after the first protocol (E0-a) looked too easy; the notebook (Section 7) shows how the results change with stricter cuts.

### Result

| | Animals | Images |
|---|---|---|
| Raw download | 268 | 4,923 |
| After removing duplicate folders | 261 | 4,824 |
| After removing near-duplicates | 261 | 3,395 |

## Split

Animals are assigned to train, dev and test (60/20/20) with seed 42. Every image of an animal goes to the same split. `ml/data/splits/e0_images.csv` records the split for every image and is versioned in Git so results can be regenerated exactly.

| Split | Animals | Images | Used for |
|---|---|---|---|
| train | 157 | 2,047 | fitting the MobileNetV3 models |
| dev | 52 | 738 | threshold setting, LBP settings and training monitoring |
| test | 52 | 610 | reporting only, never training or thresholds (see `ml/experiments/README.md`) |

## Limitations of this data for the research question

- All animals are alive. There are no post-mortem images, so the data cannot answer RQ1 to RQ4.
- One US study, one main camera model. The study population (cattle at a Rwandan abattoir, two Android phones) is different.
- Images are already cropped to the muzzle, so they cannot train or test the detector.
- Enrolment and query images of an animal appear to come from one session. Where EXIF times exist (23 animals), each animal's images span at most 72 minutes on one day.

## Planned study data

The paired dataset will be collected at one Rwandan abattoir after ethics clearance, a facility agreement and any required permit, following Section 3.2.1 of the proposal: a study code card in every photo, live (T0) and immediate post-mortem (P0) muzzle and face images on two phones, and a countersigned daily log linking study code, ear tag and slaughter sequence. Ear tag numbers will be kept in a separate linkage file and never in the image dataset. None of this data exists yet.
