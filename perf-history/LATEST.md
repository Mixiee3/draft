# Performance budgets — 2026-11-14T17-55-28

Commit d93096b · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery True · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 17.1 | 11 / 19 / 17 | < 33 | pass |
| 10k Return p95 | 10.9 | 11 / 13 / 7 | < 33 | pass |
| 10k open | 604.5 | 535 / 643 / 604 | < 2500 | pass |
| 10k scroll step p95 | 0.7 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 132.4 | 126 / 142 / 132 | < 200 | pass |
| 10k block move p95 | 18.2 | 18 / 18 / 18 | < 100 | pass |
| search (library) | 16.9 | 16 / 18 / 17 | < 500 | pass |
| link/tag index rebuild | 96.2 | 91 / 97 / 96 | < 3000 | pass |
| 20k keystroke p95 | 21.0 | 37 / 21 / 20 | < 33 | noise |
| 20k Return p95 | 18.2 | 17 / 18 / 18 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 0 / 1 / 1 | < 16.7 | pass |
| 20k open | 1180.4 | 1102 / 1246 / 1180 | < 5000 | pass |
| 20k toggle (known limit) | 274.7 | 254 / 277 / 275 | — | info |
| tab switch p95 | 42.3 | 38 / 51 / 42 | < 50 | noise |
| Space switch p95 | 77.5 | 67 / 84 / 78 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.7 | 1 / 1 / 1 | < 16.7 | pass |
| doc open from library | 146.1 | 146 / 144 / 156 | < 250 | pass |
| 1,000-item collection open | 87.0 | 87 / 58 / 93 | < 1000 | pass |
| 1,000-item collection scroll p95 | 5.4 | 5 / 5 / 6 | < 16.7 | pass |
| search index rebuild (10k blocks) | 111.1 | 111 / 111 / 114 | < 3000 | pass |
| search query p95 | 88.6 | 88 / 89 / 89 | < 500 | pass |
| panel format (warm) | 42.9 | 43 / 35 / 49 | < 100 | pass |
| panel format (first open) | 63.5 | 59 / 65 / 64 | — | info |
| panel style (warm) | 34.8 | 49 / 24 / 35 | < 100 | pass |
| panel style (first open) | 45.2 | 50 / 35 / 45 | — | info |
| panel info (warm) | 31.3 | 37 / 16 / 31 | < 100 | pass |
| panel info (first open) | 48.9 | 76 / 39 / 49 | — | info |
| panel share (warm) | 32.1 | 37 / 17 / 32 | < 100 | pass |
| panel share (first open) | 39.6 | 40 / 25 / 42 | — | info |
| panel assistant (warm) | 13.3 | 44 / 12 / 13 | < 100 | pass |
| panel assistant (first open) | 71.3 | 93 / 68 / 71 | — | info |
| panel recovery (warm) | 49.5 | 50 / 56 / 42 | < 100 | pass |
| panel recovery (first open) | 71.8 | 89 / 72 / 66 | — | info |
| sheet versionHistory render | 4.5 | 4 / 5 / 4 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 279.5 | 19 / 280 / 299 | — | info |
| sheet reviewSheet render | 38.5 | 37 / 39 / 38 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 332.3 | 347 / 317 / 332 | — | info |
| vault check 2,000 notes | 480.0 | 488 / 475 / 480 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 25.0 | 26 / 25 / 25 | < 500 | pass |
| migration check 2,000 notes | 521.0 | 550 / 503 / 521 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1704.0 | 1704 / 1646 / 1812 | < 5000 | pass |
| library rebuild 2,000 notes | 814.0 | 814 / 791 / 824 | < 3000 | pass |
| repair plan | 414.0 | 427 / 396 / 414 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
