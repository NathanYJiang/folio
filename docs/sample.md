---
title: Reading notes
updated: 2026-11-12
---

# On simple tools

The best tools disappear. You open a file, you read it, you close it. Folio tries to be that: **a quiet window for markdown**, with editing one keystroke away when you need it.

> Simplicity is prerequisite for reliability.
> — Edsger W. Dijkstra

## What matters

- Typography that's comfortable for long reads
- A layout that stays out of the way
- Live reload, so docs written by scripts or agents update as you watch

### This week

- [x] Ship the viewer
- [x] Add side-by-side editing
- [ ] Write the release notes

## A little code

```python
def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

## A little math

The Gaussian integral, $\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}$, shows up everywhere. In display form:

$$
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
$$

## Shortcuts

| Action | Keys |
| --- | --- |
| Toggle editing | ⌘E |
| Side by side | ⌘3 |
| Find | ⌘F |
| Text size | ⌘+ / ⌘− |

---

That's the whole thing.
