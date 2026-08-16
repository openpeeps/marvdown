# Marvdown

> [!NOTE]
> Marvdown is a stupid simple Markdown parser written in [Nim](https://nim-lang.org).

## Quick Start

Marvdown converts **markdown** into `HTML`. It handles *emphasis*, ~~strikethrough~~,
[links](https://github.com/openpeeps/marvdown), images and more.

```nim
import marvdown

echo marvdown.toHtml("Hello **world**")
```

## Feature Highlights

- GitHub-style alerts (`> [!WARNING]`, `> [!TIP]`, …)
- Footnotes: referenced like this[^1]
- Tables with an optional footer

| Project | Language | Notes |
| ------- | -------- | ----- |
| powpow  | Nim      | HTTP/1.1 + WebSocket server |
| ozark   | Nim      | macro-based ORM |
| emitter | Nim      | event emitter |
|-------- |--------- |------- |
| Total   | 3        | (footer row) |

- [x] task list item (done)
- [ ] task list item (todo)

## Reference links

Reference links reuse a single definition, e.g. the [OpenPeeps organization][openpeeps].

[openpeeps]: https://github.com/openpeeps

## Footnotes

[^1]: Footnotes are collected automatically and rendered at the end of the document.
