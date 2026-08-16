<p align="center">
    <img src="https://raw.githubusercontent.com/openpeeps/marvdown/main/.github/marvdown-logo.png" width="128px"><br>
    This is Marvdown ⚡️ A stupid simple Markdown parser
</p>

<p align="center">
  <code>nimble install marvdown</code>
</p>

<p align="center">
  <a href="https://openpeeps.github.io/marvdown/">API reference</a> | <a href="https://github.com/openpeeps/marvdown/releases">Download</a><br><br>
  <img src="https://github.com/openpeeps/marvdown/workflows/test/badge.svg" alt="Github Actions"> <img src="https://github.com/openpeeps/marvdown/workflows/docs/badge.svg" alt="Github Actions">
</p>

> [!NOTE]  
> Marv is still in early development. Some features are not fully implemented yet. Contributions are welcome!

## 😍 Key Features
- [x] Extremely Fast & Lightweight! [Check benchmarks](#benchmarks)
- [x] Compiled cross-platform CLI app
- [x] Nim library for easy integration in your 👑 Nim projects
- [x] Markdown to HTML
  - [x] Auto-generate heading IDs for anchor links
  - [x] Table of contents data via `getSelectorItems`
- [x] Markdown to JSON (AST)
- [x] GitHub Flavored Markdown (partial): strikethrough, tables, task lists, autolinks, alerts
- [x] GitHub-style alerts (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`)
- [x] Footnotes
- [x] Reference-style links
- [x] Bare URL & email autolinks
- [x] YAML front matter
- [x] Components: `@include` files, `@attr` props & `$variable` interpolation
- [x] Lazy-loading for iframes, videos & images
- [x] Custom per-line transform hook (`customTransform`)
- [ ] Markdown to PDF

## About
Marv is a stupid simple markdown parser written in [Nim](https://nim-lang.org). It can be used as a library in your Nim projects or as a CLI tool to convert markdown files to HTML. It supports headings, paragraphs, bold, italic, strikethrough, links, images, lists (incl. task lists), blockquotes (incl. GitHub alerts), code blocks, inline code, tables (with optional footer), footnotes, reference links, raw HTML, autolinks, YAML front matter and more.

## Installing

Install Marvdown via [Nimble](https://nim-lang.org/docs/nimble.html)
```
nimble install marvdown
```

## Quick Start

### From the command line
```
marvdown html sample.md --optAnchors
marvdown html sample.md --optAnchors --output out.html
marvdown json sample.md
```
- `--optAnchors` — generate heading anchors (with a 🔗 link icon)
- `--bench` — print timing stats
- `--components` — enable `@include` / `@attr` / `$variable` components

### As a Nim library
```nim
import marvdown

# one-liner
echo marvdown.toHtml(readFile("sample.md"))

# with custom options
let opts = MarkdownOptions(
  allowed: @[tagP, tagStrong, tagEm, tagA, tagCode, tagPre],
  enableAnchors: true,
  anchorIcon: "🔗"
)
var md = newMarkdown(readFile("sample.md"), opts)
echo md.toHtml()
```

## Settings (`MarkdownOptions`)

All knobs live on the `MarkdownOptions` object passed to `newMarkdown`:

```nim
let opts = MarkdownOptions(
  # Which raw HTML tags are allowed. Empty `@[]` means NO raw HTML.
  allowed: @[tagA, tagDiv, tagSpan, tagImg, tagP, tagPre, tagCode],
  # …or allow tags by category instead:
  allowTagsByType: none(TagType),   # tagNone | tagInline | tagBlock | tagAll

  allowInlineStyle: false,   # allow `style` attributes/tags
  allowHtmlAttributes: false, # allow attributes like `width`, `title`

  enableAnchors: true,       # add id="…" + anchor link to headings
  anchorIcon: "🔗",          # icon used inside the anchor link

  showFootnotes: true,       # render footnotes at the end of the doc

  htmlTableClasses: none(seq[string]),  # e.g. some(@["table", "table-striped"])

  enableEmailAutolinks: false,  # `<user@example.com>` → mailto link

  enableComponents: false,   # enable @include / @attr / $variable
  componentBaseDir: "",      # base dir for @include paths

  customTransform: nil,      # proc(line: string): string per-line hook

  lazyloadIframes: false,    # <iframe src> → data-src
  lazyloadVideos: false,     # <video>/<audio>/<source> src → data-src
  lazyloadImages: false      # <img> & ![alt](url) src → data-src
)
```

## Features

### Headings & anchors
```markdown
# Hello World
## Sub section
```
```html
<h1 id="hello-world"><a href="#hello-world" class="anchor-link">🔗</a>Hello World</h1>
<h2 id="sub-section"><a href="#sub-section" class="anchor-link">🔗</a>Sub section</h2>
```
Build a table of contents from the generated anchors:
```nim
for item in md.getSelectorItems():   # seq[(level, anchor, title)]
  echo item.level, ". ", item.title, "  #", item.anchor
```

### Inline formatting
```markdown
**bold**, *italic*, __strong__, _italic_, ~~strikethrough~~ and `code`.
```
```html
<p><strong>bold</strong>, <em>italic</em>, <strong>strong</strong>, <em>italic</em>,
<del>strikethrough</del> and <code>code</code>.</p>
```

### Links & autolinks
```markdown
[inline link](https://example.com "title")

Bare https://example.com auto-links.
<user@example.com>    <!-- enable enableEmailAutolinks -->
```
```html
<p><a href="https://example.com" title="title">inline link</a></p>
<p>Bare <a href="https://example.com">https://example.com</a> auto-links.</p>
<p><a href="mailto:user@example.com">user@example.com</a></p>
```

### Images
```markdown
![Marvdown logo](https://example.com/logo.png "Logo")
```
```html
<img src="https://example.com/logo.png" alt="Marvdown logo" title="Logo" />
```

### Lists & task lists
```markdown
- unordered item
1. ordered one
- [x] completed task
- [ ] pending task
```
```html
<ul><li>unordered item</li></ul>
<ol><li>ordered one</li></ol>
<ul>
  <li><input type="checkbox" checked disabled>completed task</li>
  <li><input type="checkbox" disabled>pending task</li>
</ul>
```

### Blockquotes & alerts
```markdown
> A wise quote with `code`.

> [!WARNING]
> Watch out!
```
```html
<blockquote>A wise quote with <code>code</code>.</blockquote>
<div class="alert alert-warning rounded-4" role="alert">
  <div class="alert-content">Watch out!</div>
</div>
```
Supported markers: `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`.

### Code blocks
````markdown
```nim
proc hello =
  echo "hi"
```
````
```html
<pre><code class="language-nim">proc hello =
  echo &quot;hi&quot;</code></pre>
```
Indented code blocks (4 spaces) are supported too.

### Tables (with optional footer)
```markdown
| Name | Role |
| ---- | ---- |
| Ana  | CEO  |
| Bob  | CTO  |
|------|------|
| Total | 2    |
```
```html
<table>
  <thead><tr><th>Name</th><th>Role</th></tr></thead>
  <tbody><tr><td>Ana</td><td>CEO</td></tr><tr><td>Bob</td><td>CTO</td></tr></tbody>
  <tfoot><tr><td>Total</td><td>2</td></tr></tfoot>
</table>
```
Add CSS classes with `htmlTableClasses: some(@["table", "table-striped"])`.

### Footnotes
```markdown
This needs a citation[^1].

[^1]: The footnote body.
```
```html
<p>This needs a citation<sup class="footnote-ref"><a href="#fn-1">1</a></sup>.</p>
<hr><div class="footnotes"><div class="footnote" id="fn-1"><sup>1</sup> The footnote body.</div></div>
```

### Reference links
```markdown
See the [project][repo].

[repo]: https://github.com/openpeeps/marvdown
```
```html
<p>See the <a href="https://github.com/openpeeps/marvdown">project</a>.</p>
```
Supports explicit `[text][ref]`, collapsed `[text][]` and shortcut `[text]` references.

### Raw HTML
```markdown
<div class="hero"><p>custom block</p></div>
```
```html
<div class="hero"><p>custom block</p></div>
```
Raw HTML is gated by the `allowed` / `allowTagsByType` options.

### Components (`@include`, `@attr`, `$variable`)
Include other files (markdown or HTML) and use props & variables in the HTML:

`card.html`:
```html
<div @title="Marvdown" @badge="v0.1.4">
  <h2>$title</h2>
  <p>Release <code>$badge</code></p>
</div>
```
`page.md`:
```markdown
@include("card.html")
```
```html
<div>
  <h2>Marvdown</h2>
  <p>Release <code>v0.1.4</code></p>
</div>
```
- `@attr="value"` is captured into a global scope and **stripped** from the output
- `$variable` is resolved from the scope; unknown variables stay literal
- `\$` escapes to a literal `$`
- Enable with `enableComponents: true` and set `componentBaseDir` to the folder containing the includes

### customTransform
Hook every body line before it is parsed — great for custom syntax:
```nim
let opts = MarkdownOptions(
  customTransform: proc(line: string): string =
    if line == "@card": "<div class=\"card\">Custom card</div>"
    else: line
)
```

### Lazy-loading media
```nim
MarkdownOptions(lazyloadIframes: true)
MarkdownOptions(lazyloadVideos: true)
MarkdownOptions(lazyloadImages: true)
```
`<iframe src="…">`, `<video src>`, `<audio src>`, `<source src>` and `<img src>` (both raw HTML and `![alt](url)`) are rewritten from `src` to `data-src`, ready for an IntersectionObserver.

### YAML front matter
```markdown
---
title: Marvdown
author: OpenPeeps
---

# Body
```
```nim
let header = md.getHeader()          # YAMLObject (OrderedTable)
echo yamlmod.getStr(header["title"]) # "Marvdown"
```

### AST / JSON
```nim
echo marvdown.getAst(readFile("sample.md"))
```
```json
[{"kind":"mdkHeading","level":1,"textAnchor":null,
  "children":{"items":[{"kind":"mdkText","text":"Hello","children":null,"line":1}]},
  "line":1}]
```

## Examples

Check out the [`examples/`](examples/) folder for runnable code:

```bash
# run the comprehensive feature example
nim c -r examples/example.nim

# or use the CLI on a feature-rich sample document
nim c src/marvdown.nim
./marvdown html examples/sample.md --optAnchors
./marvdown json examples/sample.md
```

## Benchmarks
Marvdown is super fast! It can parse large markdown files in milliseconds. Here is a quick benchmark
over 100K lines of markdown text (~5.3 MB)

```
Benchmark 1: marvdown html bigdoc.md
  Time (abs ≡):        188.1 ms               [User: 166.9 ms, System: 19.8 ms]
```

_Benchmark made with [hyperfine](https://github.com/sharkdp/hyperfine)_

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/marvdown/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/marvdown/fork)

### Credits
Original illustration made by 💙 [Olha](https://www.deviantart.com/jo316) remixed with Sora.

### 🎩 License
**Marv** | [MIT License](https://github.com/openpeeps/marvdown/blob/main/LICENSE).
[Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
