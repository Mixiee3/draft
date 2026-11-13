# Performance budgets — 2026-11-13T20-41-01

Commit d5e1d67 · 3 runs · median judged · Mac16,12 (Apple M4), macOS 27.0.1, 16 GB · low power False · battery False · displays 1470 x 956 @ 60.00Hz
Reduce Motion unknown · Increase Contrast unknown · Reduce Transparency unknown

| Check | Median ms | Runs | Budget | Result |
|---|---|---|---|---|
| 10k keystroke p95 | 20.1 | 20 / 19 / 25 | < 33 | pass |
| 10k Return p95 | 10.5 | 14 / 10 / 10 | < 33 | pass |
| 10k open | 557.5 | 558 / 558 / 566 | < 2500 | pass |
| 10k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 10k toggle | 132.7 | 133 / 131 / 134 | < 200 | pass |
| 10k block move p95 | 14.3 | 15 / 14 / 14 | < 100 | pass |
| search (library) | 16.8 | 17 / 17 / 17 | < 500 | pass |
| link/tag index rebuild | 94.3 | 95 / 94 / 93 | < 3000 | pass |
| 20k keystroke p95 | 24.3 | 23 / 31 / 24 | < 33 | pass |
| 20k Return p95 | 21.8 | 18 / 22 / 22 | < 33 | pass |
| 20k scroll step p95 | 0.6 | 1 / 1 / 1 | < 16.7 | pass |
| 20k open | 1143.3 | 1143 / 1130 / 1163 | < 5000 | pass |
| 20k toggle (known limit) | 259.6 | 261 / 258 / 260 | — | info |
| tab switch p95 | 42.2 | 42 / 37 / 50 | < 50 | pass |
| Space switch p95 | 68.4 | 68 / 56 / 68 | < 100 | pass |
| 2,000-block doc scroll p95 | 0.7 | 1 / 1 / 1 | < 16.7 | pass |
| doc open from library | 143.7 | 144 / 130 / 146 | < 250 | pass |
| 1,000-item collection open | 94.0 | 82 / 95 / 94 | < 1000 | pass |
| 1,000-item collection scroll p95 | 5.1 | 4 / 5 / 5 | < 16.7 | pass |
| search index rebuild (10k blocks) | 108.8 | 109 / 110 / 109 | < 3000 | pass |
| search query p95 | 88.0 | 88 / 88 / 88 | < 500 | pass |
| panel format (warm) | 47.1 | 47 / 42 / 47 | < 100 | pass |
| panel format (first open) | 74.7 | 75 / 82 / 66 | — | info |
| panel style (warm) | 46.5 | 46 / 48 / 33 | < 100 | pass |
| panel style (first open) | 47.8 | 54 / 48 / 44 | — | info |
| panel info (warm) | 35.7 | 37 / 34 / 36 | < 100 | pass |
| panel info (first open) | 74.1 | 74 / 74 / 61 | — | info |
| panel share (warm) | 39.8 | 41 / 40 / 37 | < 100 | pass |
| panel share (first open) | 49.6 | 50 / 51 / 49 | — | info |
| panel assistant (warm) | 22.6 | 34 / 17 / 23 | < 100 | pass |
| panel assistant (first open) | 79.8 | 86 / 79 / 80 | — | info |
| panel recovery (warm) | 28.1 | 23 / 28 / 43 | < 100 | pass |
| panel recovery (first open) | 93.7 | 96 / 94 / 86 | — | info |
| sheet versionHistory render | 4.4 | 4 / 3 / 5 | < 100 | pass |
| sheet versionHistory on screen (incl. AppKit animation) | 307.9 | 308 / 308 / 304 | — | info |
| sheet reviewSheet render | 37.1 | 37 / 35 / 37 | < 100 | pass |
| sheet reviewSheet on screen (incl. AppKit animation) | 349.3 | 350 / 327 / 349 | — | info |
| vault check 2,000 notes | 461.0 | 471 / 461 / 460 | < 2000 | pass |
| Version History 30 versions, 2,000 blocks | 24.0 | 24 / 24 / 24 | < 500 | pass |
| migration check 2,000 notes | 494.0 | 507 / 494 / 494 | < 5000 | pass |
| migration schema 1→2, 2,000 notes | 1616.0 | 1586 / 1635 / 1616 | < 5000 | pass |
| library rebuild 2,000 notes | 788.0 | 795 / 784 / 788 | < 3000 | pass |
| repair plan | 389.0 | 372 / 393 / 389 | < 2000 | pass |

*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations).
