# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[strutils, sequtils, options,
        tables, unidecode, json, xmltree]

import htmlparser {.all.}
export HtmlTag

import ./lexer, ./ast
import pkg/[jsony, nyml]

type
  MarkdownParser* = object
    ## Internal: The parser state
    lexer: MarkdownLexer
    prev, curr, next: MarkdownTokenTuple

  Markdown* = ref object
    parser: MarkdownParser
      ## Internal: The markdown parser instance
    minify*: bool
      ## Minify the output HTML (default: true)
    opts*: MarkdownOptions
      ## Options for allowed HTML tags and attributes
    selectors: OrderedTableRef[string, string]
      ## Internal: Used for generating unique headline anchors
    selectorCounter: CountTableRef[string]
      ## Internal: Counter for generating unique selectors
    ast*: seq[MarkdownNode]
      ## The abstract syntax tree (AST) of the parsed markdown document
    headerYaml: JsonNode
      ## Parsed YAML front matter as JsonNode
    footnotes: OrderedTableRef[string, MarkdownNode]
      ## Footnote definitions parsed from the document
    footnotesHtml*: string
      ## Generated HTML for footnotes at the end of the document

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
      # TODO an empty seq should not mean all tags allowed, just none extra
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

#
# forward declarations
#
proc renderNode(md: var Markdown, node: MarkdownNode): string
proc parseInline(md: var Markdown, text: string): seq[MarkdownNode]
proc parseEmphasis(md: var Markdown): MarkdownNode

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
    let textNode = newText(text, md.parser.curr.line)
    result = newLink(href, title, md.parser.curr.line)
    result.children.items.add(textNode)

proc parseText(md: var Markdown): MarkdownNode =
  # Parse a text token into a MarkdownNode
  newText(md.parser.curr.token, md.parser.curr.line)

proc parseStrong(md: var Markdown): MarkdownNode =
  # Parse strong text and add to current paragraph
  let tk = md.parser.curr
  md.advance() # Skip opening strong
  var strongChildren = newSeq[MarkdownNode]()
  while md.parser.curr.kind notin {mtkStrong, mtkEOF}:
    case md.parser.curr.kind
    of mtkText:
      strongChildren.add(md.parseText())
    of mtkEmphasis:
      let emphNode = md.parseEmphasis()
      strongChildren.add(emphNode)
      # # Recursively parse emphasis inside strong
      # var emphNode = MarkdownNode(
      #   kind: mdkEmphasis,
      #   children: MarkdownNodeList(),
      #   line: md.parser.curr.line
      # )
      # md.advance()
      # var emphChildren = newSeq[MarkdownNode]()
      # while md.parser.curr.kind notin {mtkEmphasis, mtkStrong, mtkEOF}:
      #   if md.parser.curr.kind == mtkText:
      #     emphChildren.add(md.parseText())
      #   else:
      #     break
      #   md.advance()
      # emphNode.children = MarkdownNodeList(items: emphChildren)
      # strongChildren.add(emphNode)
    else: break
    md.advance()

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
  ## Parse a checkbox list item ([ ] or [x])
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
  md.advance()

proc parseEmphasis(md: var Markdown): MarkdownNode =
  # Parse emphasis text and add to current paragraph
  let tk = md.parser.curr
  md.advance() # Skip opening emphasis
  var str: string
  while md.parser.curr.kind != mtkEmphasis and md.parser.curr.line == tk.line:
    if md.parser.curr.kind == mtkEOF: break
    str.add(md.parser.curr.token)
    md.advance()
  if md.parser.curr.kind == mtkEmphasis and md.parser.curr.line == tk.line:
    result = MarkdownNode(
      kind: mdkEmphasis,
      children: MarkdownNodeList(items: md.parseInline(str)),
      line: tk.line
    )
    md.advance() # Skip closing emphasis
  else:
    # Unclosed emphasis, treat as text
    result = MarkdownNode(kind: mdkText, line: tk.line)
    result.text = "*" & str

proc parseInline(md: var Markdown, text: string): seq[MarkdownNode] =
  var lex = initLexer(text)
  var curr = lex.nextToken()
  let ln = curr.line
  while curr.kind != mtkEOF:
    if curr.line != ln: break
    var node: MarkdownNode
    case curr.kind
    of mtkText:
      node = MarkdownNode(
        kind: mdkText,
        text: curr.token,
        line: curr.line
      )
      curr = lex.nextToken()
    of mtkEmphasis:
      let startCol = curr.col
      curr = lex.nextToken()
      var str = "*"
      while curr.kind != mtkEmphasis and curr.line == ln:
        if curr.kind == mtkEOF: break
        str.add(curr.token)
        curr = lex.nextToken()
      # if next.kind == mtkText:
      #   let after = lex.nextToken()
      #   if after.kind == mtkEmphasis:
      #     node = MarkdownNode(
      #       kind: mdkEmphasis,
      #       children: MarkdownNodeList(items: @[MarkdownNode(
      #         kind: mdkText,
      #         text: next.token,
      #         line: next.line,
      #         wsno: next.wsno
      #       )]),
      #       line: curr.line,
      #       wsno: curr.wsno
      #     )
      #     curr = lex.nextToken()
      #   else:
      #     node = MarkdownNode(
      #       kind: mdkText,
      #       text: text[startCol-1 ..< text.len],
      #       line: curr.line,
      #       wsno: curr.wsno
      #     )
      #     curr = after
      # else:
      #   node = MarkdownNode(
      #     kind: mdkText,
      #     text: text[startCol-1 ..< text.len],
      #     line: curr.line,
      #     wsno: curr.wsno
      #   )
      #   curr = next
    of mtkLink:
      # Parse link inline
      if curr.attrs.isSome and curr.attrs.get().len >= 2:
        let textVal = curr.attrs.get()[0]
        let hrefVal = curr.attrs.get()[1]
        let titleVal =
          if curr.attrs.get().len > 2:
            curr.attrs.get()[2]
          else: "" # no title

        let textNode = MarkdownNode(
          kind: mdkText,
          text: textVal,
          line: curr.line
        )
        let linkNode = MarkdownNode(
          kind: mdkLink,
          linkHref: hrefVal,
          linkTitle: titleVal,
          children: MarkdownNodeList(),
          line: curr.line
        )
        for n in md.parseInline(textVal):
          linkNode.children.items.add(n)
        result.add(linkNode)
      curr = lex.nextToken()
    of mtkImage:
      # Parse image inline
      if curr.attrs.isSome and curr.attrs.get().len >= 2:
        let alt = curr.attrs.get()[0]
        let src = curr.attrs.get()[1]
        let title =
          if curr.attrs.get().len > 2:
            curr.attrs.get()[2]
          else: ""
        node = newImage(alt, src, title, curr.line)
      curr = lex.nextToken()
    of mtkInlineCode:
      node = MarkdownNode(
        kind: mdkInlineCode,
        inlineCode: curr.token,
        line: curr.line
      )
      curr = lex.nextToken()
    of mtkStrong:
      var strongChildren: seq[MarkdownNode] = @[]
      let strongLine = curr.line
      curr = lex.nextToken()
      while curr.kind != mtkStrong and curr.kind != mtkEOF:
        case curr.kind
        of mtkText:
          strongChildren.add(MarkdownNode(
            kind: mdkText,
            text: curr.token,
            line: curr.line
          ))
        of mtkEmphasis:
          var emphChildren: seq[MarkdownNode] = @[]
          let emphLine = curr.line
          curr = lex.nextToken()
          while curr.kind != mtkEmphasis and curr.kind != mtkStrong and curr.kind != mtkEOF:
            if curr.kind == mtkText:
              emphChildren.add(MarkdownNode(
                kind: mdkText,
                text: curr.token,
                line: curr.line
              ))
            curr = lex.nextToken()
          strongChildren.add(MarkdownNode(
            kind: mdkEmphasis,
            children: MarkdownNodeList(items: emphChildren),
            line: emphLine
          ))
        else:
          strongChildren.add(MarkdownNode(
            kind: mdkText,
            text: curr.token,
            line: curr.line
          ))
        curr = lex.nextToken()
      node = MarkdownNode(
        kind: mdkStrong,
        children: MarkdownNodeList(items: strongChildren),
        line: strongLine
      )
      if curr.kind == mtkStrong:
        curr = lex.nextToken()
      else: discard # todo handle unclosed strong
    else:
      node = MarkdownNode(
        kind: mdkText,
        text: curr.token,
        line: curr.line
      )
      curr = lex.nextToken()
    
    # add the parsed node to result
    if node != nil: result.add(node)

proc parseListItem(md: var Markdown): MarkdownNode =
  # Parse a single list item, handling nested lists recursively
  if md.parser.curr.kind == mtkListItemCheckbox:
    # Delegate to checkbox parser
    return md.parseCheckboxItem()
  let itemText = md.parser.curr.token.strip()
  let indentLevel = 0
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
  # Check for nested lists
  while md.parser.curr.kind in {mtkListItem, mtkListItemCheckbox, mtkOListItem}:
    let nextIndent = 0
    let nextOrdered = md.parser.curr.kind == mtkOListItem
    if nextIndent > indentLevel:
      # Nested list: parse all at this deeper indent
      var nestedList = MarkdownNode(
        kind: mdkList,
        listOrdered: nextOrdered,
        children: MarkdownNodeList(items: @[]),
        line: md.parser.curr.line
      )
      while md.parser.curr.kind in {mtkListItem,
            mtkListItemCheckbox, mtkOListItem} and nextIndent == 0:
        let nestedItem = md.parseListItem()
        nestedList.children.items.add(nestedItem)
      result.children.items.add(nestedList)
    else: break

proc parseList(md: var Markdown): MarkdownNode =
  # Parse a sequence of list items into a single list node
  let startIndent = 0
  let isOrdered = md.parser.curr.kind == mtkOListItem
  result = MarkdownNode(
    kind: mdkList,
    listOrdered: isOrdered,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line
  )
  while md.parser.curr.kind in {mtkListItem, mtkListItemCheckbox, mtkOListItem} and startIndent == 0:
    # If the list type changes, break and let the main parser handle the new list
    if (md.parser.curr.kind == mtkOListItem) != isOrdered: break
    let itemNode = md.parseListItem()
    result.children.items.add(itemNode)

proc parseBlockquote(md: var Markdown): MarkdownNode =
  ## Parse one or more consecutive blockquote tokens into a blockquote node
  let startIndent = 0
  result = MarkdownNode(
    kind: mdkBlockquote,
    children: MarkdownNodeList(items: @[]),
    line: md.parser.curr.line
  )
  while md.parser.curr.kind == mtkBlockquote and startIndent == 0:
    let quoteText = md.parser.curr.token.strip()
    # Parse inline content of the blockquote
    for n in md.parseInline(quoteText):
      result.children.items.add(n)
    md.advance()
    # Handle nested blockquotes ("> > ...")
    if md.parser.curr.kind == mtkBlockquote and 0 > startIndent:
      let nested = md.parseBlockquote()
      result.children.items.add(nested)

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

let defaultOptions = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
    tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagMark, tagSmall, tagSub, tagSup
  ],
  allowTagsByType: none(TagType),
  allowInlineStyle: false,
  allowHtmlAttributes: false,
  enableAnchors: true
)

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
      let tagType = htmlparser.htmlTag(tag)
      if md.opts.allowed.len > 0:
        if not md.opts.allowed.contains(tagType):
          # TODO handle disallowed tags (e.g., escape or ignore)
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
        html: curr.token,
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
    # YAML Front Matter
    #
    of mtkDocument:
      try:
        # Parse YAML front matter
        # TODO test YAML parsing (https://github.com/openpeeps/nyml)
        md.headerYaml = fromYaml(curr.token, JsonNode)
      except YAMLException as e:
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

proc newMarkdown*(content: sink string, opts: MarkdownOptions = defaultOptions): Markdown =
  ## Create a new Markdown instance
  var md = Markdown(
    parser: MarkdownParser(lexer: initLexer(content)),
    opts: opts,
    selectors: newOrderedTable[string, string](),
    selectorCounter: newCountTable[string]()
  )
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

proc toJson*(md: Markdown): string =
  ## Convert the parsed Markdown AST to JSON
  jsony.toJson(md.ast)

proc getSelectors*(md: Markdown): OrderedTableRef[string, string] =
  ## Get the headline selectors (anchors) from the parsed Markdown
  md.selectors

proc hasSelectors*(md: Markdown): bool =
  ## Check if there are any headline selectors (anchors) in the parsed Markdown
  md.selectors != nil and md.selectors.len > 0

proc getHeader*(md: Markdown): JsonNode =
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
# Convert parsed Markdown to HTML
#
import std/htmlgen

proc renderNode(md: var Markdown, node: MarkdownNode): string =
  ## Render a single MarkdownNode to HTML. This proc is called recursively for child nodes.
  case node.kind
  of mdkText:
    result = node.text
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
    result = img(src=node.imageSrc, alt=node.imageAlt, title=node.imageTitle)
  of mdkList:
    var listItems = ""
    for item in node.children.items:
      listItems.add(md.renderNode(item))
    if node.listOrdered:
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
      else: # first occurrence
        md.selectorCounter[anchor] = 1
        md.selectors[anchor] = title
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
    # Code block with optional language class
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
