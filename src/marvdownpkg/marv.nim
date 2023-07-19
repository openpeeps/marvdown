# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown
import pkg/toktok
import std/[os, tables, critbits, uri, htmlgen, unidecode, json]

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
  pipe = '|'
  ul = '-' # unordered list
  ulp = '+' # alt prefix for ul
  ulm = '*' # alt prefix for ul
  ol # ordered list prefixed with numbers
  backSlash = '/'
  excl = '!'
  # strike = "~~" .. "~~"
  # highlight = "==" .. "=="
  paragraph
  h1 = '#': # todo toktok enable `keepChar` for variants
    h2 = '#'
    h3 = "##"
    h4 = "###"
    h5 = "####"
    h6 = "#####"
  # bold = "**" .. "**"
  # italic = '*' .. '*'s
  # italic2 = '_' .. '_'

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
    of ntText:
      text: string
    of ntInner:
      inner: seq[Node]
    of ntParagraph:
      pNodes: seq[Node]
    of ntBold, ntItalic, ntBlockQuote:
      inlineNodes: seq[Node]
    else: discard
    indent: int

  Markdown* = object
    source: string
    nodes: seq[Node]
    opts: MarkdownOptions
    when compileOption("app", "lib"):
      idSelectors: TableRef[string, Node]

  MarkdownOptions* = object
    allowed*: seq[string] # a list of HTML tag names
    useAnchors*: bool     # enable/disable anchor in title blocks

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
      allowed: @["em", "i", "b", "u", "bold", "blockquote"],
      useAnchors: true
    )
  inlineNodes = {
    "b": Node(nt: ntBold),
    "i": Node(nt: ntItalic),
    "bold": Node(nt: ntBold),
    "em": Node(nt: ntItalic),
  }.toTable

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
  result = tk.value in p.md.opts.allowed

template stackSelectorId(id: string, node: Node) =
  when compileOption("app", "lib"):
    md.idSelectors[slug] = md.nodes[n]

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

#
# parse handlers
#
proc parseInline(p: var Parser, tk: TokenTuple, parentNodes: var seq[Node]) =
  while p.isSameLine(tk):
    let node = p.getPrefix()
    if likely(node != nil):
      add parentNodes, node

proc parseHeading(p: var Parser): Node =
  # Parse headings
  let tk = p.curr
  walk p
  result = newHeading(tk.kind)
  p.parseInline(tk, result.headingNodes)

proc parseParagraph(p: var Parser): Node =
  # Pars paragraphs
  result = Node(nt: ntParagraph)
  let tk = p.curr
  var innerNode = Node(nt: ntInner)
  p.parseInline(tk, innerNode.inner)
  if p.isSecondLine(tk) and p.curr notin {tkUl, tkUlp, tkUlm}:
    if p.curr.wsno == 0:
      inc p.curr.wsno
    elif p.curr.wsno >= 2:
      # add a hard line break
      add innerNode.inner, Node(nt: ntBr)
      dec p.curr.wsno, p.curr.wsno # wsno not needed 
    p.parseInline(tk, innerNode.inner)
  add result.pNodes, innerNode

proc parseBlockquote(p: var Parser): Node =
  let tk = p.curr
  result = Node(nt: ntBlockQuote)
  walk p
  while p.isSameLine(tk):
    let node = p.getPrefix()
    if likely(node != nil):
      add result.inlineNodes, node
    else: result = nil

proc parseList(p: var Parser, tk: TokenTuple, innerNode: Node) =
  while p.isSameLine(tk):
    let node = p.getPrefix()
    if likely(node != nil):
      add innerNode.inner, node

proc parseUl(p: var Parser): Node =
  # Parse unordered lists
  result = newUl()
  while p.curr is tkUl:
    walk p # `-`, `*`, `+`
    var tk = p.prev
    let innerNode = Node(nt: ntInner)
    p.parseList(tk, innerNode)
    add result.list, innerNode

proc parseOl(p: var Parser): Node =
  # Parse ordered lists
  result = newOl()
  while (p.curr is tkInteger and p.next is tkDot) and p.next.wsno == 0:
    walk p # tkInteger
    var tk = p.prev
    walk p # tkDot
    let innerNode = Node(nt: ntInner)
    p.parseList(tk, innerNode)
    add result.list, innerNode

proc parseTag(p: var Parser): Node =
  # Parse allowed HTML tags, such as
  # `<b>`, `<em>`, `<strong>`, `<blockquote>`, and so on...
  let tag = p.next
  result = inlineNodes[tag.value]
  walk p, 2
  if p.curr is tkGT:
    walk p
    while p.curr isnot tkLT and p.next.kind != tkBackSlash:
      if p.curr is tkEOF:
        p.error "EOF reached before closing HTML tag", p.curr
      let node = p.getPrefix()
      if likely(node != nil):
        add result.inlineNodes, node
    walk p, 2 # </
    if p.curr.value == tag.value:
      if p.next.kind == tkGT:
        walk p, 2
      else: p.error "Missing `>` for closing HTML tag", p.curr
    else: p.error "Invalid enclosing tag, expects `</$1>`", p.curr, [$result.nt]

proc parseText(p: var Parser): Node =
  # Parse plain text
  result = Node(nt: ntText, text: indent(p.curr.value, p.curr.wsno))
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
    result.indent = tk.wsno
    result.isImage = isImage
    walk p # )
  else:
    result = Node(nt: ntText)

proc parseLink(p: var Parser): Node =
  p.parseMedia(false)

proc parseImage(p: var Parser): Node =
  if p.next.kind == tkLB:
    walk p # !
  else:
    walk p
    return Node(nt: ntText, text: "!")
  p.parseMedia(true)

proc getRootPrefix(p: var Parser): Node =
  let callPrefixFn = 
    case p.curr.kind
    of tkH1, tkH2, tkH3,
       tkH4, tkH5, tkH6:
      parseHeading
    of tkUl:
      parseUl
    of tkInteger:
      if p.next is tkDot and p.next.wsno == 0:
        parseOl
      else:
        parseParagraph
    of tkLT:
      if p.isAllowed(p.next):
        parseTag
      else: parseParagraph
    of tkLB:
      parseLink
    of tkGT:
      parseBlockquote
    of tkExcl:
      parseImage
    else: parseParagraph
  let node = callPrefixFn(p)
  case node.nt
  of ntUl, ntOl, ntHeading, ntParagraph:
    result = node
  else:
    result = Node(nt: ntParagraph, pNodes: @[node])

proc getPrefix(p: var Parser): Node =
  let callPrefixFn = 
    case p.curr.kind
    of tkLB:
      parseLink
    else:
      parseText
  callPrefixFn(p)

#
# Writers
#
proc writeInnerNode(node: Node): string # fwd declaration

proc writeInnerNodes(nodes: seq[Node]): string =
  for node in nodes:
    add result, node.writeInnerNode()

proc writeInnerNode(node: Node): string =
  case node.nt
  of ntLink:
    let label = writeInnerNodes(node.linkNodes)
    if unlikely(node.isImage):
      if node.linkTitle.len > 0:
        result = indent(img(src = $(node.link), alt=label, title=node.linkTitle), node.indent)
      else:
        result = indent(img(src = $(node.link), alt=label), node.indent)
    else:
      if node.linkTitle.len > 0:
        result = indent(a(href = $(node.link), title=node.linkTitle, label), node.indent)
      else:
        result = indent(a(href = $(node.link), label), node.indent)
  of ntText:
    result = node.text
  of ntInner:
    add result, writeInnerNodes(node.inner)
  of ntBr:
    result = br()
  else: discard

#
# Public API
#
proc newMarkdown*(content: string, minify = true, opts: MarkdownOptions = defaultMarkdownOptions): Markdown =
  ## Create a new `Markdown` document from `content`
  var p = Parser(lex: Lexer.init(content), md: Markdown(opts: opts))
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  when compileOption("app", "lib"):
    p.md.idSelectors = newTable[string, Node]()
    p.md.classSelectors = newTable[string, Node]()
  if minify: nl = "" # remove `\n`
  while p.curr isnot tkEOF:
    if p.errors.status: break # catch the wet bandits!
    let node = p.getRootPrefix()
    if likely(node != nil):
      p.md.nodes.add(node)
  if p.errors.status:
    let meta = "[" & $(p.errors.line) & ":" & $(p.errors.col) & "]"
    raise newException(MarkdownException, meta & p.errors.msg.indent(1))
  result = p.md
  nl = "\n" # revert `\n`
  reset(p)

proc toHtml*(md: Markdown): string =
  ## Converts `Markdown` document to HTML
  let len = md.nodes.len - 1
  for n in 0 .. md.nodes.high:
    var el: string
    let nt = md.nodes[n].nt
    case nt
    of ntParagraph:
      for pNode in md.nodes[n].pNodes:
        add result, p(writeInnerNode(pNode))
    of ntHeading:
      for inner in md.nodes[n].headingNodes:
        case inner.nt
          of ntText:
            add el, inner.text
          else: discard
      if md.opts.useAnchors:
        el = el.strip
        let slug = slugify(el)
        stackSelectorId(slug, md.nodes[n])
        el = a(id=slug, class="anchor", href="#" & slug) & el # todo `aria-hidden` is not recognized in htmlgen
      add result,
        case md.nodes[n].hlvl:
          of tkH1: h1(el)
          of tkH2: h2(el)
          of tkH3: h3(el)
          of tkH4: h4(el)
          of tkH5: h5(el)
          else: h6(el)
    of ntUl, ntOl:
      var lists: string
      for node in md.nodes[n].list:
        var el: string
        for innerNode in node.inner:
          add el, writeInnerNode(innerNode)
        add lists, li(el.strip) & nl
      if nt == ntUl:
        add result, ul(nl, lists)
      else:
        add result, ol(nl, lists)
    of ntBlockQuote:
      var el: string
      for node in md.nodes[n].inlineNodes:
        add el, writeInnerNode(node)
      add result, blockquote(el.strip)
    of ntBold:
      var content: string
      for inlineNode in md.nodes[n].inlineNodes:
        case inlineNode.nt
        of ntText:
          add content, inlineNode.text
        else: discard # todo
      add result, p(b(content))
    of ntItalic:
      var content: string
      for inlineNode in md.nodes[n].inlineNodes:
        case inlineNode.nt
        of ntText:
          add content, inlineNode.text
        else: discard # todo
      add result, p(em(content))
    of ntBr:
      add result, br()
    else: discard
    setLen(el, 0)
    if n < len: add result, nl

proc `$`*(md: Markdown): string = toHtml(md)

proc toJson*(md: Markdown): string =
  ## Parses `md` document and returns stringified `JSON`
  discard 

proc toJson*(md: Markdown, toJsonNode: bool): JsonNode =
  ## Parses `md` document and returns `JsonNode`
  discard

proc toPdf*(md: Markdown, output: string, style = "") =
  ## Compiles to `.pdf`. Optionally, you can provide some cool CSS to `style`
  discard 