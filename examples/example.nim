# Marvdown — comprehensive runnable example
#
# Run with:
#   nim c -r examples/example.nim
#
# Each section converts a snippet with `newMarkdown(...)` and prints the
# resulting HTML to stdout.

import std/options
import std/os
import std/tables
import marvdown
import pkg/openparser/yaml as yamlmod

let baseOpts = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagDiv, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagSpan, tagStrong,
    tagTable, tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl,
    tagIframe, tagVideo, tagAudio, tagSource, tagInput
  ],
  enableAnchors: true,
  anchorIcon: "🔗"
)

proc show(title: string, md: var Markdown) =
  ## Render a Markdown instance and print the generated HTML.
  echo "\n--- " & title & " ---"
  echo md.toHtml()

proc convert(title: string, sample: string, opts: MarkdownOptions) =
  var md = newMarkdown(sample, opts)
  show(title, md)

# ---------------------------------------------------------------------------
echo "Marvdown example — every feature at a glance"
echo "============================================"

# 1. Plain conversion
convert("Basic conversion", "Hello **world**, from *Marvdown*!", baseOpts)

# 2. Settings / options
convert("Options: anchors + custom table classes",
  "# A Heading\n\n| A | B |\n| - | - |\n| 1 | 2 |",
  MarkdownOptions(
    allowed: baseOpts.allowed,
    enableAnchors: true,
    htmlTableClasses: some(@["table", "table-striped"])
  )
)

# 3. Headings & anchors
convert("Headings with anchors", "# Level One\n## Level Two\n### Level Three",
  baseOpts)

# 4. Inline formatting
convert("Inline formatting",
  "**bold**, *italic*, __strong__, _italic_, ~~strikethrough~~, `code`, " &
  "and **bold *nested* bold**.",
  baseOpts)

# 5. Links & autolinks
convert("Links & autolinks",
  "[inline link](https://example.com \"title\") and bare https://example.com " &
  "auto-links.",
  baseOpts)
convert("Email autolink", "<user@example.com>",
  MarkdownOptions(allowed: baseOpts.allowed, enableEmailAutolinks: true))

# 6. Images
convert("Image", "![Marvdown logo](https://example.com/logo.png \"Logo\")",
  baseOpts)

# 7. Lists & task lists
convert("Lists & task lists",
  "- unordered item\n- with **formatting**\n\n1. ordered one\n2. ordered two\n\n" &
  "- [x] completed task\n- [ ] pending task",
  baseOpts)

# 8. Blockquotes & alerts
convert("Blockquote", "> A wise quote with `code`.", baseOpts)
convert("GitHub-style alerts",
  "> [!NOTE]\n> Useful info.\n\n> [!WARNING]\n> Watch out!",
  baseOpts)

# 9. Code blocks
convert("Code blocks",
  "```nim\nproc hello =\n  echo \"hi\"\n```\n\nIndented code:\n\n    let x = 1",
  baseOpts)

# 10. Tables
convert("Table with footer",
  "| Name | Role |\n| ---- | ---- |\n| Ana  | CEO  |\n| Bob  | CTO  |\n" &
  "|------|------|\n| Total | 2    |",
  baseOpts)

# 11. Footnotes
convert("Footnotes", "This needs a citation[^1].\n\n[^1]: The footnote body.",
  baseOpts)

# 12. Reference links
convert("Reference links",
  "See the [project][repo].\n\n[repo]: https://github.com/openpeeps/marvdown",
  baseOpts)

# 13. Raw HTML
convert("Raw HTML passthrough", "<div class=\"hero\"><p>custom block</p></div>",
  baseOpts)

# 14. Components (@include / @attr / $variable)
block:
  let assetsDir = currentSourcePath().parentDir() / "assets"
  convert("Components (@include/@attr/$variable)",
    "Intro paragraph.\n\n@include(\"card.html\")",
    MarkdownOptions(
      allowed: baseOpts.allowed,
      enableComponents: true,
      componentBaseDir: assetsDir
    ))

# 15. customTransform hook
convert("customTransform hook",
  "Before\n\n@card\n\nAfter",
  MarkdownOptions(
    allowed: baseOpts.allowed,
    customTransform: proc(line: string): string =
      if line == "@card": "<div class=\"card\">Custom card</div>"
      else: line
  ))

# 16. Lazy-loading media
convert("Lazy-load iframes",
  "<iframe src=\"https://example.com/embed\" width=\"560\" height=\"315\"></iframe>",
  MarkdownOptions(allowed: baseOpts.allowed, lazyloadIframes: true))
convert("Lazy-load videos",
  "<video src=\"https://example.com/video.mp4\"></video>",
  MarkdownOptions(allowed: baseOpts.allowed, lazyloadVideos: true))
convert("Lazy-load images",
  "![alt](https://example.com/image.png)",
  MarkdownOptions(allowed: baseOpts.allowed, lazyloadImages: true))

# 17. YAML front matter
block:
  var md = newMarkdown(
    "---\ntitle: Marvdown\nauthor: OpenPeeps\n---\n\n# Body",
    baseOpts)
  show("YAML front matter", md)
  let header = md.getHeader()
  if not header.isNil:
    echo "header title: ", yamlmod.getStr(header["title"])

# 18. AST / JSON
echo "\n--- AST (getAst / toJson) ---"
echo marvdown.getAst("# Hello\n\nSome **text**.")

# 19. ToC data (heading selectors)
block:
  var md = newMarkdown(
    "# Intro\n\n## Chapter One\n\n### Section A\n\n## Chapter Two",
    baseOpts)
  discard md.toHtml()
  echo "\n--- Table of contents (getSelectorItems) ---"
  for item in md.getSelectorItems():
    echo item.level, ". ", item.title, "  (#", item.anchor, ")"

# 20. decodeHtmlEntities
echo "\n--- decodeHtmlEntities ---"
echo "AT&amp;T &rarr; ", decodeHtmlEntities("AT&amp;T")
