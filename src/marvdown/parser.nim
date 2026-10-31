# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[strutils, sequtils, options, tables, unicode, unidecode, os]
import pkg/openparser/[json, yaml, html]

export HtmlTag
export json # re-exported (via openparser) so `JsonNode`, `$`, `parseJson`, … work for lib users

import ./lexer, ./ast, ./components

type
  MarkdownParser* = object
    ## Internal: The parser state
    lexer: MarkdownLexer
    prev, curr, next: MarkdownTokenTuple

  Markdown* {.acyclic.} = ref object
    parser: MarkdownParser
      ## Internal: The markdown parser instance
    minify*: bool
      ## Minify the output HTML (default: true)
    opts*: MarkdownOptions
      ## Options for allowed HTML tags and attributes
    selectors: OrderedTableRef[string, string]
      ## Internal: Used for generating unique headline anchors
    selectorLevels: OrderedTableRef[string, int]
      ## Internal: Heading level (1-6) for each generated anchor
    selectorCounter: CountTableRef[string]
      ## Internal: Counter for generating unique selectors
    ast*: seq[MarkdownNode]
      ## The abstract syntax tree (AST) of the parsed markdown document
    headerYaml: YAMLObject
      ## Parsed YAML front matter as JsonNode
    footnotes: OrderedTableRef[string, MarkdownNode]
      ## Footnote definitions parsed from the document
    footnotesHtml*: string
      ## Generated HTML for footnotes at the end of the document
    linkDefs*: TableRef[string, tuple[url, title: string]]
      ## Link definitions collected from the document (pre-scan)
    scope*: ComponentScope
      ## Component scope: variables set by @attr in imported HTML

  TagType* = enum
    tagNone,       # No tags allowed
    tagInline,     # Inline tags (e.g., <b>, <i>, <a>)
    tagBlock,      # Block-level tags (e.g., <div>, <p>, <h1>)
    tagAll         # All tags allowed

  MarkdownOptions* = object
    allowed*: seq[HtmlTag]
      ## Allowed HTML tag names. See `defaultMarkdownOptions`
      ## Marv is using `HtmlTag` from `std/htmlparser`
      ## **Attention!** An empty `@[]` means no tags are allowed.
      ## Use `allowTagsByType` to allow tags by category.
    allowTagsByType*: Option[TagType]
      ## Allow HTML tags by their types. Default is `none(TagType)`.
      # TODO allow a set of TagType values? and merge with `allowed`?
    allowInlineStyle*: bool
      ## Allow CSS styling using `style` tag (disabled by default)
    allowHtmlAttributes*: bool
      ## Allow using html attributes, `width`, `title` and so on.
      ## For allowing use of `style` attribute, enable `allowInlineStyle`.
    enableAnchors*: bool
      ## Enable anchor generation in title blocks (enabled by default)
    anchorIcon*: string = "🔗"
      ## Icon used for anchor links in headings
    showFootnotes*: bool = true
      ## Insert footnotes HTML at the end of the document (default: true)
    htmlTableClasses*: Option[seq[string]]
      ## Optional CSS classes to add to generated HTML tables (e.g., `["table", "table-striped"]` for Bootstrap tables)
    enableEmailAutolinks*: bool
      ## Enable email autolinks in angle brackets (e.g., `<user@example.com>`)
    enableComponents*: bool
      ## Enable @include() directives and @attr/$variable in imported HTML
    componentBaseDir*: string
      ## Base directory for resolving @include() paths. If empty,
      ## resolves relative to the current working directory.
    customTransform*: proc(line: string): string
      ## Optional per-line parsing hook. Called for every body line (outside
      ## fenced code blocks and the leading YAML front matter) before lexing.
      ## Return a different string (possibly raw HTML) to replace the line;
      ## return the input unchanged to keep it. Useful for custom syntax like
      ## `@hello-world.md` that should render as rich HTML (e.g. a card) built
      ## by the consumer. Default: nil (disabled).
    codeBlockTransform*: proc(lang, code: string): string
      ## Optional fenced code block hook. Called at render time with the raw
      ## fence info string (`lang`, may be "") and the raw code. Return full
      ## inner HTML for `<pre><code>`; return "" to keep the default escaped
      ## output. Useful for backend syntax highlighting (e.g. SweetSyntax).
      ## Default: nil (disabled).
    lazyloadIframes*: bool
      ## Lazy-load iframes by rewriting the `src` attribute of `<iframe>`
      ## tags to `data-src` so they are only fetched when a client-side
      ## script swaps them back (e.g., via IntersectionObserver).
      ## Default: false
    lazyloadVideos*: bool
      ## Lazy-load videos and audio by rewriting the `src` attribute of
      ## `<video>`, `<audio>` and `<source>` tags to `data-src`.
      ## Default: false
    lazyloadImages*: bool
      ## Lazy-load images by rewriting the `src` attribute of `<img>` tags
      ## to `data-src`. Applies to both raw HTML and Markdown image syntax.
      ## Default: false
    parseYaml*: bool = true
      ## Parse YAML front matter (`---` blocks) into `headerYaml`. Disable
      ## for speed when YAML is not needed (e.g., pure benchmarking).
      ## Default: true

#
# forward declarations
#
proc renderNode(md: var Markdown, node: MarkdownNode): string

proc parseInline(md: var Markdown, items: var seq[MarkdownNode])
proc parseInline(md: var Markdown, text: sink string): seq[MarkdownNode]

proc parseEmphasis(md: var Markdown): MarkdownNode
proc parseStrong(md: var Markdown): MarkdownNode
proc parseStrikethrough(md: var Markdown): MarkdownNode
proc parseMarkdown(md: var Markdown, currentParagraph: var MarkdownNode)

proc renderHtmlWithInnerMarkdown(md: var Markdown, rawHtml: string,
    tagName: string, line: int): string

proc nodeFromJson*(node: JsonNode): MarkdownNode

proc advance*(md: var Markdown, offset = 1) =
  var i = 0
  while i < offset and md.parser.curr.kind != mtkEOF:
    md.parser.prev = md.parser.curr
    md.parser.curr = md.parser.next
    md.parser.next = md.parser.lexer.nextToken()
    inc i

proc slugify(input: string, lowercase = true, sep = "-"): string =
  # Convert input string to a slug
  let s = unidecode(input)
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of Whitespace:
      if result.len > 0 and result[^1] != '-':
        result.add(sep)
    of Letters:
      result.add if lowercase:
        c.toLowerAscii else: c
    of Digits:
      result.add c
    of '-':
      if result.len > 0 and result[^1] != '-':
        result.add('-')
    else: discard

proc parseImage(md: var Markdown): MarkdownNode =
  ## Parse an image token into a MarkdownNode
  let attrs = md.parser.curr.attrs.get()
  if attrs.len >= 2:
    let title = if attrs.len > 2: attrs[2] else: ""
    result = newImage(attrs[0], attrs[1], title, md.parser.curr.line)

proc parseLink(md: var Markdown): MarkdownNode =
  # Parse a link token into a MarkdownNode
  let attrs = md.parser.curr.attrs.get()
  if attrs.len >= 2:
    let text = attrs[0]
    let href = attrs[1]
    let title = if attrs.len > 2: attrs[2] else: ""
    result = newLink(href, title, md.parser.curr.line)
    if text == href:
      # Autolink (or `[url](url)`): keep display text plain to avoid
      # a nested link node from re-detecting the URL as an autolink.
      result.children.items.add(newText(text, md.parser.curr.line))
    else:
      # Link text may contain inline markup (strong, emphasis, code, etc.)
      for n in md.parseInline(text):
        result.children.items.add(n)

proc parseText(md: var Markdown): MarkdownNode =
  # Parse a text token into a MarkdownNode
  newText(md.parser.curr.token, md.parser.curr.line)

proc appendInlineFromStream(md: var Markdown, items: var seq[MarkdownNode]): bool =
  ## Parse a single inline node from the parser token stream and append it
  ## to `items`. Returns `false` when the current token is not an inline
  ## kind (the token is left unconsumed so the caller can break out of its
  ## loop). Handles every inline kind, mirroring the token-stream `parseInline`.
  let curr = md.parser.curr
  case curr.kind
  of mtkText:
    items.add(md.parseText())
    md.advance()
    return true
  of mtkEmphasis:
    items.add(md.parseEmphasis())
    return true
  of mtkStrong:
    items.add(md.parseStrong())
    return true
  of mtkStrikethrough:
    items.add(md.parseStrikethrough())
    return true
  of mtkLink:
    items.add(md.parseLink())
    md.advance()
    return true
  of mtkImage:
    items.add(md.parseImage())
    md.advance()
    return true
  of mtkInlineCode:
    items.add(MarkdownNode(
      kind: mdkInlineCode,
      inlineCode: curr.token,
      line: curr.line
    ))
    md.advance()
    return true
  of mtkLineBreak:
    items.add(newRawHtml("<br>", curr.line))
    md.advance()
    return true
  of mtkRefLink:
    let attrs = curr.attrs.get()
    let displayText = attrs[0]
    let isExplicit = attrs.len > 1 and attrs[1].len > 0 and attrs[1] != displayText
    let refLabel = if isExplicit: attrs[1].toLowerAscii
                   else: displayText.toLowerAscii
    if md.linkDefs.hasKey(refLabel):
      let def = md.linkDefs[refLabel]
      let linkNode = newLink(def.url, def.title, curr.line)
      for n in md.parseInline(displayText):
        linkNode.children.items.add(n)
      items.add(linkNode)
    else:
      if isExplicit:
        items.add(newText("[" & displayText & "][" & attrs[1] & "]", curr.line))
      else:
        items.add(newText("[" & displayText & "]", curr.line))
    md.advance()
    return true
  else:
    return false

proc parseStrong(md: var Markdown): MarkdownNode =
  # Parse strong text and add to current paragraph
  let tk = md.parser.curr
  md.advance() # Skip opening strong
  var strongChildren = newSeq[MarkdownNode]()
  while md.parser.curr.kind notin {mtkStrong, mtkEOF}:
    if not appendInlineFromStream(md, strongChildren):
      break
  if md.parser.curr.kind == mtkStrong and md.parser.curr.line == tk.line:
    result = MarkdownNode(
      kind: mdkStrong,
      children: MarkdownNodeList(items: strongChildren),
      line: md.parser.curr.line
    )
    md.advance() # Skip closing strong
  else:
    # Unclosed strong, treat as text
    strongChildren.insert(MarkdownNode(kind: mdkText, text: "**"), 0)
    result = MarkdownNode(
      kind: mdkText,
      children: MarkdownNodeList(items: strongChildren),
      line: md.parser.curr.line
    )

proc parseCheckboxItem(md: var Markdown): MarkdownNode =
  # Parse a checkbox list item ([ ] or [x])
  let attrs = md.parser.curr.attrs.get()
  let checked = attrs.len > 1 and attrs[1] == "checked"
  result = MarkdownNode(
    kind: mdkListItem,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line
  )
  # Add checkbox input as first child
  result.children.items.add(MarkdownNode(
    kind: mdkHtml,
    html: "<input type=\"checkbox\"" & (if checked: " checked" else: "") & " disabled>",
    line: md.parser.curr.line
  ))
  
  let itemText = md.parser.curr.token.strip()
  if itemText.len > 0:
    for n in md.parseInline(itemText):
      result.children.items.add(n)
  md.advance() # consume the checkbox item token

proc parseEmphasis(md: var Markdown): MarkdownNode =
  # Parse emphasis text and add to current paragraph
  let tk = md.parser.curr
  md.advance() # Skip opening emphasis
  var emphChildren = newSeq[MarkdownNode]()
  while md.parser.curr.kind notin {mtkEmphasis, mtkEOF} and md.parser.curr.line == tk.line:
    if not appendInlineFromStream(md, emphChildren):
      break
  if md.parser.curr.kind == mtkEmphasis and md.parser.curr.line == tk.line:
    result = MarkdownNode(
      kind: mdkEmphasis,
      children: MarkdownNodeList(items: emphChildren),
      line: tk.line
    )
    md.advance() # Skip closing emphasis
  else:
    # Unclosed emphasis, treat as text
    result = MarkdownNode(kind: mdkText, line: tk.line)
    result.text = "*"
    for child in emphChildren:
      if child.kind == mdkText:
        result.text.add(child.text)

proc parseStrikethrough(md: var Markdown): MarkdownNode =
  let tk = md.parser.curr
  md.advance()
  var children = newSeq[MarkdownNode]()
  while md.parser.curr.kind notin {mtkStrikethrough, mtkEOF}:
    if not appendInlineFromStream(md, children):
      break
  if md.parser.curr.kind == mtkStrikethrough and md.parser.curr.line == tk.line:
    result = MarkdownNode(
      kind: mdkStrikethrough,
      children: MarkdownNodeList(items: children),
      line: tk.line
    )
    md.advance()
  else:
    children.insert(MarkdownNode(kind: mdkText, text: "~~"), 0)
    result = MarkdownNode(
      kind: mdkText,
      children: MarkdownNodeList(items: children),
      line: tk.line
    )

const stopKinds = {
  mtkEOF, mtkParagraph, mtkHeading, mtkTable,
  mtkListItem, mtkListItemCheckbox, mtkOListItem,
  mtkCodeBlock, mtkBlockquote, mtkHorizontalRule,
  mtkDocument, mtkFootnoteDef, mtkLinkDef
}

const inlineKinds = {
  mtkStrong, mtkEmphasis, mtkStrikethrough, mtkLink, mtkImage,
  mtkInlineCode, mtkFootnoteRef, mtkLineBreak, mtkRefLink
}

proc parseInline(md: var Markdown, items: var seq[MarkdownNode]) =
  # Parse inline nodes from the current parser stream.
  # Consumes tokens until a block boundary / paragraph boundary

  while md.parser.curr.kind notin stopKinds:
    let curr = md.parser.curr
    var node: MarkdownNode
    case curr.kind
    of mtkText:
      node = md.parseText()
      md.advance()
      # Preserve word boundary: append a space when text is directly
      # followed by an inline element (lexer strips the whitespace).
      if md.parser.curr.kind in inlineKinds:
        node.text.add(' ')
    of mtkEmphasis:
      node = md.parseEmphasis()
    of mtkStrong:
      node = md.parseStrong()
    of mtkStrikethrough:
      node = md.parseStrikethrough()
    of mtkLink:
      node = md.parseLink()
      md.advance()
    of mtkImage:
      node = md.parseImage()
      md.advance()
    of mtkInlineCode:
      node = MarkdownNode(
        kind: mdkInlineCode,
        inlineCode: curr.token,
        line: curr.line
      )
      md.advance()
    of mtkFootnoteRef:
      let id = curr.attrs.get()[0]
      node = MarkdownNode(
        kind: mdkFootnoteRef,
        footnoteRefId: id,
        line: curr.line
      )
      md.advance()
    of mtkLineBreak:
      node = newRawHtml("<br>", curr.line)
      md.advance()
    of mtkRefLink:
      let attrs = curr.attrs.get()
      let displayText = attrs[0]
      let isExplicit = attrs.len > 1 and attrs[1].len > 0 and attrs[1] != displayText
      let refLabel = if isExplicit: attrs[1].toLowerAscii
                     else: displayText.toLowerAscii
      if md.linkDefs.hasKey(refLabel):
        let def = md.linkDefs[refLabel]
        node = newLink(def.url, def.title, curr.line)
        for n in md.parseInline(displayText):
          node.children.items.add(n)
      else:
        if isExplicit:
          node = newText("[" & displayText & "][" & attrs[1] & "]", curr.line)
        else:
          node = newText("[" & displayText & "]", curr.line)
      md.advance()
    else: break
    if node != nil: items.add(node)

proc parseInlineNode(md: var Markdown, lex: var MarkdownLexer, curr: var MarkdownTokenTuple): MarkdownNode =
  ## Parse a single inline token (and any nested inline content) into a
  ## MarkdownNode, consuming tokens from `lex` as needed. Used by the
  ## string-based inline parser for list items, headings, table cells, etc.
  case curr.kind
  of mtkText:
    result = MarkdownNode(kind: mdkText, text: curr.token, line: curr.line)
    curr = lex.nextToken()
  of mtkEmphasis:
    let emphLine = curr.line
    curr = lex.nextToken()
    var emphChildren: seq[MarkdownNode] = @[]
    while curr.kind != mtkEmphasis and curr.kind != mtkEOF:
      let child = parseInlineNode(md, lex, curr)
      if not child.isNil:
        emphChildren.add(child)
    if curr.kind == mtkEmphasis:
      result = MarkdownNode(
        kind: mdkEmphasis,
        children: MarkdownNodeList(items: emphChildren),
        line: emphLine
      )
      curr = lex.nextToken()
    else:
      # Unclosed emphasis, treat as text (mirrors parseEmphasis)
      result = MarkdownNode(kind: mdkText, line: emphLine)
      result.text = "*"
      for child in emphChildren:
        if child.kind == mdkText:
          result.text.add(child.text)
  of mtkStrong:
    let strongLine = curr.line
    curr = lex.nextToken()
    var strongChildren: seq[MarkdownNode] = @[]
    while curr.kind != mtkStrong and curr.kind != mtkEOF:
      let child = parseInlineNode(md, lex, curr)
      if not child.isNil:
        strongChildren.add(child)
    if curr.kind == mtkStrong:
      result = MarkdownNode(
        kind: mdkStrong,
        children: MarkdownNodeList(items: strongChildren),
        line: strongLine
      )
      curr = lex.nextToken()
    else:
      # Unclosed strong, treat as text (mirrors parseStrong)
      strongChildren.insert(MarkdownNode(kind: mdkText, text: "**"), 0)
      result = MarkdownNode(
        kind: mdkText,
        children: MarkdownNodeList(items: strongChildren),
        line: strongLine
      )
  of mtkStrikethrough:
    let stLine = curr.line
    curr = lex.nextToken()
    var stChildren: seq[MarkdownNode] = @[]
    while curr.kind != mtkStrikethrough and curr.kind != mtkEOF:
      let child = parseInlineNode(md, lex, curr)
      if not child.isNil:
        stChildren.add(child)
    if curr.kind == mtkStrikethrough:
      result = MarkdownNode(
        kind: mdkStrikethrough,
        children: MarkdownNodeList(items: stChildren),
        line: stLine
      )
      curr = lex.nextToken()
    else:
      # Unclosed strikethrough, treat as text (mirrors parseStrikethrough)
      stChildren.insert(MarkdownNode(kind: mdkText, text: "~~"), 0)
      result = MarkdownNode(
        kind: mdkText,
        children: MarkdownNodeList(items: stChildren),
        line: stLine
      )
  of mtkLink:
    if curr.attrs.isSome and curr.attrs.get().len >= 2:
      let textVal = curr.attrs.get()[0]
      let hrefVal = curr.attrs.get()[1]
      let titleVal =
        if curr.attrs.get().len > 2: curr.attrs.get()[2]
        else: "" # no title provided
      let linkNode = newLink(hrefVal, titleVal, curr.line)
      if textVal == hrefVal:
        # Autolink (or `[url](url)`): the display text is the URL itself.
        # Re-parsing it would recursively detect the same autolink, so use
        # the plain text directly.
        linkNode.children.items.add(newText(textVal, curr.line))
      else:
        for n in md.parseInline(textVal):
          linkNode.children.items.add(n)
      result = linkNode
    curr = lex.nextToken()
  of mtkImage:
    if curr.attrs.isSome and curr.attrs.get().len >= 2:
      let alt = curr.attrs.get()[0]
      let src = curr.attrs.get()[1]
      let title =
        if curr.attrs.get().len > 2: curr.attrs.get()[2]
        else: ""
      result = newImage(alt, src, title, curr.line)
    curr = lex.nextToken()
  of mtkInlineCode:
    result = MarkdownNode(
      kind: mdkInlineCode,
      inlineCode: curr.token,
      line: curr.line
    )
    curr = lex.nextToken()
  of mtkLineBreak:
    result = newRawHtml("<br>", curr.line)
    curr = lex.nextToken()
  of mtkRefLink:
    if curr.attrs.isSome and curr.attrs.get().len >= 2:
      let displayText = curr.attrs.get()[0]
      let isExplicit = curr.attrs.get().len > 1 and
                       curr.attrs.get()[1].len > 0 and
                       curr.attrs.get()[1] != displayText
      let refLabel =
        if isExplicit: curr.attrs.get()[1].toLowerAscii
        else: displayText.toLowerAscii
      if md.linkDefs.hasKey(refLabel):
        let def = md.linkDefs[refLabel]
        let linkNode = newLink(def.url, def.title, curr.line)
        for n in md.parseInline(displayText):
          linkNode.children.items.add(n)
        result = linkNode
      else:
        if isExplicit:
          result = newText("[" & displayText & "][" & curr.attrs.get()[1] & "]", curr.line)
        else:
          result = newText("[" & displayText & "]", curr.line)
    curr = lex.nextToken()
  else:
    result = MarkdownNode(kind: mdkText, text: curr.token, line: curr.line)
    curr = lex.nextToken()

proc parseInline(md: var Markdown, text: sink string): seq[MarkdownNode] =
  if text.len == 0: return
  var hasSpecial = false
  for c in text:
    if c in {'*','_','[',']','!','`','<','\\','~','|'}:
      hasSpecial = true; break
  # don't fast-path block-level markers at start of inline fragment
  # (e.g. "> bar" inside blockquote, "## header" inside blockquote)
  if text.len > 0 and text[0] in {'>', '#', '-', '=', '|', '+', '0'..'9'}:
    # fallback to lexer to handle block markers correctly – skip plain fast path
    discard
  elif not hasSpecial:
    # fast path: plain text without inline markup -> avoid lexer alloc
    # autolinks like http:// are detected inside scanTextWithLinks,
    # so only bypass lexer when no http prefix present
    if find(text, "http") < 0:
      return @[newText(text, 1)]
  # fast path for **strong** (+ `code`) fragments common in big.md list items
  # e.g. "**Event loop** — description" or "thread-safe `postToLoop`"
  # avoid full lexer for 25k items
  if hasSpecial and text.len >= 4 and not (text.len>0 and text[0] in {'>', '#'}):
    let hasStrong = find(text, "**") >= 0
    let hasCode = find(text, "`") >= 0
    if hasStrong or hasCode:
      var hasOtherSpecial = false
      for c in text:
        if c in {'[',']','!','<','\\','~','|'}:
          hasOtherSpecial = true; break
        if c == '_' :
          hasOtherSpecial = true; break
      if not hasOtherSpecial and find(text, "http") < 0:
        # only * and ` are special – try to build nodes without lexer
        var backtickCount = 0
        for c in text:
          if c == '`': inc backtickCount
        if backtickCount mod 2 != 0:
          hasOtherSpecial = true
        if not hasOtherSpecial:
          var starCount = 0
          for c in text:
            if c == '*': inc starCount
          # detect single-star emphasis (e.g. *italic*) – fallback to lexer
          var hasSingleStar = false
          for i, c in text:
            if c == '*':
              let left = i > 0 and text[i-1] == '*'
              let right = i+1 < text.len and text[i+1] == '*'
              if not (left or right):
                hasSingleStar = true; break
          if hasSingleStar:
            hasOtherSpecial = true
          let onlyCode = not hasStrong
          let onlyStrong = not hasCode
          var canFast = false
          if not hasOtherSpecial:
            if onlyCode and backtickCount >= 2:
              canFast = find(text, "``") < 0  # single backticks only
            elif onlyStrong and starCount >= 2 and starCount mod 2 == 0:
              canFast = find(text, "***") < 0 and find(text, "* *") < 0 and not hasSingleStar
            elif starCount mod 2 == 0 and backtickCount mod 2 == 0 and starCount >= 2 and backtickCount >= 2:
              canFast = find(text, "***") < 0 and not hasSingleStar
            elif hasStrong and starCount >= 2 and starCount mod 2 == 0 and backtickCount == 0:
              canFast = find(text, "***") < 0 and not hasSingleStar
          if canFast:
            var outp: seq[MarkdownNode] = @[]
            var pos = 0
            var ok = true
            while pos < text.len:
              let nextStrong = find(text, "**", pos)
              let nextCode = find(text, "`", pos)
              var s = -1
              var isCode = false
              if nextStrong >= 0 and nextCode >= 0:
                if nextStrong < nextCode:
                  s = nextStrong
                else:
                  s = nextCode; isCode = true
              elif nextStrong >= 0:
                s = nextStrong
              elif nextCode >= 0:
                s = nextCode; isCode = true
              else:
                if pos < text.len:
                  let tail = text[pos..^1]
                  if tail.len > 0:
                    outp.add(newText(tail, 1))
                break
              if s > pos:
                let before = text[pos..<s]
                if before.len > 0:
                  outp.add(newText(before, 1))
              if isCode:
                let e = find(text, "`", s+1)
                if e < 0: ok = false; break
                let inner = text[s+1..<e]
                if find(inner, "`") >= 0: ok = false; break
                let codeNode = MarkdownNode(kind: mdkInlineCode, inlineCode: inner, line: 1)
                outp.add(codeNode)
                pos = e + 1
              else:
                let e = find(text, "**", s+2)
                if e < 0: ok = false; break
                let inner = text[s+2..<e]
                if inner.len == 0 or find(inner, "*") >= 0 or find(inner, "`") >= 0: ok = false; break
                let innerNode = newText(inner, 1)
                let strongNode = MarkdownNode(kind: mdkStrong, children: MarkdownNodeList(items: @[innerNode]), line: 1)
                outp.add(strongNode)
                pos = e + 2
            if ok and outp.len > 0:
              return outp
  var lex = initLexer(text)
  var curr = lex.nextToken()
  let ln = curr.line
  while curr.kind != mtkEOF and curr.line == ln:
    let node = parseInlineNode(md, lex, curr)
    if not node.isNil:
      result.add(node)

proc skipWhitespaceTokens(md: var Markdown) =
  ## Skip leading whitespace tokens (spaces between list items)
  while md.parser.curr.kind == mtkText and md.parser.curr.token == " ":
    md.advance()

proc parseListItem(md: var Markdown, parentIndent: int = 0): MarkdownNode =
  # Parse a single list item, handling nested lists recursively
  if md.parser.curr.kind == mtkListItemCheckbox:
    return md.parseCheckboxItem()
  let itemText = md.parser.curr.token.strip()
  let indentLevel = md.parser.curr.indent
  let isOrdered = md.parser.curr.kind == mtkOListItem
  result = MarkdownNode(
    kind: mdkListItem,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line
  )
  if itemText.len > 0:
    for n in md.parseInline(itemText):
      result.children.items.add(n)
  md.advance()
  skipWhitespaceTokens(md)
  # Check for nested lists
  while md.parser.curr.kind in {mtkListItem, mtkListItemCheckbox, mtkOListItem}:
    let nextIndent = md.parser.curr.indent
    let nextOrdered = md.parser.curr.kind == mtkOListItem
    if nextIndent > indentLevel:
      # Nested list: parse all at this deeper indent
      var nestedList = MarkdownNode(
        kind: mdkList,
        listOrdered: nextOrdered,
        listStart: 1,
        children: MarkdownNodeList(items: @[]),
        line: md.parser.curr.line
      )
      while md.parser.curr.kind in {mtkListItem,
            mtkListItemCheckbox, mtkOListItem} and md.parser.curr.indent >= nextIndent:
        skipWhitespaceTokens(md)
        if md.parser.curr.kind notin {mtkListItem, mtkListItemCheckbox, mtkOListItem}: break
        let nestedItem = md.parseListItem(nextIndent)
        nestedList.children.items.add(nestedItem)
      result.children.items.add(nestedList)
    else: break

proc parseList(md: var Markdown): MarkdownNode =
  # Parse a sequence of list items into a single list node
  skipWhitespaceTokens(md)
  let startIndent = md.parser.curr.indent
  let isOrdered = md.parser.curr.kind == mtkOListItem
  let listStart =
    if isOrdered and md.parser.curr.attrs.isSome:
      try: md.parser.curr.attrs.get()[0].parseInt
      except: 1
    else: 1
  result = MarkdownNode(
    kind: mdkList,
    listOrdered: isOrdered,
    listStart: listStart,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line
  )
  while md.parser.curr.kind in {mtkListItem, mtkListItemCheckbox, mtkOListItem} and
        md.parser.curr.indent == startIndent:
    if (md.parser.curr.kind == mtkOListItem) != isOrdered: break
    skipWhitespaceTokens(md)
    if md.parser.curr.kind notin {mtkListItem, mtkListItemCheckbox, mtkOListItem}: break
    let itemNode = md.parseListItem(startIndent)
    result.children.items.add(itemNode)
    skipWhitespaceTokens(md)

proc parseBlockquote(md: var Markdown): MarkdownNode =
  # Parse one or more consecutive blockquote tokens into a blockquote node.
  # A GitHub-style alert (`> [!NOTE]` / `> [!WARNING]` …) becomes an mdkAlert
  # node whose content excludes the marker line.
  let firstText = md.parser.curr.token.strip()
  var alertType = ""
  if firstText.len >= 4 and firstText[0] == '[' and firstText[1] == '!':
    # `[!TYPE]` — read the identifier up to the closing bracket
    var j = 2
    while j < firstText.len and firstText[j] in IdentChars:
      inc j
    if j < firstText.len and firstText[j] == ']' and j == firstText.len - 1:
      let t = firstText[2 ..< j].toUpperAscii
      if t in ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]:
        alertType = t
  if alertType.len > 0:
    result = MarkdownNode(
      kind: mdkAlert,
      alertType: alertType,
      children: MarkdownNodeList(items: @[]),
      line: md.parser.curr.line
    )
    md.advance() # consume the `[!TYPE]` marker line
  else:
    result = MarkdownNode(
      kind: mdkBlockquote,
      children: MarkdownNodeList(items: @[]),
      line: md.parser.curr.line
    )
  # Collect all consecutive blockquote lines as inline content.
  # Lines are joined with a single space *before* inline parsing so that
  # (a) words split across a soft wrap keep their boundary, and
  # (b) inline markers spanning lines (e.g. `**bold` ... `text**`)
  # see their opening and closing markers in one pass.
  var parts: seq[string] = @[]
  while md.parser.curr.kind == mtkBlockquote:
    let quoteText = md.parser.curr.token.strip()
    if quoteText.len > 0:
      parts.add(quoteText)
    md.advance()
  if parts.len > 0:
    for n in md.parseInline(parts.join(" ")):
      result.children.items.add(n)

proc parsePipeRow(md: var Markdown): MarkdownNode =
  # Parse one pipe-delimited row. Expects curr.kind == mtkTable at row start.
  let rowLine = md.parser.curr.line
  result = MarkdownNode(
    kind: mdkTableRow,
    children: MarkdownNodeList(items: @[]),
    line: rowLine
  )

  var cell: seq[MarkdownNode]
  md.advance() # consume first '|'
  while md.parser.curr.kind != mtkEOF and md.parser.curr.line == rowLine:
    if md.parser.curr.kind == mtkTable:
      # Strip leading/trailing whitespace from cell text
      while cell.len > 0 and cell[0].kind == mdkText and cell[0].text.strip() == "":
        cell.delete(0)
      if cell.len > 0 and cell[0].kind == mdkText:
        var j = 0
        while j < cell[0].text.len and cell[0].text[j] in {' ', '\t'}:
          inc j
        cell[0].text = cell[0].text[j .. ^1]
      while cell.len > 0 and cell[^1].kind == mdkText and cell[^1].text.strip() == "":
        cell.delete(cell.len - 1)
      if cell.len > 0 and cell[^1].kind == mdkText:
        var j = cell[^1].text.len - 1
        while j >= 0 and cell[^1].text[j] in {' ', '\t'}:
          dec j
        cell[^1].text = cell[^1].text[0 .. j]
      result.children.items.add(MarkdownNode(
        kind: mdkTableCell,
        children: MarkdownNodeList(items: cell),
        line: rowLine
      ))
      setLen(cell, 0)
      md.advance() # consume '|'
    else:
      md.parseInline(cell)
  

proc isSeparatorLine(md: var Markdown): bool =
  ## Check if the current line looks like a table separator (---|---|--- or :---: etc.)
  if md.parser.curr.kind != mtkTable:
    return false
  let pos = md.parser.curr.post
  var start = pos
  while start > 0 and md.parser.lexer.input[start - 1] notin {'\n', '\r'}:
    dec start
  var lineEnd = pos
  while lineEnd < md.parser.lexer.input.len and
        md.parser.lexer.input[lineEnd] notin {'\n', '\r'}:
    inc lineEnd
  let lineContent = md.parser.lexer.input[start ..< lineEnd].strip()
  result = lineContent.len > 0 and
           lineContent.allCharsInSet({' ', '\t', '-', ':', '|', '='})

proc parseTable(md: var Markdown, currentParagraph: var MarkdownNode): MarkdownNode =
  # Parse a table starting with the header row
  # Header row
  let headerParsed = md.parsePipeRow()
  var headerRow = MarkdownNode(
    kind: mdkTableHeader,
    children: headerParsed.children,
    line: headerParsed.line
  )

  # Optional separator row: consume whole line if it looks like ---|---|---
  # todo support alignment indicators like :---, ---:, :---:
  # https://www.markdownguide.org/extended-syntax/#alignment
  if md.parser.curr.kind == mtkTable:
    let sepLine = md.parser.curr.line
    var sepText: string
    while md.parser.curr.kind != mtkEOF and md.parser.curr.line == sepLine:
      if md.parser.curr.kind != mtkTable:
        sepText.add(md.parser.curr.token)
      md.advance()
    if not sepText.contains("-"):
      discard

  result = MarkdownNode(
    kind: mdkTable,
    children: MarkdownNodeList(items: @[headerRow]),
    line: headerRow.line
  )

  # Body rows and optional footer
  var footerRows: seq[MarkdownNode]
  while md.parser.curr.kind == mtkTable:
    # Peek ahead: if this line looks like a separator (dashes/pipes), it's a footer delimiter
    if footerRows.len == 0 and md.isSeparatorLine():
      # Consume the separator line
      let sepLine = md.parser.curr.line
      while md.parser.curr.kind != mtkEOF and md.parser.curr.line == sepLine:
        md.advance()
      # Remaining rows are footer
      while md.parser.curr.kind == mtkTable:
        let row = md.parsePipeRow()
        if row.children.items.len > 0:
          footerRows.add(row)
      break
    else:
      let row = md.parsePipeRow()
      if row.children.items.len > 0:
        result.children.items.add(row)

  if footerRows.len > 0:
    result.children.items.add(MarkdownNode(
      kind: mdkTableFooter,
      children: MarkdownNodeList(items: footerRows),
      line: footerRows[0].line
    ))

#
# Init Marvdown with content and options
#
proc newParagraph*(curr: MarkdownTokenTuple): MarkdownNode =
  ## Create a new empty paragraph node
  MarkdownNode(
    kind: mdkParagraph,
    children: MarkdownNodeList(),
    line: curr.line
  )

template withCurrentParagraph(body: untyped): untyped =
  # Ensure currentParagraph is initialized
  if currentParagraph.isNil:
    currentParagraph = newParagraph(curr)
  body

template closeCurrentParagraph(): untyped =
  # Close and add the current paragraph to the AST if it exists
  if not currentParagraph.isNil:
    md.ast.add(currentParagraph)
    currentParagraph = nil

const blockLevelTags = {
  HtmlTag.tagDiv, HtmlTag.tagP, HtmlTag.tagH1, HtmlTag.tagH2,
  HtmlTag.tagH3, HtmlTag.tagH4, HtmlTag.tagH5, HtmlTag.tagH6,
  HtmlTag.tagBlockquote, HtmlTag.tagPre, HtmlTag.tagTable,
  HtmlTag.tagUl, HtmlTag.tagOl, HtmlTag.tagLi, HtmlTag.tagHr
}

let defaultOptions* = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
    tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagMark, tagSmall, tagSub, tagSup
  ],
  allowTagsByType: none(TagType),
  allowInlineStyle: false,
  allowHtmlAttributes: false,
  enableAnchors: true,
  enableEmailAutolinks: false
)

#
# MarkdownOptions from JSON/YAML config (snake_case keys)
#
# Nim uses camelCase; config files use snake_case. The two proc fields
# (`customTransform`, `codeBlockTransform`) are lib-only and intentionally
# not exposed here.
#

proc tagTypeFromConfig(s: string): TagType =
  ## Map an `allow_tags_by_type` value to `TagType` (case-insensitive,
  ## `tag`-prefixed variants accepted: `tagBlock` == `block`)
  let v = s.strip().toLowerAscii()
  let normalized =
    if v.startsWith("tag"): v[3 .. ^1]
    else: v
  case normalized
  of "none": tagNone
  of "inline": tagInline
  of "block": tagBlock
  of "all": tagAll
  else:
    raise newException(ValueError,
      "invalid allow_tags_by_type (expected none|inline|block|all): " & s)

proc htmlTagsFromConfig(names: seq[string]): seq[HtmlTag] =
  ## Map `allowed` tag names to `HtmlTag` (case-insensitive)
  for name in names:
    let tag = html.getHtmlTag(name.strip().toLowerAscii())
    if tag == tagUnknown:
      raise newException(ValueError, "unknown html tag in allowed: " & name)
    result.add(tag)

proc optionsFromJson*(base: MarkdownOptions, node: JsonNode): MarkdownOptions =
  ## Apply a parsed JSON config object onto `base` (snake_case keys).
  ## Keys present in the object replace `base`; missing keys keep `base`.
  ## Unknown keys and wrong types raise `ValueError`.
  if node.kind != JObject:
    raise newException(ValueError, "config root must be a JSON object")
  result = base
  for key, val in node.pairs:
    case key
    of "allowed":
      if val.kind != JArray:
        raise newException(ValueError, "allowed must be an array of tag names")
      var names: seq[string] = @[]
      for item in val.elems:
        if item.kind != JString:
          raise newException(ValueError, "allowed must be an array of tag names")
        names.add(item.getStr())
      result.allowed = htmlTagsFromConfig(names)
    of "allow_tags_by_type":
      if val.kind == JNull:
        result.allowTagsByType = none(TagType)
      elif val.kind == JString:
        let v = val.getStr().strip().toLowerAscii()
        if v in ["none", "null", ""]:
          result.allowTagsByType = none(TagType)
        else:
          result.allowTagsByType = some(tagTypeFromConfig(val.getStr()))
      else:
        raise newException(ValueError, "allow_tags_by_type must be a string or null")
    of "html_table_classes":
      if val.kind == JNull:
        result.htmlTableClasses = none(seq[string])
      elif val.kind == JArray:
        var classes: seq[string] = @[]
        for item in val.elems:
          if item.kind != JString:
            raise newException(ValueError, "html_table_classes must be an array of strings or null")
          classes.add(item.getStr())
        result.htmlTableClasses = some(classes)
      else:
        raise newException(ValueError, "html_table_classes must be an array of strings or null")
    of "anchor_icon":
      if val.kind != JString:
        raise newException(ValueError, "anchor_icon must be a string")
      result.anchorIcon = val.getStr()
    of "component_base_dir":
      if val.kind != JString:
        raise newException(ValueError, "component_base_dir must be a string")
      result.componentBaseDir = val.getStr()
    of "allow_inline_style", "allow_html_attributes", "enable_anchors",
       "show_footnotes", "enable_email_autolinks", "enable_components",
       "lazyload_iframes", "lazyload_videos", "lazyload_images", "parse_yaml":
      if val.kind != JBool:
        raise newException(ValueError, key & " must be a boolean")
      let b = val.getBool()
      case key
      of "allow_inline_style": result.allowInlineStyle = b
      of "allow_html_attributes": result.allowHtmlAttributes = b
      of "enable_anchors": result.enableAnchors = b
      of "show_footnotes": result.showFootnotes = b
      of "enable_email_autolinks": result.enableEmailAutolinks = b
      of "enable_components": result.enableComponents = b
      of "lazyload_iframes": result.lazyloadIframes = b
      of "lazyload_videos": result.lazyloadVideos = b
      of "lazyload_images": result.lazyloadImages = b
      else: result.parseYaml = b
    else:
      raise newException(ValueError, "unknown option (expected snake_case): " & key)

proc optionsFromYaml*(base: MarkdownOptions, obj: YAMLObject): MarkdownOptions =
  ## Apply a parsed YAML config mapping onto `base` (snake_case keys).
  ## Same semantics as `optionsFromJson`; raises `ValueError` on misuse.
  result = base
  if obj.isNil: return
  for key, val in obj.pairs:
    case key
    of "allowed":
      if val.isNil or val.kind != yamlArray:
        raise newException(ValueError, "allowed must be a list of tag names")
      var names: seq[string] = @[]
      for item in val.arrValue:
        if item.isNil or item.kind != yamlString:
          raise newException(ValueError, "allowed must be a list of tag names")
        names.add(item.strValue)
      result.allowed = htmlTagsFromConfig(names)
    of "allow_tags_by_type":
      if val.isNil or val.kind == yamlNull:
        result.allowTagsByType = none(TagType)
      elif val.kind == yamlString:
        let v = val.strValue.strip().toLowerAscii()
        if v in ["none", "null", "~", ""]:
          result.allowTagsByType = none(TagType)
        else:
          result.allowTagsByType = some(tagTypeFromConfig(val.strValue))
      else:
        raise newException(ValueError, "allow_tags_by_type must be a string or null")
    of "html_table_classes":
      if val.isNil or val.kind == yamlNull:
        result.htmlTableClasses = none(seq[string])
      elif val.kind == yamlArray:
        var classes: seq[string] = @[]
        for item in val.arrValue:
          if item.isNil or item.kind != yamlString:
            raise newException(ValueError, "html_table_classes must be a list of strings or null")
          classes.add(item.strValue)
        result.htmlTableClasses = some(classes)
      else:
        raise newException(ValueError, "html_table_classes must be a list of strings or null")
    of "anchor_icon":
      if val.isNil or val.kind != yamlString:
        raise newException(ValueError, "anchor_icon must be a string")
      result.anchorIcon = val.strValue
    of "component_base_dir":
      if val.isNil or val.kind != yamlString:
        raise newException(ValueError, "component_base_dir must be a string")
      result.componentBaseDir = val.strValue
    of "allow_inline_style", "allow_html_attributes", "enable_anchors",
       "show_footnotes", "enable_email_autolinks", "enable_components",
       "lazyload_iframes", "lazyload_videos", "lazyload_images", "parse_yaml":
      if val.isNil or val.kind != yamlBoolean:
        raise newException(ValueError, key & " must be a boolean")
      let b = val.boolValue
      case key
      of "allow_inline_style": result.allowInlineStyle = b
      of "allow_html_attributes": result.allowHtmlAttributes = b
      of "enable_anchors": result.enableAnchors = b
      of "show_footnotes": result.showFootnotes = b
      of "enable_email_autolinks": result.enableEmailAutolinks = b
      of "enable_components": result.enableComponents = b
      of "lazyload_iframes": result.lazyloadIframes = b
      of "lazyload_videos": result.lazyloadVideos = b
      of "lazyload_images": result.lazyloadImages = b
      else: result.parseYaml = b
    else:
      raise newException(ValueError, "unknown option (expected snake_case): " & key)

proc loadMarkdownOptions*(path: string, base: MarkdownOptions = defaultOptions): MarkdownOptions =
  ## Load `MarkdownOptions` from a `.json`, `.yaml` or `.yml` file (snake_case keys).
  ## Keys present in the file replace `base`; missing keys keep `base`.
  ## Raises `IOError` when the file is missing, `ValueError` on bad content.
  if not fileExists(path):
    raise newException(IOError, "config not found: " & path)
  let ext = path.splitFile().ext.toLowerAscii()
  let content = readFile(path)
  case ext
  of ".json":
    try:
      result = optionsFromJson(base, parseJson(content))
    except JsonParsingError as e:
      raise newException(ValueError, "invalid JSON config " & path & ": " & e.msg)
  of ".yaml", ".yml":
    result = optionsFromYaml(base, parseYAML(content))
  else:
    raise newException(ValueError, "unsupported config format (expected .json/.yaml/.yml): " & path)

proc optionsToJson*(opts: MarkdownOptions): JsonNode =
  ## Serialize `opts` to a JSON object with snake_case keys
  ## (inverse of `optionsFromJson`; proc fields are skipped)
  result = newJObject()
  var tags = newJArray()
  for tag in opts.allowed:
    tags.add(newJString($tag))
  result["allowed"] = tags
  if opts.allowTagsByType.isSome:
    let name =
      case opts.allowTagsByType.get()
      of tagNone: "none"
      of tagInline: "inline"
      of tagBlock: "block"
      of tagAll: "all"
    result["allow_tags_by_type"] = newJString(name)
  else:
    result["allow_tags_by_type"] = newJNull()
  result["allow_inline_style"] = newJBool(opts.allowInlineStyle)
  result["allow_html_attributes"] = newJBool(opts.allowHtmlAttributes)
  result["enable_anchors"] = newJBool(opts.enableAnchors)
  result["anchor_icon"] = newJString(opts.anchorIcon)
  result["show_footnotes"] = newJBool(opts.showFootnotes)
  if opts.htmlTableClasses.isSome:
    var classes = newJArray()
    for c in opts.htmlTableClasses.get():
      classes.add(newJString(c))
    result["html_table_classes"] = classes
  else:
    result["html_table_classes"] = newJNull()
  result["enable_email_autolinks"] = newJBool(opts.enableEmailAutolinks)
  result["enable_components"] = newJBool(opts.enableComponents)
  result["component_base_dir"] = newJString(opts.componentBaseDir)
  result["lazyload_iframes"] = newJBool(opts.lazyloadIframes)
  result["lazyload_videos"] = newJBool(opts.lazyloadVideos)
  result["lazyload_images"] = newJBool(opts.lazyloadImages)
  result["parse_yaml"] = newJBool(opts.parseYaml)

proc optionsToYaml*(opts: MarkdownOptions): YAMLObject =
  ## Serialize `opts` to a YAML mapping with snake_case keys
  ## (inverse of `optionsFromYaml`; proc fields are skipped)
  result = newOrderedTable[string, YamlNode]()
  var tags: seq[YamlNode] = @[]
  for tag in opts.allowed:
    tags.add(YamlNode(kind: yamlString, strValue: $tag))
  result["allowed"] = YamlNode(kind: yamlArray, arrValue: tags)
  if opts.allowTagsByType.isSome:
    let name =
      case opts.allowTagsByType.get()
      of tagNone: "none"
      of tagInline: "inline"
      of tagBlock: "block"
      of tagAll: "all"
    result["allow_tags_by_type"] = YamlNode(kind: yamlString, strValue: name)
  else:
    result["allow_tags_by_type"] = YamlNode(kind: yamlNull)
  result["allow_inline_style"] = YamlNode(kind: yamlBoolean, boolValue: opts.allowInlineStyle)
  result["allow_html_attributes"] = YamlNode(kind: yamlBoolean, boolValue: opts.allowHtmlAttributes)
  result["enable_anchors"] = YamlNode(kind: yamlBoolean, boolValue: opts.enableAnchors)
  result["anchor_icon"] = YamlNode(kind: yamlString, strValue: opts.anchorIcon)
  result["show_footnotes"] = YamlNode(kind: yamlBoolean, boolValue: opts.showFootnotes)
  if opts.htmlTableClasses.isSome:
    var classes: seq[YamlNode] = @[]
    for c in opts.htmlTableClasses.get():
      classes.add(YamlNode(kind: yamlString, strValue: c))
    result["html_table_classes"] = YamlNode(kind: yamlArray, arrValue: classes)
  else:
    result["html_table_classes"] = YamlNode(kind: yamlNull)
  result["enable_email_autolinks"] = YamlNode(kind: yamlBoolean, boolValue: opts.enableEmailAutolinks)
  result["enable_components"] = YamlNode(kind: yamlBoolean, boolValue: opts.enableComponents)
  result["component_base_dir"] = YamlNode(kind: yamlString, strValue: opts.componentBaseDir)
  result["lazyload_iframes"] = YamlNode(kind: yamlBoolean, boolValue: opts.lazyloadIframes)
  result["lazyload_videos"] = YamlNode(kind: yamlBoolean, boolValue: opts.lazyloadVideos)
  result["lazyload_images"] = YamlNode(kind: yamlBoolean, boolValue: opts.lazyloadImages)
  result["parse_yaml"] = YamlNode(kind: yamlBoolean, boolValue: opts.parseYaml)

proc configJsonString*(opts: MarkdownOptions): string =
  ## Pretty-printed JSON starter config (snake_case keys)
  result = optionsToJson(opts).pretty()
  if not result.endsWith("\n"):
    result.add("\n")

proc configYamlString*(opts: MarkdownOptions): string =
  ## YAML starter config (snake_case keys) with a short header comment
  const header = "# marvdown settings (snake_case = camelCase Nim opts)\n" &
    "# raw HTML tags in `allowed` (empty list = no raw HTML);\n" &
    "# `allow_tags_by_type`: none|inline|block|all (or null)\n"
  result = header & dump(optionsToYaml(opts))
  if not result.endsWith("\n"):
    result.add("\n")

proc yamlNodeToJson*(n: YamlNode): JsonNode =
  ## Convert a YAML node to its JSON equivalent (used for `fields`)
  if n.isNil:
    return newJNull()
  case n.kind
  of yamlNull: result = newJNull()
  of yamlBoolean: result = newJBool(n.boolValue)
  of yamlInteger: result = newJInt(n.intValue.int)
  of yamlFloat: result = newJFloat(n.floatValue)
  of yamlString: result = newJString(n.strValue)
  of yamlArray:
    result = newJArray()
    for item in n.arrValue:
      result.add(yamlNodeToJson(item))
  of yamlObject:
    result = newJObject()
    if not n.objValue.isNil:
      for k, v in n.objValue.pairs:
        result[k] = yamlNodeToJson(v)

proc headerJson*(md: Markdown): JsonNode =
  ## Front matter as JSON (`{}` when the document has none)
  result = newJObject()
  if md.headerYaml.isNil: return
  for k, v in md.headerYaml.pairs:
    result[k] = yamlNodeToJson(v)

proc lazyloadMediaSrc*(html: sink string, tagName: string): string =
  ## Rewrites the `src` attribute of `<tagName>` opening tags to `data-src`
  ## so the media is not loaded until a client-side script swaps it back.
  ## Leaves the rest of the HTML untouched.
  result = html
  if result.len == 0:
    return
  let tagPrefix = "<" & tagName
  let prefixLen = tagPrefix.len
  var i = 0
  while i < result.len:
    let tagStart = result.find(tagPrefix, i)
    if tagStart < 0:
      break
    # Find the end of the `<tagName ...>` opening tag, respecting quotes
    var tagEnd = tagStart + prefixLen
    var quote: char
    while tagEnd < result.len and result[tagEnd] != '>':
      if result[tagEnd] in {'"', '\''}:
        if quote == '\0': quote = result[tagEnd]
        elif quote == result[tagEnd]: quote = '\0'
      inc tagEnd
    # Scan for the `src` attribute inside the opening tag
    var j = tagStart + prefixLen
    while j < tagEnd:
      if result[j] in {'s', 'S'}:
        if j + 2 < result.len and result[j + 1] in {'r', 'R'} and result[j + 2] in {'c', 'C'}:
          let prev = if j > 0: result[j - 1] else: ' '
          let next = if j + 3 < tagEnd: result[j + 3] else: '='
          # Match `src` as an attribute name: preceded by whitespace and
          # followed by `=` or whitespace (skips `data-src`, `srcset`, `srcdoc`)
          if prev in {' ', '\t', '\n', '\r'} and next in {' ', '\t', '='}:
            result = result[0 ..< j] & "data-" & result[j .. ^1]
            inc tagEnd, 5
            break
      inc j
    i = tagEnd + 1

proc parseFootnoteDef(md: var Markdown): MarkdownNode = 
  ## Parse a footnote definition into a MarkdownNode
  let id = md.parser.curr.attrs.get()[0]
  let content = md.parser.curr.token.strip()
  result = MarkdownNode(
    kind: mdkFootnoteDef,
    footnoteId: id,
    children: MarkdownNodeList(),
    line: md.parser.curr.line
  )
  # Parse inline content of the footnote definition
  for n in md.parseInline(content):
    result.children.items.add(n)
  
  # Store the footnote definition in the Markdown instance
  if md.footnotes.isNil:
    md.footnotes = newOrderedTable[string, MarkdownNode]()
  md.footnotes[id] = result

proc parseMarkdown(md: var Markdown, currentParagraph: var MarkdownNode) =
  # Main parsing loop: iterate through tokens and build the AST
  while md.parser.curr.kind != mtkEOF:
    let curr = md.parser.curr
    case curr.kind
    of mtkText:
      withCurrentParagraph do:
        let textNode = md.parseText()
        currentParagraph.children.items.add(textNode)
      md.advance()
    of mtkLineBreak:
      # Hard line break: add <br> inside the current paragraph
      withCurrentParagraph do:
        currentParagraph.children.items.add(newRawHtml("<br>", curr.line))
      md.advance()
    of mtkParagraph:
      # Blank line / paragraph separator: close current paragraph
      closeCurrentParagraph()
      md.advance()
    #
    # Inline elements
    #
    of mtkLink:
      withCurrentParagraph do:
        let node = md.parseLink()
        currentParagraph.children.items.add(node)
        md.advance()
    of mtkStrong:
      # parse strong text and add to current paragraph
      withCurrentParagraph do:
        let node = md.parseStrong()
        currentParagraph.children.items.add(node)
    of mtkEmphasis:
      # parse emphasis text and add to current paragraph
      withCurrentParagraph do:
        let node = md.parseEmphasis()
        currentParagraph.children.items.add(node)
    of mtkStrikethrough:
      withCurrentParagraph do:
        let node = md.parseStrikethrough()
        currentParagraph.children.items.add(node)
    of mtkInlineCode:
      withCurrentParagraph do:
        let codeNode = MarkdownNode(
          kind: mdkInlineCode,
          inlineCode: curr.token,
          line: curr.line
        )
        currentParagraph.children.items.add(codeNode)
      md.advance()
    #
    # Block-level elements
    #
    of mtkHeading:
      closeCurrentParagraph()
      let text = curr.token.strip()
      let headingNode = newHeading(curr.attrs.get()[0].parseInt, curr.line)
      # parse inline content of the heading
      for n in md.parseInline(text):
        headingNode.children.items.add(n)
      md.ast.add(headingNode)
      md.advance()
    #
    # Tables
    # 
    of mtkTable:
      closeCurrentParagraph()
      let tableNode = md.parseTable(currentParagraph)
      md.ast.add(tableNode)
    #
    # Media elements
    #
    of mtkImage:
      closeCurrentParagraph()
      let imgNode = md.parseImage()
      md.ast.add(imgNode)
      md.advance()
    #
    # RAW HTML elements
    #
    of mtkHtml:
      closeCurrentParagraph()
      let tag = curr.attrs.get()[0]
      let tagType = html.getHtmlTag(tag)

      block checkAllowed:
        if md.opts.allowed.len > 0:
          if md.opts.allowed.contains(tagType):
            break checkAllowed
        elif md.opts.allowTagsByType.isSome:
          let byType = md.opts.allowTagsByType.get()
          if byType == tagAll:
            break checkAllowed
          if byType == tagBlock and tagType in blockLevelTags:
            break checkAllowed
          if byType == tagInline and tagType notin blockLevelTags:
            break checkAllowed

        withCurrentParagraph do:
          let textValue =
            curr.token.multiReplace(("<", "&lt;"), (">", "&gt;"))
          currentParagraph.children.items.add(MarkdownNode(
            kind: mdkText,
            text: textValue,
            line: curr.line
          ))
          md.advance()
          continue
      let htmlNode = MarkdownNode(
        kind: mdkHtml,
        html: block:
          var content = curr.token
          let withInner = md.renderHtmlWithInnerMarkdown(curr.token, tag, curr.line)
          if withInner.len > 0:
            content = withInner
          if md.opts.lazyloadIframes:
            content = lazyloadMediaSrc(content, "iframe")
          if md.opts.lazyloadVideos:
            content = lazyloadMediaSrc(content, "video")
            content = lazyloadMediaSrc(content, "source")
            content = lazyloadMediaSrc(content, "audio")
          if md.opts.lazyloadImages:
            content = lazyloadMediaSrc(content, "img")
          content,
        line: curr.line
      )
      if tagType notin blockLevelTags:
        # Inline HTML: add to current paragraph
        withCurrentParagraph do:
          currentParagraph.children.items.add(htmlNode)
        md.advance()
      else:
        # Block-level HTML: flush paragraph and add as block
        closeCurrentParagraph()
        md.ast.add(htmlNode)
        md.advance()
    #
    # Other block elements
    #
    of mtkListItem, mtkOListItem, mtkListItemCheckbox:
      closeCurrentParagraph()
      md.ast.add(md.parseList())
      # do not advance here, parseList already advances
    #
    # Code blocks
    #
    of mtkCodeBlock:
      # handle code blocks
      closeCurrentParagraph()
      let lang = if curr.attrs.isSome and curr.attrs.get().len > 0: curr.attrs.get()[0] else: ""
      let codeNode = MarkdownNode(
        kind: mdkCodeBlock,
        code: curr.token,
        codeLang: lang,
        line: curr.line
      )
      md.ast.add(codeNode)
      md.advance()
    #
    # Blockquotes
    #
    of mtkBlockquote:
      closeCurrentParagraph()
      let bqNode = md.parseBlockquote()
      md.ast.add(bqNode)
    #
    # Special elements
    #
    of mtkHorizontalRule:
      closeCurrentParagraph()
      md.ast.add(MarkdownNode(
        kind: mdkHorizontalRule,
        line: curr.line
      ))
      md.advance()
    #
    # Link definitions (invisible — already collected by pre-scan)
    #
    of mtkLinkDef:
      md.advance()
    #
    # Reference links
    #
    of mtkRefLink:
      let attrs = curr.attrs.get()
      let displayText = attrs[0]
      let isExplicit = attrs.len > 1 and attrs[1].len > 0 and attrs[1] != displayText
      let refLabel = if isExplicit: attrs[1].toLowerAscii
                     else: displayText.toLowerAscii
      if md.linkDefs.hasKey(refLabel):
        let def = md.linkDefs[refLabel]
        withCurrentParagraph do:
          let linkNode = newLink(def.url, def.title, curr.line)
          for n in md.parseInline(displayText):
            linkNode.children.items.add(n)
          currentParagraph.children.items.add(linkNode)
      else:
        withCurrentParagraph do:
          if isExplicit:
            currentParagraph.children.items.add(
              newText("[" & displayText & "][" & attrs[1] & "]", curr.line))
          else:
            currentParagraph.children.items.add(
              newText("[" & displayText & "]", curr.line))
      md.advance()
    #
    # YAML Front Matter
    #
    of mtkDocument:
      if md.opts.parseYaml:
        try:
          # Parse YAML front matter
          md.headerYaml = parseYAML(curr.token)
        except OpenParserYamlError as e:
          # On error, add a text node with the error message
          md.ast.add(MarkdownNode(
            kind: mdkText,
            text: curr.token, # invalid YAML, just add as text
            line: curr.line
          ))
      md.advance()
    #
    # Footnotes
    #
    of mtkFootnoteRef:
      withCurrentParagraph do:
        let id = curr.attrs.get()[0]
        let fnNode = MarkdownNode(
          kind: mdkFootnoteRef,
          footnoteRefId: id,
          line: curr.line
        )
        currentParagraph.children.items.add(fnNode)
      md.advance()
    of mtkFootnoteDef:
      closeCurrentParagraph() # close any open paragraph
      let node = md.parseFootnoteDef()
      md.ast.add(node)
      md.advance()
    else:
      closeCurrentParagraph()

proc collectLinkDefs(content: string): TableRef[string, tuple[url, title: string]] =
  ## Pre-scan the document for link definitions: [label]: url "title"
  result = newTable[string, tuple[url, title: string]]()
  # fast reject: link defs require "]:" (avoid 5MB lex when absent)
  if content.len < 4: return
  if find(content, "]:") < 0:
    return
  var lex = initLexer(content)
  var tok = lex.nextToken()
  while tok.kind != mtkEOF:
    if tok.kind == mtkLinkDef and tok.attrs.isSome:
      let a = tok.attrs.get()
      if a.len >= 2:
        let label = a[0].strip().toLowerAscii
        let url = a[1]
        let title = if a.len > 2: a[2] else: ""
        if not result.hasKey(label):
          result[label] = (url, title)
    tok = lex.nextToken()

proc newMarkdown*(content: sink string,
              opts: MarkdownOptions = defaultOptions): Markdown =
  ## Create a new Markdown instance
  var processedContent = content
  var scope: ComponentScope = nil

  if opts.enableComponents:
    scope = newComponentScope()
    let basePath =
      if opts.componentBaseDir.len > 0: opts.componentBaseDir
      else: getCurrentDir()
    var visited: seq[string] = @[]
    processedContent = preprocess(processedContent, basePath, scope, visited)

  if opts.customTransform != nil:
    processedContent = transformLines(processedContent, opts.customTransform)

  var md = Markdown(
    parser: MarkdownParser(lexer: initLexer(processedContent, opts.enableEmailAutolinks)),
    opts: opts,
    linkDefs: collectLinkDefs(processedContent),
    selectors: newOrderedTable[string, string](),
    selectorLevels: newOrderedTable[string, int](),
    selectorCounter: newCountTable[string]()
  )
  if opts.enableComponents:
    md.scope = scope
  md.parser.curr = md.parser.lexer.nextToken()
  md.parser.next = md.parser.lexer.nextToken()

  var currentParagraph: MarkdownNode
  md.parseMarkdown(currentParagraph)
  if not currentParagraph.isNil:
    md.ast.add(currentParagraph) # add any remaining paragraph
  md

proc toHtml*(md: var Markdown): string =
  ## Convert the parsed Markdown AST to HTML
  for node in md.ast:
    add result, md.renderNode(node)
  if md.opts.showFootnotes and md.footnotesHtml.len > 0:
    add result, "<hr><div class=\"footnotes\">" & md.footnotesHtml & "</div>"

proc dedentInnerMarkdown(s: string): string =
  ## Remove HTML-nesting indentation from `s` so Markdown nested inside
  ## HTML for readability is not misread as an indented code block.
  ## Blank lines are normalized to empty. Only lines that are indented
  ## participate in the common-indent calculation, and only lines with at
  ## least that indent are stripped — paragraph continuation lines that
  ## start at column 0 (e.g. soft-wrapped text inside a `<div>`) are left
  ## untouched instead of being corrupted.
  var lines = s.splitLines()
  var minIndent = high(int)
  for line in lines:
    if line.strip().len == 0: continue
    var indent = 0
    while indent < line.len and line[indent] in {' ', '\t'}:
      inc indent
    if indent == 0: continue # continuation line, not HTML nesting
    if indent < minIndent:
      minIndent = indent
  if minIndent == high(int) or minIndent == 0:
    return s
  result = newStringOfCap(s.len)
  for idx, line in lines:
    if line.strip().len == 0:
      discard
    else:
      var indent = 0
      while indent < line.len and line[indent] in {' ', '\t'}:
        inc indent
      if indent >= minIndent:
        result.add(line[minIndent .. ^1])
      else:
        result.add(line)
    if idx < lines.len - 1:
      result.add("\n")

proc innerHasBlankLine(s: string): bool =
  ## True when `s` (after trimming outer whitespace) contains an empty
  ## line. Used to distinguish block-level Markdown (keep `<p>` wrappers)
  ## from single-line inline Markdown (strip the single `<p>` wrapper so
  ## `<div>content</div>` stays `<div>content</div>`).
  let t = s.strip()
  if t.len == 0: return false
  for line in t.splitLines():
    if line.strip().len == 0:
      return true
  return false

const innerMarkdownTags = {
  tagDiv, tagSection, tagArticle, tagAside, tagHeader, tagFooter,
  tagMain, tagNav, tagFigure, tagFigcaption, tagDetails, tagSummary,
  tagBlockquote, tagP, tagSpan,
  tagH1, tagH2, tagH3, tagH4, tagH5, tagH6
}

proc renderHtmlWithInnerMarkdown(md: var Markdown, rawHtml: string,
    tagName: string, line: int): string =
  ## Re-parse Markdown found inside raw HTML container tags (e.g. `<div>`).
  ## Returns "" when the token should stay raw, otherwise the reassembled
  ## HTML (`openTag + renderedInner + closeTag`).
  ##
  ## - Block Markdown (blank lines inside) keeps its `<p>` wrappers.
  ## - Single-line inline Markdown strips the single `<p>` wrapper so
  ##   `<div>content</div>` and `<div>**bold**</div>` don't gain extra `<p>`.
  ## - Pure HTML (tables, lists, `pre`/`script`/`style`/`textarea`) stays raw.
  let lowerTag = tagName.toLowerAscii()
  let tagType = html.getHtmlTag(lowerTag)
  if tagType notin innerMarkdownTags:
    return ""
  if tagType in {tagPre, tagScript, tagStyle, tagTextarea}:
    return ""
  if html.isSelfClosing(tagType):
    return ""
  # Locate `<...>` opening tag end, respecting quotes.
  var startIdx = 0
  while startIdx < rawHtml.len and rawHtml[startIdx] in {' ', '\t', '\n', '\r'}:
    inc startIdx
  if startIdx >= rawHtml.len or rawHtml[startIdx] != '<':
    return ""
  if startIdx + 1 < rawHtml.len and rawHtml[startIdx + 1] == '/':
    return "" # lone closing tag like `</div>`
  var quote: char = '\0'
  var openEnd = -1
  var i = startIdx + 1
  while i < rawHtml.len:
    let c = rawHtml[i]
    if quote != '\0':
      if c == quote: quote = '\0'
    else:
      if c in {'"', '\''}: quote = c
      elif c == '>':
        openEnd = i
        break
    inc i
  if openEnd < 0:
    return ""
  # Self-closing `<div ... />` has no inner content.
  var k = openEnd - 1
  while k > startIdx and rawHtml[k] in {' ', '\t', '\n', '\r'}:
    dec k
  if k >= startIdx and rawHtml[k] == '/':
    return ""
  # Find outermost `</tag>` (last occurrence, case-insensitive).
  let lowerHtml = rawHtml.toLowerAscii()
  let closeMarker = "</" & lowerTag
  var closeStart = lowerHtml.rfind(closeMarker)
  if closeStart < 0 or closeStart <= openEnd:
    return "" # no closing tag (e.g. `<div>` without `</div>`)
  let closeEnd = rawHtml.find('>', closeStart)
  if closeEnd < 0:
    return ""
  var t = closeEnd + 1
  while t < rawHtml.len and rawHtml[t] in {' ', '\t', '\n', '\r'}:
    inc t
  if t != rawHtml.len:
    return "" # trailing content after closing tag; stay raw for safety
  let innerRaw = rawHtml[openEnd + 1 ..< closeStart]
  if innerRaw.strip().len == 0:
    return ""
  let dedented = dedentInnerMarkdown(innerRaw)
  if dedented.strip().len == 0:
    return ""
  var innerMd = newMarkdown(dedented, md.opts)
  var renderedInner = innerMd.toHtml()
  if renderedInner.strip() == dedented.strip():
    return "" # pure HTML, no Markdown parsed — keep raw to preserve e.g. `<p>`
  # Merge inner state (anchors, footnotes, link defs) into the outer doc.
  for anchor, title in innerMd.selectors:
    if not md.selectors.hasKey(anchor):
      md.selectors[anchor] = title
      md.selectorLevels[anchor] = innerMd.selectorLevels.getOrDefault(anchor, 2)
  for anchor, cnt in innerMd.selectorCounter:
    if md.selectorCounter.hasKey(anchor):
      if cnt > md.selectorCounter[anchor]:
        md.selectorCounter[anchor] = cnt
    else:
      md.selectorCounter[anchor] = cnt
  if innerMd.footnotes != nil and innerMd.footnotes.len > 0:
    if md.footnotes.isNil:
      md.footnotes = newOrderedTable[string, MarkdownNode]()
    for id, node in innerMd.footnotes:
      if not md.footnotes.hasKey(id):
        md.footnotes[id] = node
  if innerMd.footnotesHtml.len > 0:
    md.footnotesHtml.add(innerMd.footnotesHtml)
  for lk, lv in innerMd.linkDefs:
    if not md.linkDefs.hasKey(lk):
      md.linkDefs[lk] = lv
  let hasBlank = innerHasBlankLine(innerRaw)
  if not hasBlank:
    # No empty lines between blocks: either single-line inline Markdown
    # (strip the single `<p>` so `<div>content</div>` stays unchanged) or
    # a single non-paragraph block like `<pre>` / `<h1>` (keep as is).
    # Anything mixing `<p>` with other blocks stays raw for safety.
    if renderedInner.startsWith("<p>") and renderedInner.endsWith("</p>") and
        renderedInner.count("<p>") == 1:
      if not (renderedInner.contains("<ul") or renderedInner.contains("<ol") or
              renderedInner.contains("<pre") or renderedInner.contains("<h1") or
              renderedInner.contains("<h2") or renderedInner.contains("<h3") or
              renderedInner.contains("<h4") or renderedInner.contains("<h5") or
              renderedInner.contains("<h6") or renderedInner.contains("<blockquote") or
              renderedInner.contains("<table") or renderedInner.contains("<hr") or
              renderedInner.contains("<div")):
        renderedInner = renderedInner[3 .. ^5]
      else:
        return ""
    elif not renderedInner.contains("<p>"):
      discard # e.g. `<pre>`, `<h1>`, `<ul>` without surrounding blank lines: keep
    else:
      return ""
  let prefix = rawHtml[0 .. openEnd]
  let suffix = rawHtml[closeStart .. ^1]
  result = prefix & renderedInner & suffix

proc toJson*(md: Markdown): string =
  ## Convert the parsed Markdown AST to JSON
  toJson(md.ast)

#
# Stored AST: deserialize `json` command output back into nodes
# and render it to HTML without re-parsing Markdown source
#

proc jsonStr(node: JsonNode, field, default: string): string =
  ## Optional string field with a default (null/missing → default)
  if node.hasKey(field):
    let v = node[field]
    if v.kind == JString:
      return v.getStr()
    if v.kind != JNull:
      raise newException(ValueError, "AST field `" & field & "` must be a string")
  default

proc jsonInt(node: JsonNode, field: string, default: int): int =
  ## Optional integer field with a default (null/missing → default)
  if node.hasKey(field):
    let v = node[field]
    if v.kind == JInt:
      return v.getInt()
    if v.kind != JNull:
      raise newException(ValueError, "AST field `" & field & "` must be an integer")
  default

proc jsonBool(node: JsonNode, field: string, default: bool): bool =
  ## Optional boolean field with a default (null/missing → default)
  if node.hasKey(field):
    let v = node[field]
    if v.kind == JBool:
      return v.getBool()
    if v.kind != JNull:
      raise newException(ValueError, "AST field `" & field & "` must be a boolean")
  default

proc childrenFromJson(node: JsonNode): MarkdownNodeList =
  ## Child list for container nodes; empty list when null/missing.
  ## Mirrors the parser, which always creates a list for containers.
  result = MarkdownNodeList()
  if node.hasKey("children") and node["children"].kind == JObject:
    let items = node["children"].getOrDefault("items")
    if not items.isNil and items.kind == JArray:
      for c in items.elems:
        result.items.add(nodeFromJson(c))

proc optChildren(node: JsonNode): MarkdownNodeList =
  ## Child list for leaf nodes; nil when null/missing (mirrors the parser,
  ## e.g. `newText` / `newImage` create no child list)
  if node.hasKey("children") and node["children"].kind == JObject:
    return childrenFromJson(node)
  nil

proc nodeFromJson*(node: JsonNode): MarkdownNode =
  ## Deserialize one AST node from its JSON form (inverse of `toJson` output).
  ## Raises `ValueError` on malformed input.
  if node.isNil or node.kind != JObject:
    raise newException(ValueError, "AST node must be a JSON object")
  if not node.hasKey("kind") or node["kind"].kind != JString:
    raise newException(ValueError, "AST node is missing string field: kind")
  let kindStr = node["kind"].getStr()
  let line = jsonInt(node, "line", 1)
  case kindStr
  of "mdkText":
    result = MarkdownNode(kind: mdkText, text: jsonStr(node, "text", ""), line: line)
    result.children = optChildren(node)
  of "mdkElement":
    var attrs: seq[(string, string)] = @[]
    if node.hasKey("attrs") and node["attrs"].kind == JArray:
      for a in node["attrs"].elems:
        if a.kind == JArray and a.elems.len == 2 and
            a[0].kind == JString and a[1].kind == JString:
          attrs.add((a[0].getStr(), a[1].getStr()))
        else:
          raise newException(ValueError, "AST element attrs must be [[name, value], ...]")
    result = MarkdownNode(kind: mdkElement,
      tag: html.getHtmlTag(jsonStr(node, "tag", "")), attrs: attrs, line: line)
    result.children = childrenFromJson(node)
  of "mdkCodeBlock":
    result = MarkdownNode(kind: mdkCodeBlock,
      code: jsonStr(node, "code", ""),
      codeLang: jsonStr(node, "codeLang", ""), line: line)
    result.children = optChildren(node)
  of "mdkHeading":
    let lvl = jsonInt(node, "level", 1)
    if lvl notin 1 .. 6:
      raise newException(ValueError, "AST heading level out of range: " & $lvl)
    result = MarkdownNode(kind: mdkHeading, level: lvl, line: line)
    if node.hasKey("textAnchor") and node["textAnchor"].kind == JString:
      result.textAnchor = some(node["textAnchor"].getStr())
    result.children = childrenFromJson(node)
  of "mdkList":
    result = MarkdownNode(kind: mdkList,
      listOrdered: jsonBool(node, "listOrdered", false),
      listStart: jsonInt(node, "listStart", 1), line: line)
    result.children = childrenFromJson(node)
  of "mdkListItem":
    result = MarkdownNode(kind: mdkListItem, line: line)
    result.children = childrenFromJson(node)
  of "mdkBlockquote":
    result = MarkdownNode(kind: mdkBlockquote, line: line)
    result.children = childrenFromJson(node)
  of "mdkAlert":
    result = MarkdownNode(kind: mdkAlert,
      alertType: jsonStr(node, "alertType", ""), line: line)
    result.children = childrenFromJson(node)
  of "mdkHorizontalRule":
    result = MarkdownNode(kind: mdkHorizontalRule, line: line)
  of "mdkLineBreak":
    result = MarkdownNode(kind: mdkLineBreak, line: line)
  of "mdkLink":
    result = MarkdownNode(kind: mdkLink,
      linkHref: jsonStr(node, "linkHref", ""),
      linkTitle: jsonStr(node, "linkTitle", ""), line: line)
    result.children = childrenFromJson(node)
  of "mdkImage":
    result = MarkdownNode(kind: mdkImage,
      imageSrc: jsonStr(node, "imageSrc", ""),
      imageAlt: jsonStr(node, "imageAlt", ""),
      imageTitle: jsonStr(node, "imageTitle", ""), line: line)
    result.children = optChildren(node)
  of "mdkEmphasis":
    result = MarkdownNode(kind: mdkEmphasis, line: line)
    result.children = childrenFromJson(node)
  of "mdkStrong":
    result = MarkdownNode(kind: mdkStrong, line: line)
    result.children = childrenFromJson(node)
  of "mdkStrikethrough":
    result = MarkdownNode(kind: mdkStrikethrough, line: line)
    result.children = childrenFromJson(node)
  of "mdkInlineCode":
    result = MarkdownNode(kind: mdkInlineCode,
      inlineCode: jsonStr(node, "inlineCode", ""), line: line)
    result.children = optChildren(node)
  of "mdkHtml":
    result = MarkdownNode(kind: mdkHtml,
      html: jsonStr(node, "html", ""), line: line)
    result.children = optChildren(node)
  of "mdkTable":
    result = MarkdownNode(kind: mdkTable, line: line)
    result.children = childrenFromJson(node)
  of "mdkTableHeader":
    result = MarkdownNode(kind: mdkTableHeader, line: line)
    result.children = childrenFromJson(node)
  of "mdkTableRow":
    result = MarkdownNode(kind: mdkTableRow, line: line)
    result.children = childrenFromJson(node)
  of "mdkTableFooter":
    result = MarkdownNode(kind: mdkTableFooter, line: line)
    result.children = childrenFromJson(node)
  of "mdkTableCell":
    result = MarkdownNode(kind: mdkTableCell, line: line)
    result.children = childrenFromJson(node)
  of "mdkParagraph":
    result = MarkdownNode(kind: mdkParagraph, line: line)
    result.children = childrenFromJson(node)
  of "mdkFootnoteDef":
    result = MarkdownNode(kind: mdkFootnoteDef,
      footnoteId: jsonStr(node, "footnoteId", ""), line: line)
    result.children = childrenFromJson(node)
  of "mdkFootnoteRef":
    result = MarkdownNode(kind: mdkFootnoteRef,
      footnoteRefId: jsonStr(node, "footnoteRefId", ""), line: line)
    result.children = optChildren(node)
  of "mdkDocument":
    result = MarkdownNode(kind: mdkDocument, line: line)
    result.children = childrenFromJson(node)
  of "mdkUnknown":
    result = MarkdownNode(kind: mdkUnknown,
      info: jsonStr(node, "info", ""), line: line)
    result.children = optChildren(node)
  else:
    raise newException(ValueError, "unknown AST node kind: " & kindStr)

proc nodesFromJson*(s: string): seq[MarkdownNode] =
  ## Deserialize a stored AST (`json` command output) back into nodes.
  ## Raises `ValueError` on malformed input.
  var root: JsonNode
  try:
    root = parseJson(s)
  except JsonParsingError as e:
    raise newException(ValueError, "invalid AST JSON: " & e.msg)
  if root.kind != JArray:
    raise newException(ValueError, "AST JSON must be an array of nodes")
  for item in root.elems:
    result.add(nodeFromJson(item))

proc newMarkdownFromAst*(nodes: seq[MarkdownNode],
    opts: MarkdownOptions = defaultOptions): Markdown =
  ## Build a Markdown document from stored AST nodes for re-rendering to HTML.
  ## Options control rendering (anchors, table classes, lazy-load, footnotes).
  Markdown(
    opts: opts,
    ast: nodes,
    selectors: newOrderedTable[string, string](),
    selectorLevels: newOrderedTable[string, int](),
    selectorCounter: newCountTable[string]()
  )

proc astToHtml*(nodes: seq[MarkdownNode],
    opts: MarkdownOptions = defaultOptions): string =
  ## Render stored AST nodes back to HTML without re-parsing Markdown source
  var md = newMarkdownFromAst(nodes, opts)
  md.toHtml()

proc astToHtml*(astJson: string,
    opts: MarkdownOptions = defaultOptions): string =
  ## Parse stored AST JSON and render it back to HTML
  astToHtml(nodesFromJson(astJson), opts)

proc getSelectors*(md: Markdown): OrderedTableRef[string, string] =
  ## Get the headline selectors (anchors) from the parsed Markdown
  md.selectors

proc getSelectorItems*(md: Markdown): seq[tuple[level: int, anchor, title: string]] =
  ## Get the headline selectors with their heading levels (1-6),
  ## in document order. Useful for building nested tables of contents.
  for anchor, title in md.selectors:
    result.add((level: md.selectorLevels.getOrDefault(anchor, 2),
                anchor: anchor, title: title))

proc getSelectorsList*(md: Markdown): seq[string] =
  ## Get a sequence of headline selector values from the parsed Markdown
  md.selectors.values().toSeq()

proc hasSelectors*(md: Markdown): bool =
  ## Check if there are any headline selectors (anchors) in the parsed Markdown
  md.selectors != nil and md.selectors.len > 0

proc getHeader*(md: Markdown): YAMLObject =
  ## Get the parsed YAML front matter from the Markdown
  md.headerYaml

proc getFootnotes*(md: Markdown): OrderedTableRef[string, MarkdownNode] =
  ## Get the footnote definitions from the parsed Markdown
  md.footnotes

proc hasFootnotes*(md: Markdown): bool =
  ## Check if there are any footnote definitions in the parsed Markdown
  md.footnotes != nil and md.footnotes.len > 0

proc getTitle*(md: Markdown): string =
  ## Retrieve the first heading as the document title
  if md.selectors.len > 0:
    let firstKey = md.selectors.keys().toSeq()[0]
    md.selectors[firstKey]
  else: "Untitled document"

#
# HTML Entity Decoding
#
proc decodeHtmlEntities*(s: string): string =
  ## Decode HTML entities in a string (e.g., `&amp;` → `&`, `&#123;` → `{`).
  ## Unknown or malformed entities are passed through unchanged.
  if s.len == 0 or find(s, '&') < 0:
    return s
  # fast reject if '&' but no ';' after it
  if find(s, ';') < 0:
    return s
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '&':
      var semi = i + 1
      while semi < s.len and s[semi] != ';':
        inc semi
      if semi < s.len:
        let entity = s[i + 1 .. semi - 1]
        if entity.len > 0:
          var decoded: string
          if entity[0] == '#':
            if entity.len > 1 and entity[1] in {'x', 'X'}:
              try:
                let cp = parseHexInt(entity[2 .. ^1])
                if cp <= 0x10FFFF:
                  decoded = $Rune(cp)
              except ValueError: discard
            else:
              try:
                let cp = parseInt(entity[1 .. ^1])
                if cp <= 0x10FFFF:
                  decoded = $Rune(cp)
              except ValueError: discard
          else:
            case entity
            of "amp":   decoded = "&"
            of "lt":    decoded = "<"
            of "gt":    decoded = ">"
            of "quot":  decoded = "\""
            of "apos":  decoded = "'"
            of "nbsp":  decoded = "\u00A0"
            of "iexcl": decoded = "\u00A1"
            of "cent":  decoded = "\u00A2"
            of "pound": decoded = "\u00A3"
            of "curren": decoded = "\u00A4"
            of "yen":   decoded = "\u00A5"
            of "brvbar": decoded = "\u00A6"
            of "sect":  decoded = "\u00A7"
            of "uml":   decoded = "\u00A8"
            of "copy":  decoded = "\u00A9"
            of "ordf":  decoded = "\u00AA"
            of "laquo": decoded = "\u00AB"
            of "not":   decoded = "\u00AC"
            of "shy":   decoded = "\u00AD"
            of "reg":   decoded = "\u00AE"
            of "macr":  decoded = "\u00AF"
            of "deg":   decoded = "\u00B0"
            of "plusmn": decoded = "\u00B1"
            of "sup2":  decoded = "\u00B2"
            of "sup3":  decoded = "\u00B3"
            of "acute": decoded = "\u00B4"
            of "micro": decoded = "\u00B5"
            of "para":  decoded = "\u00B6"
            of "middot": decoded = "\u00B7"
            of "cedil": decoded = "\u00B8"
            of "sup1":  decoded = "\u00B9"
            of "ordm":  decoded = "\u00BA"
            of "raquo": decoded = "\u00BB"
            of "frac14": decoded = "\u00BC"
            of "frac12": decoded = "\u00BD"
            of "frac34": decoded = "\u00BE"
            of "iquest": decoded = "\u00BF"
            of "times": decoded = "\u00D7"
            of "divide": decoded = "\u00F7"
            of "Agrave": decoded = "\u00C0"
            of "Aacute": decoded = "\u00C1"
            of "Acirc":  decoded = "\u00C2"
            of "Atilde": decoded = "\u00C3"
            of "Auml":   decoded = "\u00C4"
            of "Aring":  decoded = "\u00C5"
            of "AElig":  decoded = "\u00C6"
            of "Ccedil": decoded = "\u00C7"
            of "Egrave": decoded = "\u00C8"
            of "Eacute": decoded = "\u00C9"
            of "Ecirc":  decoded = "\u00CA"
            of "Euml":   decoded = "\u00CB"
            of "Igrave": decoded = "\u00CC"
            of "Iacute": decoded = "\u00CD"
            of "Icirc":  decoded = "\u00CE"
            of "Iuml":   decoded = "\u00CF"
            of "ETH":    decoded = "\u00D0"
            of "Ntilde": decoded = "\u00D1"
            of "Ograve": decoded = "\u00D2"
            of "Oacute": decoded = "\u00D3"
            of "Ocirc":  decoded = "\u00D4"
            of "Otilde": decoded = "\u00D5"
            of "Ouml":   decoded = "\u00D6"
            of "Oslash": decoded = "\u00D8"
            of "Ugrave": decoded = "\u00D9"
            of "Uacute": decoded = "\u00DA"
            of "Ucirc":  decoded = "\u00DB"
            of "Uuml":   decoded = "\u00DC"
            of "Yacute": decoded = "\u00DD"
            of "THORN":  decoded = "\u00DE"
            of "szlig":  decoded = "\u00DF"
            of "agrave": decoded = "\u00E0"
            of "aacute": decoded = "\u00E1"
            of "acirc":  decoded = "\u00E2"
            of "atilde": decoded = "\u00E3"
            of "auml":   decoded = "\u00E4"
            of "aring":  decoded = "\u00E5"
            of "aelig":  decoded = "\u00E6"
            of "ccedil": decoded = "\u00E7"
            of "egrave": decoded = "\u00E8"
            of "eacute": decoded = "\u00E9"
            of "ecirc":  decoded = "\u00EA"
            of "euml":   decoded = "\u00EB"
            of "igrave": decoded = "\u00EC"
            of "iacute": decoded = "\u00ED"
            of "icirc":  decoded = "\u00EE"
            of "iuml":   decoded = "\u00EF"
            of "eth":    decoded = "\u00F0"
            of "ntilde": decoded = "\u00F1"
            of "ograve": decoded = "\u00F2"
            of "oacute": decoded = "\u00F3"
            of "ocirc":  decoded = "\u00F4"
            of "otilde": decoded = "\u00F5"
            of "ouml":   decoded = "\u00F6"
            of "oslash": decoded = "\u00F8"
            of "ugrave": decoded = "\u00F9"
            of "uacute": decoded = "\u00FA"
            of "ucirc":  decoded = "\u00FB"
            of "uuml":   decoded = "\u00FC"
            of "yacute": decoded = "\u00FD"
            of "thorn":  decoded = "\u00FE"
            of "yuml":   decoded = "\u00FF"
            of "ndash":  decoded = "\u2013"
            of "mdash":  decoded = "\u2014"
            of "lsquo":  decoded = "\u2018"
            of "rsquo":  decoded = "\u2019"
            of "ldquo":  decoded = "\u201C"
            of "rdquo":  decoded = "\u201D"
            of "bull":   decoded = "\u2022"
            of "hellip": decoded = "\u2026"
            of "prime":  decoded = "\u2032"
            of "Prime":  decoded = "\u2033"
            of "euro":   decoded = "\u20AC"
            of "trade":  decoded = "\u2122"
            else: discard
          if decoded.len > 0:
            result.add(decoded)
            i = semi + 1
            continue
      result.add(s[i])
    else:
      result.add(s[i])
    inc i

#
# Convert parsed Markdown to HTML
#
import std/htmlgen

proc renderNode(md: var Markdown, node: MarkdownNode): string =
  ## Render a single MarkdownNode to HTML. This proc is called recursively for child nodes.
  case node.kind
  of mdkText:
    result = decodeHtmlEntities(node.text)
    if node.children != nil:
      for child in node.children.items:
        result.add(md.renderNode(child))
  of mdkStrong:
    var content = ""
    for child in node.children.items:
      content.add(md.renderNode(child))
    result = strong(content)
  of mdkEmphasis:
    var content = ""
    for child in node.children.items:
      content.add(md.renderNode(child))
    result = em(content)
  of mdkStrikethrough:
    var content = ""
    for child in node.children.items:
      content.add(md.renderNode(child))
    result = del(content)
  of mdkLink:
    var linkContent = ""
    for child in node.children.items:
      linkContent.add(md.renderNode(child))
    result =
      if node.linkTitle.len > 0:
        a(href=node.linkHref, title=node.linkTitle, linkContent)
      else:
        a(href=node.linkHref, linkContent)
  of mdkImage:
    if md.opts.lazyloadImages:
      result = "<img data-src=\"" & node.imageSrc & "\" alt=\"" & node.imageAlt & "\" title=\"" & node.imageTitle & "\" />"
    else:
      result = img(src=node.imageSrc, alt=node.imageAlt, title=node.imageTitle)
  of mdkList:
    var listItems = ""
    for item in node.children.items:
      listItems.add(md.renderNode(item))
    if node.listOrdered:
      if node.listStart > 1:
        result = "<ol start=\"" & $node.listStart & "\">" & listItems & "</ol>"
      else:
        result = ol(listItems)
    else:
      result = ul(listItems)
  of mdkListItem:
    var itemContent = ""
    for child in node.children.items:
      itemContent.add(md.renderNode(child))
    result = li(itemContent)
  of mdkHeading:
    # Write headline with anchor if enabled
    var innerContent: string
    for childNode in node.children.items:
      innerContent.add(md.renderNode(childNode))

    if md.opts.enableAnchors:
      # if anchors are enabled, generate unique anchors
      let title = parseHtml(innerContent).innerText
      var anchor = slugify(title)
      if md.selectorCounter.contains(anchor):
        # make unique anchors - e.g., "heading-2", "heading-3", etc.
        let count = md.selectorCounter[anchor] + 1
        md.selectorCounter[anchor] = count
        anchor.add("-" & $count)
        md.selectors[anchor] = title
        md.selectorLevels[anchor] = node.level
      else: # first occurrence
        md.selectorCounter[anchor] = 1
        md.selectors[anchor] = title
        md.selectorLevels[anchor] = node.level
      let anchorlink =
            a(href="#" & anchor, `class`="anchor-link",
                    md.opts.anchorIcon)
      add result,
        case node.level
        of 1: h1(id=anchor, anchorlink, innerContent)
        of 2: h2(id=anchor, anchorlink, innerContent)
        of 3: h3(id=anchor, anchorlink, innerContent)
        of 4: h4(id=anchor, anchorlink, innerContent)
        of 5: h5(id=anchor, anchorlink, innerContent)
        else: h6(id=anchor, anchorlink, innerContent)
    else:
      add result,
        case node.level
        of 1: h1(innerContent)
        of 2: h2(innerContent)
        of 3: h3(innerContent)
        of 4: h4(innerContent)
        of 5: h5(innerContent)
        else: h6(innerContent)
  of mdkHtml:
    result = node.html
  of mdkParagraph:
    # Write paragraph
    var paraContent = ""
    for child in node.children.items:
      case child.kind
      of mdkHtml:
        paraContent.add(child.html)
      else:
        paraContent.add(md.renderNode(child))
    add result, p(paraContent)
  of mdkCodeBlock:
    # Code block with optional language class.
    # When `codeBlockTransform` is set, it produces the inner HTML
    # (e.g. backend syntax highlighting); "" falls back to default.
    if md.opts.codeBlockTransform != nil:
      let customHtml = md.opts.codeBlockTransform(node.codeLang, node.code)
      if customHtml.len > 0:
        result.add(
          pre(
            code(
              `class`=if node.codeLang.len > 0: "language-" & node.codeLang else: "",
              customHtml
            )
          )
        )
        return
    let codeBlock = node.code.multiReplace(
        ("<", "&lt;"), (">", "&gt;"),
        ("\"", "&quot;"), ("&", "&amp;")
      )
    result.add(
      pre(
        code(
          `class`=if node.codeLang.len > 0: "language-" & node.codeLang else: "",
          codeBlock.strip()
        )
      )
    )
  of mdkInlineCode:
    let inlineCode = node.inlineCode.multiReplace(
        ("<", "&lt;"), (">", "&gt;"),
        ("\"", "&quot;"), ("&", "&amp;")
      )
    result = code(inlineCode)
  of mdkBlockquote:
    var bqContent = ""
    for child in node.children.items:
      bqContent.add(md.renderNode(child))
    result = blockquote(bqContent)
  of mdkAlert:
    # GitHub-style alert: `> [!NOTE]` … rendered as a Bootstrap alert.
    # Type -> Bootstrap alert class (GFM convention).
    let cssClass =
      case node.alertType
      of "NOTE":       "info"
      of "TIP":        "success"
      of "IMPORTANT":  "primary"
      of "WARNING":    "warning"
      of "CAUTION":    "danger"
      else:            "info"
    var alertContent = ""
    for child in node.children.items:
      alertContent.add(md.renderNode(child))
    result = "<div class=\"alert alert-" & cssClass &
      " rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">" & alertContent & "</div></div>"
  of mdkTable:
    var html: string
    if md.opts.htmlTableClasses.isSome:
      html = "<table class=\"" & md.opts.htmlTableClasses.get().join(" ") & "\">"
    else:
      html = "<table>"
    var idx = 0
    if node.children.items.len > 0 and node.children.items[0].kind == mdkTableHeader:
      html.add(md.renderNode(node.children.items[0]))
      idx = 1
    html.add("<tbody>")
    while idx < node.children.items.len and node.children.items[idx].kind != mdkTableFooter:
      html.add(md.renderNode(node.children.items[idx]))
      inc idx
    html.add("</tbody>")
    if idx < node.children.items.len and node.children.items[idx].kind == mdkTableFooter:
      html.add(md.renderNode(node.children.items[idx]))
    html.add("</table>")
    result = html
  of mdkTableHeader:
    var html = "<thead><tr>"
    for cell in node.children.items:
      html.add("<th>")
      for child in cell.children.items:
        html.add(md.renderNode(child))
      html.add("</th>")
    html.add("</tr></thead>")
    result = html
  of mdkTableFooter:
    var html = "<tfoot>"
    for row in node.children.items:
      html.add("<tr>")
      for cell in row.children.items:
        html.add("<td>")
        for child in cell.children.items:
          html.add(md.renderNode(child))
        html.add("</td>")
      html.add("</tr>")
    html.add("</tfoot>")
    result = html
  of mdkTableRow:
    var html = "<tr>"
    for cell in node.children.items:
      html.add(md.renderNode(cell))
    html.add("</tr>")
    result = html
  of mdkTableCell:
    var html = "<td>"
    for child in node.children.items:
      html.add(md.renderNode(child))
    html.add("</td>")
    result = html    
  of mdkFootnoteRef:
    # Footnote reference rendering
    result = sup(
      `class`="footnote-ref",
      a(href="#fn-" & node.footnoteRefId, node.footnoteRefId)
    )
  of mdkFootnoteDef:
    # Footnote definition rendering (could be customized)
    var fnContent = ""
    for child in node.children.items:
      fnContent.add(md.renderNode(child))
    md.footnotesHtml.add(
      `div`(
        `class`="footnote",
        id="fn-" & node.footnoteId,
        sup(node.footnoteId),
        " ",
        fnContent
      )
    )
  of mdkHorizontalRule: result = "<hr>"
  else:
    echo node.kind
    echo "Warning: Unhandled MarkdownNode kind in renderNode"
