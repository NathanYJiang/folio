const SAMPLE = `---
title: Field notes
tags: reading, design
---

# Field notes

A quiet place to **read** and *write* markdown. Links like [the docs](https://example.com) open in your browser, and [relative links](./other.md) open right here.

## Lists and tasks

- Clean typography with a comfortable measure
- Code highlighting, tables, math
  - Nested items work too

- [x] Render GFM task lists
- [ ] Click a checkbox to toggle it in the file

> Simplicity is prerequisite for reliability.
> — Edsger Dijkstra

## Code

\`\`\`ts
export function greet(name: string) {
  return \`hello, \${name}\`;
}
\`\`\`

Inline \`code\` looks like this.

## Math

Euler's identity $e^{i\\pi} + 1 = 0$, and a block:

$$
\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}
$$

## Table

| Feature | Shortcut |
| --- | --- |
| Quick open | ⌘P |
| Toggle edit | ⌘E |
| Split view | ⌘3 |

---

### Footer

That's it.
`;

let content = SAMPLE;
let prefs = '';

export async function mockNative(cmd, args) {
  switch (cmd) {
    case 'init': return { path: '/Users/me/notes/Field notes.md', home: '/Users/me', mode: 'read', prefs };
    case 'setPrefs': prefs = args.json; return true;
    case 'stat': return { exists: true, isDir: false, mtime: 1 };
    case 'readFile': return { content, mtime: 1 };
    case 'writeFile': content = args.content; return { mtime: 1 };
    default: return null;
  }
}
