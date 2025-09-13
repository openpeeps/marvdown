# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[strutils, options, tables, unidecode, json]

import htmlparser {.all.}
export HtmlTag

import ./lexer, ./ast, renderer

type
  MarkdownParser* = object
    ## Internal: The parser state
    lexer: MarkdownLexer
    prev, curr, next: MarkdownTokenTuple

  HeadlineAnchor* = string

  Markdown* = ref object
    parser: MarkdownParser
      ## Internal: The markdown parser instance
    minify*: bool
      ## Minify the output HTML (default: true)
    opts*: MarkdownOptions
      ## Options for allowed HTML tags and attributes
    selectors*: CountTableRef[HeadlineAnchor]
      ## Internal: Used for generating unique headline anchors
    ast*: seq[MarkdownNode]
      ## The abstract syntax tree (AST) of the parsed markdown document

  TagType* = enum
    tagNone,       # No tags allowed
    tagInline,     # Inline tags (e.g., <b>, <i>, <a>)
    tagBlock,      # Block-level tags (e.g., <div>, <p>, <h1>)
    tagAll         # All tags allowed

  MarkdownOptions* = object
    allowed*: seq[HtmlTag]
      ## Allowed HTML tag names. See `defaultMarkdownOptions`
      ## Marv is using `HtmlTag` from `std/htmlparser`
      ## **Attention!** An empty `@[]` means all tags are allowed.
    allowTagsByType*: TagType
      ## Allow HTML tags by their types. Default `tagNone`
      ## This option is not used by default, instead, just a little
      ## list of `HtmlTag`. See `allowed` sequence
    allowInlineStyle*: bool
      ## Allow CSS styling using `style` tag (disabled by default)
    allowHtmlAttributes*: bool
      ## Allow using html attributes, `width`, `title` and so on.
      ## For allowing use of `style` attribute, enable `allowInlineStyle`.
    enableAnchors*: bool
      ## Enable anchor generation in title blocks (enabled by default)

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
      result.add if lowercase: c.toLowerAscii else: c
    of Digits:
      result.add c
    else: discard

proc parseImage(md: var Markdown): MarkdownNode =
  ## Parse an image token into a MarkdownNode
  let attrs = md.parser.curr.attrs.get()
  if attrs.len >= 2:
    let alt = attrs[0]
    let src = attrs[1]
    let title = if attrs.len > 2: attrs[2] else: ""
    result = MarkdownNode(
      kind: mdkImage,
      imageAlt: alt,
      imageSrc: src,
      imageTitle: title,
      line: md.parser.curr.line,
      wsno: md.parser.curr.wsno
    )

proc parseLink(md: var Markdown): MarkdownNode =
  # Parse a link token into a MarkdownNode
  let attrs = md.parser.curr.attrs.get()
  if attrs.len >= 2:
    let text = attrs[0]
    let href = attrs[1]
    let title = if attrs.len > 2: attrs[2] else: ""
    let textNode = MarkdownNode(
      kind: mdkText,
      text: text,
      line: md.parser.curr.line,
      wsno: md.parser.curr.wsno
    )
    result = MarkdownNode(
      kind: mdkLink,
      linkHref: href,
      linkTitle: title,
      children: MarkdownNodeList(items: @[textNode]),
      line: md.parser.curr.line,
      wsno: md.parser.curr.wsno
    )

proc parseText(md: var Markdown): MarkdownNode =
  # Parse a text token into a MarkdownNode
  result = MarkdownNode(
    kind: mdkText,
    text: md.parser.curr.token,
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )

proc parseStrong(md: var Markdown): MarkdownNode =
  # Parse strong text and add to current paragraph
  md.advance() # Skip opening strong
  var strongChildren = newSeq[MarkdownNode]()
  while md.parser.curr.kind notin {mtkStrong, mtkEOF}:
    case md.parser.curr.kind
    of mtkText:
      strongChildren.add(md.parseText())
    of mtkEmphasis:
      # Recursively parse emphasis inside strong
      var emphNode = MarkdownNode(
        kind: mdkEmphasis,
        children: MarkdownNodeList(),
        line: md.parser.curr.line,
        wsno: md.parser.curr.wsno
      )
      md.advance()
      var emphChildren = newSeq[MarkdownNode]()
      while md.parser.curr.kind notin {mtkEmphasis, mtkStrong, mtkEOF}:
        if md.parser.curr.kind == mtkText:
          emphChildren.add(md.parseText())
        else:
          break
        md.advance()
      emphNode.children = MarkdownNodeList(items: emphChildren)
      strongChildren.add(emphNode)
    else: break
    md.advance()
  result = MarkdownNode(
    kind: mdkStrong,
    children: MarkdownNodeList(items: strongChildren),
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )
  if md.parser.curr.kind == mtkStrong:
    md.advance() # Skip closing strong

proc parseEmphasis(md: var Markdown): MarkdownNode =
  # Parse emphasis text and add to current paragraph
  md.advance() # Skip opening emphasis
  result = MarkdownNode(
    kind: mdkEmphasis,
    children: MarkdownNodeList(),
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )
  while md.parser.curr.kind notin {mtkEmphasis, mtkEOF}:
    if md.parser.curr.kind == mtkText:
      result.children.items.add(md.parseText())
    else: break
    md.advance()
  if md.parser.curr.kind == mtkEmphasis:
    md.advance() # Skip closing emphasis

proc parseInline(md: var Markdown, text: string): seq[MarkdownNode] =
  var lex = initLexer(text)
  var curr = lex.nextToken()
  let ln = curr.line
  while curr.kind != mtkEOF:
    if curr.line != ln: break
    case curr.kind
    of mtkText:
      result.add(MarkdownNode(
        kind: mdkText,
        text: curr.token,
        line: curr.line,
        wsno: curr.wsno
      ))
      curr = lex.nextToken()
    of mtkEmphasis:
      let startCol = curr.col
      let next = lex.nextToken()
      if next.kind == mtkText:
        let after = lex.nextToken()
        if after.kind == mtkEmphasis:
          result.add(MarkdownNode(
            kind: mdkEmphasis,
            children: MarkdownNodeList(items: @[MarkdownNode(
              kind: mdkText,
              text: next.token,
              line: next.line,
              wsno: next.wsno
            )]),
            line: curr.line,
            wsno: curr.wsno
          ))
          curr = lex.nextToken()
          continue
        else:
          result.add(MarkdownNode(
            kind: mdkText,
            text: text[startCol-1 ..< text.len],
            line: curr.line,
            wsno: curr.wsno
          ))
          curr = after
          continue
      else:
        result.add(MarkdownNode(
          kind: mdkText,
          text: text[startCol-1 ..< text.len],
          line: curr.line,
          wsno: curr.wsno
        ))
        curr = next
        continue
    of mtkLink:
      # Parse link inline
      if curr.attrs.isSome and curr.attrs.get().len >= 2:
        let textVal = curr.attrs.get()[0]
        let hrefVal = curr.attrs.get()[1]
        let titleVal = if curr.attrs.get().len > 2: curr.attrs.get()[2] else: ""
        let textNode = MarkdownNode(
          kind: mdkText,
          text: textVal,
          line: curr.line,
          wsno: curr.wsno
        )
        result.add(MarkdownNode(
          kind: mdkLink,
          linkHref: hrefVal,
          linkTitle: titleVal,
          children: MarkdownNodeList(items: @[textNode]),
          line: curr.line,
          wsno: curr.wsno
        ))
      curr = lex.nextToken()
    of mtkImage:
      # Parse image inline
      if curr.attrs.isSome and curr.attrs.get().len >= 2:
        let alt = curr.attrs.get()[0]
        let src = curr.attrs.get()[1]
        let title = if curr.attrs.get().len > 2: curr.attrs.get()[2] else: ""
        result.add(MarkdownNode(
          kind: mdkImage,
          imageAlt: alt,
          imageSrc: src,
          imageTitle: title,
          line: curr.line,
          wsno: curr.wsno
        ))
      curr = lex.nextToken()
    of mtkInlineCode:
      result.add(MarkdownNode(
        kind: mdkInlineCode,
        inlineCode: curr.token,
        line: curr.line,
        wsno: curr.wsno
      ))
      curr = lex.nextToken()
    of mtkStrong:
      var strongChildren: seq[MarkdownNode] = @[]
      let strongLine = curr.line
      let strongWsno = curr.wsno
      curr = lex.nextToken()
      while curr.kind != mtkStrong and curr.kind != mtkEOF:
        case curr.kind
        of mtkText:
          strongChildren.add(MarkdownNode(
            kind: mdkText,
            text: curr.token,
            line: curr.line,
            wsno: curr.wsno
          ))
        of mtkEmphasis:
          var emphChildren: seq[MarkdownNode] = @[]
          let emphLine = curr.line
          let emphWsno = curr.wsno
          curr = lex.nextToken()
          while curr.kind != mtkEmphasis and curr.kind != mtkStrong and curr.kind != mtkEOF:
            if curr.kind == mtkText:
              emphChildren.add(MarkdownNode(
                kind: mdkText,
                text: curr.token,
                line: curr.line,
                wsno: curr.wsno
              ))
            curr = lex.nextToken()
          strongChildren.add(MarkdownNode(
            kind: mdkEmphasis,
            children: MarkdownNodeList(items: emphChildren),
            line: emphLine,
            wsno: emphWsno
          ))
        else:
          strongChildren.add(MarkdownNode(
            kind: mdkText,
            text: curr.token,
            line: curr.line,
            wsno: curr.wsno
          ))
        curr = lex.nextToken()
      result.add(MarkdownNode(
        kind: mdkStrong,
        children: MarkdownNodeList(items: strongChildren),
        line: strongLine,
        wsno: strongWsno
      ))
      if curr.kind == mtkStrong:
        curr = lex.nextToken()
    else:
      result.add(MarkdownNode(
        kind: mdkText,
        text: curr.token,
        line: curr.line,
        wsno: curr.wsno
      ))
      curr = lex.nextToken()

proc parseListItem(md: var Markdown): MarkdownNode =
  # Parse a single list item, handling nested lists recursively
  let itemText = md.parser.curr.token.strip()
  let indentLevel = md.parser.curr.wsno
  let isOrdered = md.parser.curr.kind == mtkOListItem
  result = MarkdownNode(
    kind: mdkListItem,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )
  if itemText.len > 0:
    for n in md.parseInline(itemText):
      result.children.items.add(n)
  md.advance()
  # Check for nested lists
  while md.parser.curr.kind in {mtkListItem, mtkOListItem}:
    let nextIndent = md.parser.curr.wsno
    let nextOrdered = md.parser.curr.kind == mtkOListItem
    if nextIndent > indentLevel:
      # Nested list: parse all at this deeper indent
      var nestedList = MarkdownNode(
        kind: mdkList,
        listOrdered: nextOrdered,
        children: MarkdownNodeList(items: @[]),
        line: md.parser.curr.line,
        wsno: md.parser.curr.wsno
      )
      while md.parser.curr.kind in {mtkListItem, mtkOListItem} and md.parser.curr.wsno == nextIndent:
        let nestedItem = md.parseListItem()
        nestedList.children.items.add(nestedItem)
      result.children.items.add(nestedList)
    else: break

proc parseList(md: var Markdown): MarkdownNode =
  # Parse a sequence of list items into a single list node
  let startIndent = md.parser.curr.wsno
  let isOrdered = md.parser.curr.kind == mtkOListItem
  result = MarkdownNode(
    kind: mdkList,
    listOrdered: isOrdered,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )
  while md.parser.curr.kind in {mtkListItem, mtkOListItem} and md.parser.curr.wsno == startIndent:
    # If the list type changes, break and let the main parser handle the new list
    if (md.parser.curr.kind == mtkOListItem) != isOrdered:
      break
    let itemNode = md.parseListItem()
    result.children.items.add(itemNode)

proc parseBlockquote(md: var Markdown): MarkdownNode =
  ## Parse one or more consecutive blockquote tokens into a blockquote node
  let startIndent = md.parser.curr.wsno
  result = MarkdownNode(
    kind: mdkBlockquote,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line,
    wsno: md.parser.curr.wsno
  )
  while md.parser.curr.kind == mtkBlockquote and md.parser.curr.wsno == startIndent:
    let quoteText = md.parser.curr.token.strip()
    # Parse inline content of the blockquote
    for n in md.parseInline(quoteText):
      result.children.items.add(n)
    md.advance()
    # Handle nested blockquotes ("> > ...")
    if md.parser.curr.kind == mtkBlockquote and md.parser.curr.wsno > startIndent:
      let nested = md.parseBlockquote()
      result.children.items.add(nested)


#
# Init Marvdown with content and options
#
template withCurrentParagraph(body: untyped): untyped =
  # Ensure currentParagraph is initialized
  if currentParagraph.isNil:
    currentParagraph = MarkdownNode(
      kind: mdkParagraph,
      children: MarkdownNodeList(),
      line: md.parser.curr.line,
      wsno: md.parser.curr.wsno
    )
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

let defaultOptions = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
    tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl
  ],
  allowTagsByType: tagNone,
  allowInlineStyle: false,
  allowHtmlAttributes: false,
  enableAnchors: true
)

proc newMarkdown*(content: sink string, opts: MarkdownOptions = defaultOptions): Markdown =
  ## Create a new Markdown instance
  var md = Markdown(
    parser: MarkdownParser(lexer: initLexer(content)),
    opts: opts,
    selectors: newCountTable[HeadlineAnchor]()
  )
  md.parser.curr = md.parser.lexer.nextToken()
  md.parser.next = md.parser.lexer.nextToken()
  var currentParagraph: MarkdownNode
  while md.parser.curr.kind != mtkEOF:
    let curr = md.parser.curr
    case curr.kind
    of mtkText:
      if currentParagraph.isNil:
        currentParagraph = MarkdownNode(
          kind: mdkParagraph,
          children: MarkdownNodeList(),
          line: curr.line,
          wsno: curr.wsno
        )
      elif curr.col == 0:
        if md.ast.len > 0 and curr.line - currentParagraph.line > 2:
          # New paragraph after blank line
          closeCurrentParagraph() # Flush existing paragraph
          currentParagraph = MarkdownNode(
            kind: mdkParagraph,
            children: MarkdownNodeList(),
            line: curr.line,
            wsno: curr.wsno
          )
      let textNode = md.parseText()
      currentParagraph.children.items.add(textNode)
      md.advance()
    of mtkImage:
      closeCurrentParagraph()
      let imgNode = md.parseImage()
      md.ast.add(imgNode)
      md.advance()
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
    of mtkHeading:
      closeCurrentParagraph()
      let text = curr.token.strip()
      let headingNode = MarkdownNode(
        kind: mdkHeading,
        level: curr.attrs.get()[0].parseInt,
        textHeading: text,
        children: nil,
        line: curr.line,
        wsno: curr.wsno
      )
      if md.opts.enableAnchors:
        var anchor = slugify(text)
        if md.selectors.contains(anchor):
          # make unique anchors - e.g., "heading-2", "heading-3", etc.
          let count = md.selectors[anchor] + 1
          md.selectors[anchor] = count
          anchor.add("-" & $count)
        else: # first occurrence
          md.selectors[anchor] = 1
        headingNode.textAnchor = some(anchor)
      md.ast.add(headingNode)
      md.advance()
    of mtkHtml:
      let tag = curr.attrs.get()[0]
      let tagType = htmlparser.htmlTag(tag)
      if md.opts.allowed.len > 0:
        if not md.opts.allowed.contains(tagType):
          withCurrentParagraph do:
            let textValue =
              curr.token.multiReplace(("<", "&lt;"), (">", "&gt;"))
            currentParagraph.children.items.add(MarkdownNode(
              kind: mdkText,
              text: textValue,
              line: curr.line,
              wsno: curr.wsno
            ))
            md.advance()
            continue
      let htmlNode = MarkdownNode(
        kind: mdkHtml,
        html: curr.token,
        line: curr.line,
        wsno: curr.wsno
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
    of mtkListItem, mtkOListItem:
      closeCurrentParagraph()
      md.ast.add(md.parseList())
      # do not advance here, parseList already advances
    of mtkCodeBlock:
      # handle code blocks
      closeCurrentParagraph()
      let lang = if curr.attrs.isSome and curr.attrs.get().len > 0: curr.attrs.get()[0] else: ""
      let codeNode = MarkdownNode(
        kind: mdkCodeBlock,
        code: curr.token,
        codeLang: lang,
        line: curr.line,
        wsno: curr.wsno
      )
      md.ast.add(codeNode)
      md.advance()
    of mtkInlineCode:
      withCurrentParagraph do:
        let codeNode = MarkdownNode(
          kind: mdkInlineCode,
          inlineCode: curr.token,
          line: curr.line,
          wsno: curr.wsno
        )
        currentParagraph.children.items.add(codeNode)
      md.advance()
    of mtkBlockquote:
      closeCurrentParagraph()
      let bqNode = md.parseBlockquote()
      md.ast.add(bqNode)
    else:
      closeCurrentParagraph()
      md.advance()

  if not currentParagraph.isNil:
    # Add any remaining paragraph to the AST
    md.ast.add(currentParagraph)
  md # returns the markdown instance

proc toHtml*(md: Markdown): string =
  ## Convert the parsed Markdown AST to HTML
  for node in md.ast:
    add result, renderer.renderNode(node)
