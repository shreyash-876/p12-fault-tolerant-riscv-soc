# Codec delay / area table (Vivado, xc7z010clg400-1, out of context, routed, clock constrained at 5 ns)

| Variant | Hand XORs / literals | Hand depth | LUTs | FFs | Logic levels | Path delay (ns) | Fmax (MHz) | Slack at 50 MHz (ns) |
|---|---|---|---|---|---|---|---|---|
| enc IMPL 0 (behavioural) | 89 before sharing | - | 21 | 71 | 2 | 2.938 | 334.1 | 17.007 |
| enc IMPL 1 (flat) | 89 | 13 (as written) | 21 | 71 | 2 | 2.618 | 374.1 | 17.327 |
| enc IMPL 2 (CSE) | 71 | 4 | 21 | 71 | 2 | 2.672 | 373.0 | 17.319 |
| enc IMPL 3 (tree) | 89 | 4 | 21 | 71 | 2 | 2.503 | 398.4 | 17.490 |
| enc IMPL 2 (CSE), ECC_KEEP | 71 | 4 | 71 | 71 | 4 | 4.345 | 227.3 | 15.600 |
| enc IMPL 3 (tree), ECC_KEEP | 89 | 4 | 80 | 71 | 4 | 4.261 | 231.8 | 15.686 |
| dec IMPL 0 (behavioural) | - | - | 93 | 95 | 4 | 4.565 | 216.5 | 15.380 |
| dec IMPL 1 (flat) | 89+7 XOR, 273 corr. literals | 14 + compare | 93 | 95 | 5 | 4.629 | 217.4 | 15.400 |
| dec IMPL 2 (CSE) | 71+7 XOR, 273 corr. literals | 5 + compare | 87 | 95 | 4 | 4.773 | 209.3 | 15.222 |
| dec IMPL 3 (ESPRESSO) | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 135 | 95 | 6 | 5.184 | 190.9 | 14.763 |
| dec IMPL 2 (CSE), ECC_KEEP | 71+7 XOR, 273 corr. literals | 5 + compare | 143 | 95 | 7 | 5.330 | 185.8 | 14.618 |
| dec IMPL 3 (ESPRESSO), ECC_KEEP | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 194 | 95 | 8 | 5.723 | 174.5 | 14.270 |
| dec IMPL 2 (CSE), PIPE 1 | 71+7 XOR, 273 corr. literals | 5 + compare | 85 | 142 | 1 | 3.377 | 295.7 | 16.618 |
| dec IMPL 3 (ESPRESSO), PIPE 1 | 89+7 XOR, 168 corr. literals (ESPRESSO) | 5 + 3-input AND | 129 | 142 | 2 | 3.697 | 270.0 | 16.296 |
