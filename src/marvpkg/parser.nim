# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown
import pkg/toktok
import std/[os, tables, uri, htmlgen, unidecode, json]

# from htmlparser import HtmlTag, BlockTags, InlineTags, SingleTags
import htmlparser {.all.}

when not defined release:
  import std/[jsonutils]

const safe = {'<': "&lt;", '>': "&gt;"}.toTable()

#
# tokenizer
#
handlers:
  proc ltgt(lex: var Lexer, kind: TokenKind) =
    lexReady lex
    add lex.token, safe[lex.buf[lex.bufpos]]
    inc lex.bufpos
    lex.kind = kind

const settings =
  Settings(
    tkPrefix: "tk",
    keepChar: true,
    keepUnknown: true,
    tkModifier: defaultTokenModifier,      
    enableCustomIdent: false,
  )

registerTokens settings:
  dot = '.'
  # code = '`' .. '`'
  note = '^'
  lp = '('
  rp = ')'
  lb = '['
  rb = ']'
  lc = '{'
  rc = '}'
  lt = tokenize(ltgt, '<')
  gt = tokenize(ltgt, '>')
  eq = '='
  pipe = '|'
  ul = '-'    # unordered list
  ulp = '+'   # alt prefix for ul
  ulm = '*':  # alt prefix for ul
    bold = '*'
  ol          # ordered list prefixed with numbers
  tick = '`':
    blockCode = "``"
  italic
  `div` = '/'
  backslash = '\\'
  excl = '!'
  paragraph
  h1 = '#': # todo toktok enable `keepChar` for variants
    h2 = '#'
    h3 = "##"
    h4 = "###"
    h5 = "####"
    h6 = "#####"

type
  NodeType* = enum
    ntText
    ntInner
    ntBold = "b"
    ntBr = "br"
    ntBlockQuote = "blockquote"
    ntHeading = "h"
    ntHr = "hr"
    ntHtml
    ntLink
    ntItalic = "em"
    ntOl = "ol"
    ntParagraph = "p"
    ntUl
    ntTag # named tags
    ntCode
    ntBlockCode

  Node {.acyclic.} = ref object
    case nt: NodeType
    of ntHeading:
      hlvl: TokenKind # from tkH1 - tkH6
      headingNodes: seq[Node]
    of ntLink:
      link: Uri
      linkTitle: string
      linkNodes: seq[Node]
      isImage: bool
    of ntUl, ntOl:
      list: seq[Node]
    of ntText, ntCode:
      text: string
    of ntInner:
      inner: seq[Node]
    of ntParagraph:
      pNodes: seq[Node]
    of ntBold, ntItalic, ntBlockQuote:
      inlineNodes: seq[Node]
    of ntTag:
      tagName: string
      tagInlineNodes: seq[Node]
      tagAttrs: seq[string]
    of ntBlockCode:
      blockCode: seq[string] # a seq of lines
    else: discard
    wsno: int

  Markdown* = object
    source: string
    nodes: seq[Node]
    opts: MarkdownOptions
    selectors: TableRef[string, Node]

  TagType* = enum
    tagNone
    tagAll
    tagInline
    tagBlock
    tagSingle

  MarkdownOptions* = object
    allowed*: seq[HtmlTag]
      ## Allowed HTML tag names. See `defaultMarkdownOptions`
    allowTagsByType*: TagType
      ## Allow HTML tags by their types. Default `tagNone`
      ## This option is not used by default, instead, just a little
      ## list of `HtmlTag`. See `allowed`
    allowInlineStyle*: bool
      ## Allow CSS styling using `style` tag (disabled by default)
    allowHtmlAttributes*: bool
      ## Allow using html attributes, `width`, `title` and so on.
      ## For allowing use of `style` attribute, enable `allowInlineStyle`.
    useAnchors*: bool
      ## Enable anchor generation in title blocks (enabled by default)

  Parser* = object
    lex: Lexer
    md: Markdown
    prev, curr, next: TokenTuple
    errors: tuple[status: bool, msg: string, line, col: int]

  PrefixFunction = proc(p: var Parser): Node
  MarkdownException* = object of CatchableError

var nl = "\n"
let
  defaultMarkdownOptions* =
    MarkdownOptions(
      allowed: @[
        tagEm, tagI, tagB, tagU, tagStrong, tagBlockquote,
        tagDiv, tagKbd, tagSamp, tagSub, tagSup,
        tagIns, tagDel, tagVar, tagQ, tagDl, tagDt, tagDd,
        tagTable, tagThead, tagTfoot, tagTr, tagTd,
        tagSpan, tagCite, tagBr, tagCode, tagPre
      ],
      # todo add support for tagDetails, tagSummary (only in devel)
      # https://github.com/nim-lang/Nim/blob/devel/lib/pure/htmlparser.nim
      useAnchors: true
    )

# fwd declaration
proc getRootPrefix(p: var Parser): Node
proc getPrefix(p: var Parser): Node

#
# AST nodes
#
proc newHeading*(lvl: TokenKind): Node =
  ## Create a new heading node, `h1, `h2`, `h3`, so on...
  Node(nt: ntHeading, hlvl: lvl)

proc newParagraph*(): Node =
  ## Create a new `p` node
  Node(nt: ntParagraph)

proc newUl*(): Node =
  ## Create a new `ul` node
  Node(nt: ntUl)

proc newOl*(): Node =
  ## Create a new `ul` node
  Node(nt: ntOl)

#
# parse utils
#
when not defined release:
  proc `$`(node: Node): string = pretty(node.toJson(), 2)
  # proc `$`(md: Markdown): string = pretty(md.toJson(), 2)

proc walk(p: var Parser, offset = 1) =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()

template error(p: var Parser, msg: string, tk: TokenTuple, args: openarray[string] = []) =
  if args.len == 0:
    p.errors = (true, msg, tk.line, tk.col)
  else:
    p.errors = (true, msg % args, tk.line, tk.col)
  return nil

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

proc isSameLine(p: var Parser, left: TokenTuple): bool =
  result = p.curr.line == left.line and p.curr isnot tkEOF

proc isSecondLine(p: var Parser, left: TokenTuple): bool =
  result = (p.curr.line - left.line == 1) and p.curr isnot tkEOF

proc isAllowed(p: var Parser, tk: TokenTuple): bool =
  if p.md.opts.allowed.len > 0:
    return toHtmlTag(tk.value) in p.md.opts.allowed
  result = true # warning, this allows use of any tag

proc slugify(input: string, lowercase = true, sep = "-"): string =
  # Convert input string to a slug
  let s = unidecode(input)
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of Whitespace:
      if result[^1] != '-':
        result.add(sep)
    of Letters:
      result.add if lowercase: c.toLowerAscii else: c
    of Digits:
      result.add c
    else:
      discard

proc stackSelector(md: Markdown, prefix, name: string, node: Node): string =
  result = slugify(name)
  if unlikely(md.selectors.hasKey(prefix & result)):
    add result, "-" & $(md.selectors.len + 1)
  md.selectors[prefix & result] = node

#
# parse handlers
#
proc parseInline(p: var Parser, tk: TokenTuple, parentNodes: var seq[Node]) =
  while p.isSameLine(tk):
    add parentNodes, p.getPrefix()

proc parseSecondLine(p: var Parser, tk: TokenTuple, parentNodes: var seq[Node]) =
  while p.isSecondLine(tk):
    add parentNodes, p.getPrefix()

proc parseInline(p: var Parser, tk: TokenTuple, parentNodes: var seq[Node], xKind: TokenKind) =
  while p.isSameLine(tk) and p.curr isnot xKind:
    add parentNodes, p.getPrefix()
  if p.curr is xKind:
    walk p

proc parseHeading(p: var Parser): Node =
  # parse headings `h1`..`h6`
  let tk = p.curr
  walk p
  result = newHeading(tk.kind)
  p.parseInline(tk, result.headingNodes)

proc parseParagraph(p: var Parser): Node =
  # parse `paragraph` tags
  result = Node(nt: ntParagraph)
  let tk = p.curr
  var innerNode = Node(nt: ntInner)
  p.parseInline(tk, innerNode.inner)
  if p.isSecondLine(tk) and p.curr notin {tkUl, tkUlp, tkUlm}:
    if p.curr.wsno == 0:
      inc p.curr.wsno
    elif p.curr.wsno >= 2: # insert a break tag <br>
      add innerNode.inner, Node(nt: ntBr)
      dec p.curr.wsno, p.curr.wsno # wsno not needed 
    p.parseSecondLine(tk, innerNode.inner)
  add result.pNodes, innerNode

proc parseBlockquote(p: var Parser): Node =
  # parse `blockquote` tags 
  let tk = p.curr
  result = Node(nt: ntBlockQuote)
  walk p
  p.parseInline(tk, result.inlineNodes)

proc parseList(p: var Parser, tk: TokenTuple, innerNode: Node) =
  # parse (un)ordered lists
  while p.isSameLine(tk):
    let node = p.getPrefix()
    add innerNode.inner, node

proc parseUl(p: var Parser): Node =
  # parse unordered lists
  result = newUl()
  while p.curr is tkUl:
    walk p # `-`, `*`, `+`
    var tk = p.prev
    let innerNode = Node(nt: ntInner)
    p.parseList(tk, innerNode)
    add result.list, innerNode

proc parseOl(p: var Parser): Node =
  # parse ordered lists
  result = newOl()
  while (p.curr is tkInteger and p.next is tkDot) and p.next.wsno == 0:
    walk p # tkInteger
    var tk = p.prev
    walk p # tkDot
    let innerNode = Node(nt: ntInner)
    p.parseList(tk, innerNode)
    add result.list, innerNode

proc parseInnerTag(p: var Parser, parentNode: Node, tag: TokenTuple) =
  walk p # tkGT
  while p.curr isnot tkLT and p.next.kind != tkDiv:
    # if p.curr is tkEOF:
      # p.error "EOF reached before closing HTML tag", p.curr
    let node = p.getPrefix()
    add parentNode.tagInlineNodes, node
  walk p, 2 # </
  if p.curr.value == tag.value:
    if p.next.kind == tkGT:
      walk p, 2
    # else: p.error "Missing `>` for closing HTML tag", p.curr
  # else: p.error "Invalid enclosing tag, expects `</$1>`", p.curr, [$result.nt]

proc parseTag(p: var Parser): Node =
  # parse HTML tags,
  # `<b>`, `<em>`, `<strong>`, `<blockquote>`, and so on...
  let tag = p.next
  result = Node(nt: ntTag, tagName: tag.value)
  walk p, 2
  if likely(p.curr is tkGT):
    p.parseInnerTag(result, tag)
  elif p.md.opts.allowHtmlAttributes:
    while p.curr isnot tkGT:
      let attrName = p.curr
      var attrValue: string
      if p.next is tkEQ:
        walk p, 2
      if p.curr is tkString:
        attrValue = p.curr.value
        walk p
      else: walk p # could be an attr without values
      if likely(attrValue.len != 0):
        add result.tagAttrs, attrName.value & "=" & "\"" & attrValue & "\""
      else:
        add result.tagAttrs, attrName.value
    if likely(p.curr is tkGT):
      p.parseInnerTag(result, tag)

proc parseText(p: var Parser): Node =
  # Parse plain text
  result = Node(nt: ntText, text: p.curr.value, wsno: p.curr.wsno)
  walk p

proc parseInlineCode(p: var Parser): Node =
  # Parse inline `code` elements
  let tk = p.curr # tkTick
  result = Node(nt: ntCode, wsno: p.curr.wsno)
  walk p
  while p.isSameLine(tk) and p.curr isnot tk.kind:
    add result.text, indent(p.curr.value, p.curr.wsno)
    walk p
  if p.curr is tk.kind:
    walk p

proc parseBlockCode(p: var Parser): Node =
  # Parse a block code `<pre>`
  let tk = p.curr # tkBlockCode
  result = Node(nt: ntBlockCode)
  walk p
  var lines: string
  while p.curr isnot tk.kind and p.curr.pos == tk.pos:
    var line: string
    var lineno = p.curr.line
    while true:
      if p.curr is tkEOF: break
      elif p.curr is tk.kind and p.curr.pos == tk.pos:
        add lines, line
        break
      if p.curr.line == lineno:
        add line, indent(p.curr.value, p.curr.wsno)
        walk p
      else:
        add lines, line & "\n"
        setLen(line, 0)
        lineno = p.curr.line
        add line, indent(p.curr.value, p.curr.wsno)
        walk p
    add result.blockCode, lines
  if p.curr is tk.kind:
    walk p

proc parseMedia(p: var Parser, isImage: bool): Node =
  # Parse links `[Label](https://example.com "Example")`
  # and images `![Alt text](https://example.com/img.jpg "Some image")`
  let tk = p.curr
  var innerNodes: seq[Node]
  walk p
  while p.curr.line == tk.line and p.curr isnot tkRB:
    if p.curr is tkEOF:
      return Node(nt: ntText, text: "!")
    let node = p.getPrefix()
    if likely(node != nil):
      add innerNodes, node
  if p.curr isnot tkRB:
    innerNodes.insert(Node(nt: ntText, text: "!"), 0)
    return Node(nt: ntInner, inner: innerNodes)
  walk p # ]
  if p.curr is tkLP:
    walk p
    result = Node(nt: ntLink)
    var address: string
    # parse link address
    while p.curr notin {tkRP, tkString}:
      if p.curr is tkEOF:
        p.error("EOF reached before closing tag", p.curr)
      add address, p.curr.value
      walk p

    # parse link title, if available
    if p.curr is tkString:
      add result.linkTitle, p.curr.value
      walk p
    result.link = parseUri(address)
    result.linkNodes = innerNodes
    result.wsno = tk.wsno
    result.isImage = isImage
    walk p # )
  else:
    result = Node(nt: ntText)

proc parseLink(p: var Parser): Node =
  p.parseMedia(false)

proc parseImage(p: var Parser): Node =
  if p.next.kind == tkLB:
    walk p # tkExcl
  else:
    walk p # tkExcl
    return Node(nt: ntText, text: "!")
  p.parseMedia(true)

proc parseBold(p: var Parser): Node =
  let tk = p.curr
  walk p
  result = Node(nt: ntBold, wsno: tk.wsno)
  p.parseInline(tk, result.inlineNodes, tk.kind)

proc parseItalic(p: var Parser): Node =
  let tk = p.curr
  walk p
  result = Node(nt: ntItalic, wsno: tk.wsno)
  p.parseInline(tk, result.inlineNodes, tk.kind)

proc getRootPrefix(p: var Parser): Node =
  let callPrefixFn = 
    case p.curr.kind
    of tkH1, tkH2, tkH3, tkH4, tkH5, tkH6: parseHeading
    of tkUl, tkUlp: parseUl
    of tkUlm:      
      if p.next.wsno == 0:
        parseItalic
      else: parseUl
    of tkInteger:
      if p.next is tkDot and p.next.wsno == 0:
        parseOl
      else:
        parseParagraph
    of tkLT:
      if p.isAllowed(p.next):
        parseTag
      else: parseParagraph
    of tkLB:    parseLink
    of tkBold:  parseBold
    of tkBlockCode: parseBlockCode
    of tkGT:    parseBlockquote
    of tkExcl:  parseImage
    else: parseParagraph
  
  let node = callPrefixFn(p)
  case node.nt
  of ntUl, ntOl, ntHeading, ntParagraph, ntBlockQuote, ntBlockCode:
    result = node
  else:
    result = Node(nt: ntParagraph, pNodes: @[node])

proc getPrefix(p: var Parser): Node =
  let callPrefixFn = 
    case p.curr.kind
    of tkLB:      parseLink
    of tkBold:    parseBold
    of tkUlm:     parseItalic
    of tkTick:    parseInlineCode
    else:         parseText
  callPrefixFn(p)

#
# Public API
#
proc newMarkdown*(content: string, minify = true, opts: MarkdownOptions = defaultMarkdownOptions): Markdown =
  ## Create a new `Markdown` document from `content`
  var p = Parser(lex: Lexer.init(content), md: Markdown(opts: opts))
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  p.md.selectors = newTable[string, Node]()
  if minify: nl = "" # remove `\n`
  while p.curr isnot tkEOF:
    if p.errors.status: break # catch the wet bandits!
    let node = p.getRootPrefix()
    p.md.nodes.add(node)
  if p.errors.status:
    let meta = "[" & $(p.errors.line) & ":" & $(p.errors.col) & "]"
    raise newException(MarkdownException, meta & indent(p.errors.msg, 1))
  result = p.md
  reset(p)

include ./writers