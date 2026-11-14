# Performance budgets — 2026-11-14T16-38-10

Commit 391e4e3 · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery True · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 11.9 | 13 / 12 / 12 | < 33 | pass |
| 10k Return p95 | 10.7 | 10 / 11 / 11 | < 33 | pass |
| 10k open | 552.6 | 534 / 553 / 561 | < 2500 | pass |
| 10k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 129.5 | 129 / 130 / 130 | < 200 | pass |
| 10k block move p95 | 18.7 | 18 / 19 / 19 | < 100 | pass |
| search (library) | 16.8 | 17 / 17 / 16 | < 500 | pass |
| link/tag index rebuild | 93.6 | 94 / 94 / 92 | < 3000 | pass |
| 20k keystroke p95 | 17.1 | 17 / 39 / 17 | < 33 | noise |
| 20k Return p95 | 16.2 | 15 / 16 / 17 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 20k open | 1145.7 | 1181 / 1138 / 1146 | < 5000 | pass |
| 20k toggle (known limit) | 260.2 | 267 / 260 / 259 | — | info |
| tab switch p95 | 39.1 | 39 / 41 / 37 | < 50 | pass |
| Space switch p95 | 67.2 | 64 / 74 / 67 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| doc open from library | 141.7 | 144 / 142 / 138 | < 250 | pass |
| 1,000-item collection open | 84.0 | 84 / 78 / 95 | < 1000 | pass |
| 1,000-item collection scroll p95 | 4.6 | 5 / 4 / 5 | < 16.7 | pass |
| search index rebuild (10k blocks) | 109.9 | 110 / 109 / 112 | < 3000 | pass |
| search query p95 | 88.2 | 88 / 88 / 90 | < 500 | pass |
| panel format (warm) | 51.9 | 50 / 60 / 52 | < 100 | pass |
| panel format (first open) | 58.1 | 62 / 52 / 58 | — | info |
| panel style (warm) | 49.5 | 50 / 44 / 50 | < 100 | pass |
| panel style (first open) | 47.0 | 44 / 51 / 47 | — | info |
| panel info (warm) | 35.8 | 36 / 36 / 36 | < 100 | pass |
| panel info (first open) | 67.8 | 68 / 76 / 54 | — | info |
| panel share (warm) | 37.9 | 38 / 38 / 38 | < 100 | pass |
| panel share (first open) | 46.6 | 49 / 47 / 43 | — | info |
| panel assistant (warm) | 13.8 | 14 / 15 / 13 | < 100 | pass |
| panel assistant (first open) | 86.1 | 86 / 82 / 89 | — | info |
| panel recovery (warm) | 43.6 | 39 / 44 / 55 | < 100 | pass · slower than last (28) |
| panel recovery (first open) | 71.1 | 71 / 76 / 65 | — | info |
| sheet versionHistory render | 5.0 | 5 / 4 / 5 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 299.1 | 299 / 292 / 302 | — | info |
| sheet reviewSheet render | 37.2 | 37 / 37 / 38 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 344.2 | 322 / 344 / 347 | — | info |
| vault check 2,000 notes | 463.0 | 463 / 463 / 464 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 25.0 | 25 / 25 / 25 | < 500 | pass |
| migration check 2,000 notes | 507.0 | 501 / 507 / 518 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1621.0 | 1595 / 1621 / 1633 | < 5000 | pass |
| library rebuild 2,000 notes | 808.0 | 808 / 779 / 824 | < 3000 | pass |
| repair plan | 389.0 | 389 / 388 / 405 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
