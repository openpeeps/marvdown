# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/bro

import pkg/toktok except NewLines
import std/[os, tables, strutils, htmlgen]

when not defined release:
  import std/[jsonutils, json]

registerTokens defaultSettings:
  dot = '.'
  hyphen = '-'
  # code = '`' .. '`'
  note = '^'
  lp = '('
  rp = ')'
  lb = '['
  rb = ']'
  lc = '{'
  rc = '}'
  pipe = '|'
  # strike = "~~" .. "~~"
  # highlight = "==" .. "=="
  h1 = '#':
    h2 = '#'
    h3 = "##"
    h4 = "###"
    h5 = "####"
    h6 = "#####"
  # bold = "**" .. "**"
  # italic = '*' .. '*'
  # italic2 = '_' .. '_'
  paragraph

type
  NodeType* = enum
    ntText
    ntBold
    ntHeading
    ntHtml
    ntLink
    ntItalic
    ntImage
    ntOl
    ntParagraph
    ntUl

  Node {.acyclic.} = ref object
    case nt: NodeType
    of ntHeading:
      hlvl: TokenKind # from tkH1 - tkH6
      hInner: seq[Node]
    of ntLink:
      link: string
      linkAttrs: seq[string]
      linkInner: Node
    of ntImage:
      img: string
      imgAttrs: seq[string]
    of ntUl, ntOl:
      list: seq[Node]
    of ntText:
      text: string
    else: discard
    # innerNodes: seq[Node]

  Markdown* = object
    source: string
    nodes: seq[Node]

  Parser* = object
    lex: Lexer
    md: Markdown
    prev, curr, next: TokenTuple
    hasErrors: bool
    nl: string

  PrefixFunction = proc(p: var Parser): Node

var nl = "\n"

#
# AST nodes
#
proc newHeading*(lvl: TokenKind): Node =
  ## Create a new heading node, `h1, `h2`, `h3`, so on...
  Node(nt: ntHeading, hlvl: lvl)

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

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

proc onSameLine(p: var Parser, lht: TokenTuple): bool =
  result = p.curr.line == lht.line and p.curr isnot tkEOF

#
# parse handlers
#
proc parseHeading(p: var Parser): Node =
  let tk = p.curr
  walk p
  result = newHeading(p.prev.kind)
  while p.onSameLine(tk):
    case p.curr.kind
    of tkIdentifier, tkH1, tkH2, tkH3, tkH4, tkH5, tkH6, tkUnknown:
      add result.hInner, Node(nt: ntText, text: indent(p.curr.value, p.curr.wsno))
    else: discard
    walk p

proc parsePrefix(p: var Parser): PrefixFunction =
  result =
    case p.curr.kind
    of tkH1, tkH2, tkH3, tkH4, tkH5, tkH6:
      parseHeading
    else: nil

proc newMarkdown*(src: string, minify = true): Markdown =
  ## Create a new `Markdown` document from `src`
  var p = Parser(lex: Lexer.init(src.readFile))
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  if minify: nl = ""
  while p.curr isnot tkEOF:
    if p.hasErrors: break # catch the wet bandits!
    let callPrefixFn = p.parsePrefix()
    if likely(callPrefixFn != nil):
      let node = callPrefixFn(p)
      if likely(node != nil):
        p.md.nodes.add(node)
  result = p.md

proc toHtml*(md: Markdown): string =
  ## Converts `Markdown` document to HTML
  let len = md.nodes.len - 1
  for n in 0 .. md.nodes.high:
    var el: string
    case md.nodes[n].nt
    of ntHeading:
      for inner in md.nodes[n].hInner:
        case inner.nt
          of ntText:
            add el, inner.text
          else: discard
      add result,
        case md.nodes[n].hlvl:
          of tkH1: h1(el.strip)
          of tkH2: h2(el.strip)
          of tkH3: h3(el.strip)
          of tkH4: h4(el.strip)
          of tkH5: h5(el.strip)
          else: h6(el.strip)
    else: discard
    if n < len: add result, nl


proc `$`*(md: Markdown): string =
  # An alias of `toHtml`
  toHtml(md)

when isMainModule:
  var md = newMarkdown("./sample.md", false)
  echo md.toHtml
  # var marv = Marvdown.init(getCurrentDir() & "/sample.md", engine = HTML)
  # var p = marv.parse()