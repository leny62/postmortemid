# Experiment plan

This document separates what has been run (E0) from what the research study will run (E1 to E7). The experiment IDs match Table 8 of the proposal.

## E0: public-data baseline (done, initial demonstration)

| | |
|---|---|
| Question | Does the pipeline work end to end, and how well do the baselines and the proposed model verify unseen live animals? |
| Data | Xiong et al. (2022) public muzzle database, cleaned as in [dataset.md](dataset.md): 261 animals, 3,395 images |
| Split | Identity-disjoint, 157 train / 52 dev / 52 test animals, seed 42 |
| Enrolment | First 3 images in capture order form the template; all later images are queries |
| Comparisons | Each query against its own template (genuine) and every other template in the split (impostor) |
| Thresholds | tau(FAR 1%) and tau(FAR 0.1%) set on dev impostor scores, then applied unchanged to test |
| Models | SIFT matching; LBP histogram (app fallback encoder); frozen ImageNet MobileNetV3-Large; MobileNetV3-Large trained with softmax; MobileNetV3-Large trained with ArcFace (proposed) |
| Metrics | ROC-AUC, EER, TAR at calibrated FAR 1% and 0.1% with realised test FAR, oracle TAR, Rank-1, open-set rejection, 95% bootstrap CIs (2,000 resamples of test animals; both animals of each comparison are resampled) |
| Config | `ml/configs/e0.json` |
| Notebook | `ml/notebooks/01_e0_public_baseline.ipynb` |
| Results | `ml/experiments/e0_results.json`, summarised in `ml/experiments/README.md` |

### Leakage prevention in E0

1. Duplicate folders that hold the same animal are removed before splitting, so one animal cannot sit in two splits under two names.
2. Animals, not images, are split. `splits.check_disjoint` fails if an animal or an identical file appears in two splits.
3. Near-identical frames within an animal are removed, so a query cannot match its own near copy in the template.
4. The fine-tuned models see train animals only. The dev curve is logged for monitoring, but the final epoch is always used, so dev animals do not choose the checkpoint.
5. LBP settings and all thresholds are chosen on dev animals. Test animals are used only for reporting. They were scored by the notebook and by the TFLite export; the export's preprocessing was changed after its first test scores, and dev data alone support the same change (see `ml/experiments/README.md`, E0-c).

### What E0 does not show

E0 is a live-to-live check on one herd photographed in one session. It does not show anything about post-mortem verification, the face comparator, phone changes or Rwandan cattle.

## Planned research experiments

These need the paired dataset from the abattoir. None have been run.

| ID | Experiment | Enrolment to query | Question |
|---|---|---|---|
| E1 | Live-to-live reference, muzzle | T0 burst 1 to T0 burst 2, same phone | RQ1 reference |
| E2 | Live-to-post-mortem, muzzle (core) | T0 to P0, same phone; all baselines and the proposed model; k = 1, 3, 5 | RQ1, H1 |
| E3 | Muzzle against face | E1 and E2 repeated on face crops | RQ2, H2 |
| E4 | Device variation | T0 on phone A to P0 on phone B, and the reverse | RQ3, H3 |
| E5 | Time since slaughter | E2 scores against post-mortem interval | RQ4, H4 |
| E6 | Open-set rejection | P0 queries against galleries without their own template | RQ1 (supporting) |
| E7 | Post-mortem adaptation (optional) | E2 with a model adapted on dev post-mortem images, only if E2 shows a clear drop | Exploratory |
| On-device | Final model on both phones | Model size, inference time, agreement with desktop scores | Objective 3 |

For the paired data, animals are split into development and test sets within each collection day. Thresholds come from out-of-fold scores in an animal-level cross-validation on development animals. Confidence intervals resample animals 2,000 times, and differences between conditions are computed inside each resample so they stay paired by animal.

## Next steps from E0

1. Re-run the E0 protocol with the cleaned identity list from BC et al. (2026) if it becomes available, and compare.
2. Label muzzle and face boxes on pilot images and train a small YOLO detector (detection is evaluated separately from verification).
3. Measure on-device time and score agreement on the two study phones (the export and an emulator check are done), and test reduced-precision weights.
4. Run the pilot DINOv2 sanity check on the first linked live and post-mortem pairs, as described in the proposal.
