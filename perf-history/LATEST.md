# Performance budgets — 2026-11-14T18-27-21

Commit b6619ef · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery True · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 16.4 | 35 / 13 / 16 | < 33 | noise |
| 10k Return p95 | 10.7 | 11 / 11 / 11 | < 33 | pass |
| 10k open | 592.9 | 570 / 593 / 594 | < 2500 | pass |
| 10k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 131.9 | 132 / 131 / 133 | < 200 | pass |
| 10k block move p95 | 16.9 | 17 / 18 / 17 | < 100 | pass |
| search (library) | 16.6 | 17 / 17 / 16 | < 500 | pass |
| link/tag index rebuild | 94.1 | 94 / 96 / 92 | < 3000 | pass |
| 20k keystroke p95 | 21.5 | 18 / 24 / 22 | < 33 | pass |
| 20k Return p95 | 17.2 | 17 / 18 / 17 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 20k open | 1156.5 | 1127 / 1156 / 1167 | < 5000 | pass |
| 20k toggle (known limit) | 250.5 | 250 / 260 / 250 | — | info |
| tab switch p95 | 40.7 | 41 / 40 / 43 | < 50 | pass |
| Space switch p95 | 69.0 | 69 / 71 / 57 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.7 | 1 / 1 / 1 | < 16.7 | pass |
| doc open from library | 143.4 | 135 / 144 / 143 | < 250 | pass |
| 1,000-item collection open | 92.0 | 92 / 79 / 96 | < 1000 | pass |
| 1,000-item collection scroll p95 | 3.8 | 5 / 4 / 3 | < 16.7 | pass |
| search index rebuild (10k blocks) | 110.9 | 111 / 110 / 111 | < 3000 | pass |
| search query p95 | 88.8 | 89 / 89 / 89 | < 500 | pass |
| panel format (warm) | 50.7 | 51 / 51 / 42 | < 100 | pass |
| panel format (first open) | 65.1 | 65 / 63 / 75 | — | info |
| panel style (warm) | 49.3 | 50 / 49 / 47 | < 100 | pass |
| panel style (first open) | 50.4 | 50 / 52 / 40 | — | info |
| panel info (warm) | 35.7 | 36 / 36 / 33 | < 100 | pass |
| panel info (first open) | 66.2 | 73 / 66 / 60 | — | info |
| panel share (warm) | 32.1 | 31 / 35 / 32 | < 100 | pass |
| panel share (first open) | 41.0 | 41 / 41 / 41 | — | info |
| panel assistant (warm) | 23.7 | 16 / 24 / 27 | < 100 | pass · slower than last (13) |
| panel assistant (first open) | 80.8 | 78 / 91 / 81 | — | info |
| panel recovery (warm) | 60.2 | 61 / 60 / 43 | < 100 | pass |
| panel recovery (first open) | 90.7 | 91 / 76 / 91 | — | info |
| sheet versionHistory render | 4.4 | 4 / 4 / 5 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 296.4 | 290 / 296 / 299 | — | info |
| sheet reviewSheet render | 37.6 | 38 / 36 / 38 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 346.0 | 346 / 335 / 347 | — | info |
| vault check 2,000 notes | 470.0 | 470 / 478 / 466 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 25.0 | 25 / 25 / 25 | < 500 | pass |
| migration check 2,000 notes | 516.0 | 522 / 516 / 509 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1632.0 | 1608 / 1658 / 1632 | < 5000 | pass |
| library rebuild 2,000 notes | 797.0 | 797 / 870 / 785 | < 3000 | pass |
| repair plan | 392.0 | 378 / 398 / 392 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
