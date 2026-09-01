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
- [x] CommonMark compliant
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
  lazyloadImages: false,     # <img> & ![alt](url) src → data-src

  parseYaml: true            # parse YAML front matter (--- blocks); set false to skip for speed
)
```

## Features

### Headings & anchors
Build a table of contents from the generated anchors:
```nim
for item in md.getSelectorItems():   # seq[(level, anchor, title)]
  echo item.level, ". ", item.title, "  #", item.anchor
```

### Inline formatting
Supports **bold**, *italic*, `code`, ~~strikethrough~~ and combinations.

### Links & autolinks
Inline links with optional titles, bare `https://` auto-links and `mailto:` email autolinks via `enableEmailAutolinks`.

### Images
Images with alt text and optional titles.

### Lists & task lists
Unordered (`-`, `*`, `+`), ordered (`1.`) and task lists (`- [x]`, `- [ ]`) with nesting.

### Blockquotes & alerts
Blockquotes and GitHub-style alerts. Supported markers: `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`.

### Code blocks
Fenced code blocks with language info and indented code blocks (4 spaces).

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
Footnote references and definitions rendered at the end of the document.

### Reference links
Supports explicit `[text][ref]`, collapsed `[text][]` and shortcut `[text]` references.

### Raw HTML
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
Marvdown is super fast! Run `clue test -d:release` (options `allowTagsByType: tagAll`, `parseYaml: false`):

```
Marvdown Benchmark – toHtml (wall time, release)
==================================================

| Document                 | Size       |   Iters |   Total ms |     Avg ms |       Throughput |        Out |     CPU ms |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
| sample.md (CommonMark)   | 27.1 KB    |     500 |     263.99 |      0.528 |       50.19 MB/s |    27.9 KB |     263.89 |
| tests/data/big.md        | 4.84 MB    |       5 |     842.18 |    168.437 |       28.73 MB/s |    6.15 MB |     841.88 |
| synthetic 100 lines      | 4.2 KB     |     200 |      37.02 |      0.185 |       22.37 MB/s |     6.8 KB |      37.02 |
| synthetic 1k lines       | 43.8 KB    |      50 |      92.59 |      1.852 |       23.07 MB/s |    68.9 KB |      92.54 |
| synthetic 10k lines      | 451.2 KB   |       5 |     115.05 |     23.010 |       19.15 MB/s |   703.1 KB |     115.04 |
| tiny 1 line              | 14 B       |    1000 |       2.10 |      0.002 |        6.36 MB/s |       26 B |       2.10 |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
  Iterations: 1760  |  Total wall: 1352.93 ms
```

```
Marvdown Benchmark – toHtml + anchors
=======================================

| Document                 | Size       |   Iters |   Total ms |     Avg ms |       Throughput |        Out |     CPU ms |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
| sample.md (CommonMark) + | 27.1 KB    |     250 |     127.20 |      0.509 |       52.08 MB/s |    28.0 KB |     127.19 |
| synthetic 1k lines +anch | 43.8 KB    |      25 |      49.20 |      1.968 |       21.71 MB/s |    75.6 KB |      49.20 |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
  Iterations: 275  |  Total wall: 176.40 ms
```

```
Marvdown Benchmark – toHtml vs toJson (sample.md)
===================================================

| Document                 | Size       |   Iters |   Total ms |     Avg ms |       Throughput |        Out |     CPU ms |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
| sample toHtml            | 27.1 KB    |     100 |      53.82 |      0.538 |       49.24 MB/s |    27.9 KB |      53.80 |
| sample toJson            | 27.1 KB    |     100 |      71.98 |      0.720 |       36.81 MB/s |    42.6 KB |      71.97 |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
  Iterations: 200  |  Total wall: 125.79 ms
```

```
Scaling check – 100 vs 1k lines
=================================

| Document                 | Size       |   Iters |   Total ms |     Avg ms |       Throughput |        Out |     CPU ms |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
| 100 lines                | 4.2 KB     |     100 |      18.34 |      0.183 |       22.58 MB/s |     6.8 KB |      18.34 |
| 1k lines                 | 43.8 KB    |      20 |      37.15 |      1.857 |       23.00 MB/s |    68.9 KB |      37.15 |
|--------------------------|------------|---------|------------|------------|------------------|------------|------------|
  Iterations: 120  |  Total wall: 55.49 ms
```

_Benchmark via `tests/test_benchmark.nim` plain-text table; `Nim 2.2.0`, `macOS amd64` (clue). Re-run with `clue test -d:release`._

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/marvdown/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/marvdown/fork)

### Credits
Original illustration made by 💙 [Olha](https://www.deviantart.com/jo316) remixed with Sora.

### 🎩 License
**Marv** | [MIT License](https://github.com/openpeeps/marvdown/blob/main/LICENSE).
[Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2024 OpenPeeps & Contributors &mdash; All rights reserved.
