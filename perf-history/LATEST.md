# Performance budgets — 2026-11-13T16-27-04

Commit b92fb2e · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery False · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 13.3 | 14 / 12 / 13 | < 33 | pass |
| 10k Return p95 | 10.0 | 12 / 9 / 10 | < 33 | pass |
| 10k open | 536.4 | 524 / 556 / 536 | < 2500 | pass |
| 10k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 125.2 | 124 / 125 / 125 | < 200 | pass |
| 10k block move p95 | 17.2 | 18 / 17 / 17 | < 100 | pass |
| search (library) | 16.5 | 16 / 16 / 17 | < 500 | pass |
| link/tag index rebuild | 91.8 | 92 / 92 / 90 | < 3000 | pass |
| 20k keystroke p95 | 17.1 | 18 / 17 / 17 | < 33 | pass |
| 20k Return p95 | 15.0 | 16 / 15 / 15 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 1 / 0 / 1 | < 16.7 | pass |
| 20k open | 1092.8 | 1093 / 1108 / 1091 | < 5000 | pass |
| 20k toggle (known limit) | 252.0 | 250 / 252 / 252 | — | info |
| tab switch p95 | 32.2 | 32 / 32 / 33 | < 50 | pass |
| Space switch p95 | 59.2 | 59 / 51 / 70 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.6 | 0 / 1 / 1 | < 16.7 | pass |
| doc open from library | 132.8 | 128 / 133 / 133 | < 250 | pass |
| 1,000-item collection open | 84.0 | 84 / 85 / 81 | < 1000 | pass |
| 1,000-item collection scroll p95 | 3.7 | 3 / 4 / 4 | < 16.7 | pass |
| search index rebuild (10k blocks) | 107.1 | 106 / 107 / 108 | < 3000 | pass |
| search query p95 | 87.3 | 89 / 87 / 87 | < 500 | pass |
| panel format (warm) | 48.9 | 50 / 47 / 49 | < 100 | pass |
| panel format (first open) | 58.3 | 59 / 58 / 58 | — | info |
| panel style (warm) | 47.6 | 47 / 48 / 48 | < 100 | pass |
| panel style (first open) | 54.7 | 52 / 55 / 55 | — | info |
| panel info (warm) | 34.8 | 34 / 36 / 35 | < 100 | pass |
| panel info (first open) | 72.6 | 73 / 72 / 73 | — | info |
| panel share (warm) | 36.0 | 36 / 35 / 38 | < 100 | pass |
| panel share (first open) | 47.6 | 48 / 48 / 47 | — | info |
| panel assistant (warm) | 23.3 | 23 / 16 / 27 | < 100 | pass |
| panel assistant (first open) | 76.4 | 76 / 69 / 80 | — | info |
| panel recovery (warm) | 41.1 | 42 / 41 / 40 | < 100 | pass |
| panel recovery (first open) | 70.4 | 82 / 68 / 70 | — | info |
| sheet versionHistory render | 4.1 | 4 / 4 / 5 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 300.6 | 304 / 300 / 301 | — | info |
| sheet reviewSheet render | 35.9 | 36 / 36 / 36 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 345.3 | 351 / 345 / 344 | — | info |
| vault check 2,000 notes | 444.0 | 444 / 446 / 443 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 24.0 | 24 / 23 / 24 | < 500 | pass |
| migration check 2,000 notes | 487.0 | 512 / 484 / 487 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1565.0 | 1565 / 1569 / 1561 | < 5000 | pass |
| library rebuild 2,000 notes | 767.0 | 767 / 771 / 763 | < 3000 | pass |
| repair plan | 370.0 | 370 / 370 / 370 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
