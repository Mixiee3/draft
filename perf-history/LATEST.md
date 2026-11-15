# Performance budgets — 2026-11-15T16-26-13

Commit 6562511 · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery True · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 20.6 | 21 / 13 / 21 | < 33 | pass |
| 10k Return p95 | 10.8 | 12 / 11 / 11 | < 33 | pass |
| 10k open | 553.0 | 518 / 553 / 591 | < 2500 | pass |
| 10k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 130.5 | 136 / 127 / 130 | < 200 | pass |
| 10k block move p95 | 22.3 | 23 / 17 / 22 | < 100 | pass |
| search (library) | 16.3 | 16 / 16 / 16 | < 500 | pass |
| link/tag index rebuild | 91.0 | 90 / 91 / 92 | < 3000 | pass |
| 20k keystroke p95 | 26.5 | 23 / 26 / 28 | < 33 | pass |
| 20k Return p95 | 18.1 | 15 / 19 / 18 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 20k open | 1111.4 | 1089 / 1111 / 1138 | < 5000 | pass |
| 20k toggle (known limit) | 259.2 | 261 / 259 / 254 | — | info |
| tab switch p95 | 35.8 | 43 / 36 / 35 | < 50 | pass |
| Space switch p95 | 67.1 | 63 / 67 / 67 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| doc open from library | 132.7 | 127 / 133 / 136 | < 250 | pass |
| 1,000-item collection open | 89.0 | 90 / 67 / 89 | < 1000 | pass |
| 1,000-item collection scroll p95 | 3.5 | 3 / 4 / 4 | < 16.7 | pass |
| search index rebuild (10k blocks) | 105.0 | 103 / 105 / 106 | < 3000 | pass |
| search query p95 | 85.8 | 85 / 86 / 86 | < 500 | pass |
| panel format (warm) | 42.7 | 42 / 43 / 43 | < 100 | pass |
| panel format (first open) | 68.3 | 78 / 66 / 68 | — | info |
| panel style (warm) | 42.0 | 53 / 42 / 38 | < 100 | pass |
| panel style (first open) | 47.2 | 46 / 64 / 47 | — | info |
| panel info (warm) | 38.1 | 36 / 39 / 38 | < 100 | pass |
| panel info (first open) | 66.6 | 71 / 64 / 67 | — | info |
| panel share (warm) | 40.2 | 39 / 40 / 41 | < 100 | pass |
| panel share (first open) | 47.9 | 48 / 43 / 48 | — | info |
| panel assistant (warm) | 13.4 | 13 / 29 / 12 | < 100 | pass |
| panel assistant (first open) | 84.4 | 81 / 85 / 84 | — | info |
| panel recovery (warm) | 46.4 | 41 / 46 / 48 | < 100 | pass |
| panel recovery (first open) | 88.6 | 89 / 87 / 90 | — | info |
| sheet versionHistory render | 3.4 | 3 / 4 / 3 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 307.9 | 316 / 303 / 308 | — | info |
| sheet reviewSheet render | 34.3 | 34 / 34 / 35 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 357.8 | 358 / 360 / 348 | — | info |
| vault check 2,000 notes | 435.0 | 435 / 440 / 435 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 23.0 | 24 / 23 / 23 | < 500 | pass |
| migration check 2,000 notes | 476.0 | 476 / 475 / 477 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1553.0 | 1554 / 1552 / 1553 | < 5000 | pass |
| library rebuild 2,000 notes | 757.0 | 757 / 757 / 795 | < 3000 | pass |
| repair plan | 365.0 | 365 / 365 / 365 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
