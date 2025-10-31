# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[strutils, options]

type
  MarkdownTokenKind* = enum
    mtkText,           # Plain text
    mtkElement,        # Generic HTML element
    mtkCodeBlock,      # Code block (fenced or indented)
    mtkHeading,        # Heading (h1, h2, h3, etc.)
    mtkList,           # Ordered or unordered list
    mtkListItem,       # List item
    mtkOListItem,      # Ordered list item
    mtkBlockquote,     # Blockquote
    mtkHorizontalRule, # Horizontal rule (--- or ***)
    mtkLink,           # Hyperlink
    mtkImage,          # Image
    mtkEmphasis,       # Emphasized text (italic)
    mtkStrong,         # Strongly emphasized text (bold)
    mtkInlineCode,     # Inline code
    mtkLineBreak,      # Line break
    mtkHtml,           # Raw HTML content
    mtkTable,          # Table
    mtkParagraph,      # Paragraph
    mtkDocument,       # Root document node
    mtkUnknown         # Unknown or unsupported token
    mtkEOF             # End of file/input

  MarkdownTokenTuple* = tuple
    kind: MarkdownTokenKind
    token: string
    line: int
    col: int
    post: int
    wsno: int
    attrs: Option[seq[string]] # For future use, e.g., link title, image title, etc.

  MarkdownLexer* = object
    input*: string
    current*: char
    pos*, line*, col*: int
    strbuf*: string

#
# Markdown Lexer
#
proc initLexer*(input: sink string): MarkdownLexer =
  result.input = input
  result.pos = 0
  result.line = 1
  result.col = 1
  result.strbuf = ""
  if input.len > 0:
    result.current = input[0]
  else:
    result.current = '\0'

proc advance(lex: var MarkdownLexer) =
  if lex.pos < lex.input.len:
    if lex.current == '\n':
      inc lex.line
      lex.col = 0
    else:
      inc lex.col
    inc lex.pos
    if lex.pos < lex.input.len:
      lex.current = lex.input[lex.pos]
    else:
      lex.current = '\0'

proc peek(lex: MarkdownLexer, offset = 1): char =
  let idx = lex.pos + offset
  if idx < lex.input.len: lex.input[idx] else: '\0'

# For char-based tokens (no value allocation)
proc initToken(lex: var MarkdownLexer, kind: static MarkdownTokenKind, wsno: int): MarkdownTokenTuple =
  (kind, "", lex.line, lex.pos, lex.col, wsno, none(seq[string]))

# For tokens that need a value (identifiers, numbers, strings, etc)
proc initToken(lex: var MarkdownLexer, kind: MarkdownTokenKind, value: sink string, wsno: int): MarkdownTokenTuple =
  (kind, value, lex.line, lex.pos, lex.col, wsno, none(seq[string]))

proc newTokenTuple(lex: MarkdownLexer, kind: MarkdownTokenKind, token: string = "", wsno: int = 0, attrs: Option[seq[string]] = none(seq[string])): MarkdownTokenTuple =
  (kind, token, lex.line, lex.col - token.len, lex.pos, wsno, attrs)

proc nextToken*(lex: var MarkdownLexer): MarkdownTokenTuple =
  ## Lex the next token from the input
  var wsno = 0
  # Skip whitespace and newlines before token
  while true:
    while lex.current in {' ', '\t', '\r'}:
      inc wsno
      lex.advance()
    if lex.current == '\n':
      # inc lex.line
      lex.col = 0
      lex.advance()
      wsno = 0
      continue
    elif lex.current == '\r':
      if lex.peek() == '\n':
        lex.advance()
      inc lex.line
      lex.col = 0
      lex.advance()
      wsno = 0
      continue
    break
  # End of input
  if lex.current == '\0':
    return newTokenTuple(lex, mtkEOF, wsno=wsno)

  # let startCol = wsno # not needed anymore

  case lex.current
  of '#':
    # Headings (e.g., ## Heading 2)
    var level = 0
    while lex.current == '#':
      inc level
      lex.advance()
    if lex.current == ' ':
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      return newTokenTuple(lex, mtkHeading, lex.strbuf.strip(), wsno=wsno, attrs=some(@[$level]))
    else:
      return newTokenTuple(lex, mtkText, repeat('#', level), wsno=wsno)
  of '-', #['*',]# '_':
    # Horizontal rule or unordered list or emphasis/strong
    let ch = lex.current
    var count = 0
    while lex.current == ch:
      inc count
      lex.advance()
    if count >= 3 and (lex.current == '\n' or lex.current == '\0'):
      # it's a horizontal rule!
      return newTokenTuple(lex, mtkHorizontalRule, repeat(ch, count), wsno=wsno)
    elif (ch in {'-', '*', '+'}) and (lex.current == ' ' or lex.current == '\t'):
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      return newTokenTuple(lex, mtkListItem, lex.strbuf.strip(), wsno=wsno)
    elif ch in {'*', '_'}:
      # Emphasis or strong
      if lex.peek() == ch:
        lex.advance(); lex.advance() # skip both delimiters
        return newTokenTuple(lex, mtkStrong, wsno=wsno)
      else:
        return newTokenTuple(lex, mtkEmphasis, wsno=wsno)
    else:
      return newTokenTuple(lex, mtkText, repeat(ch, count), wsno=wsno)
  of '>':
    # Blockquote
    lex.advance()
    if lex.current == ' ':
      lex.advance()
    lex.strbuf.setLen(0)
    while lex.current notin {'\n', '\r', '\0'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    return newTokenTuple(lex, mtkBlockquote, lex.strbuf.strip(), wsno=wsno)
  of '0'..'9':
    # Ordered list item
    lex.strbuf.setLen(0)
    while lex.current in {'0'..'9'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '.' and (lex.peek() == ' ' or lex.peek() == '\t'):
      lex.advance()
      if lex.current == ' ' or lex.current == '\t':
        lex.advance()
      let num = lex.strbuf
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      return newTokenTuple(lex, mtkOListItem, lex.strbuf.strip(), wsno=wsno)
    else:
      return newTokenTuple(lex, mtkText, lex.strbuf, wsno=wsno)
  of '`', '~':
    # Fenced code block (``` or ~~~)
    if lex.peek() == lex.current and lex.peek(2) == lex.current:
      let fence = lex.current
      lex.advance(); lex.advance(); lex.advance()
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      let lang = lex.strbuf
      if lex.current in {'\n', '\r'}:
        lex.advance()
      lex.strbuf.setLen(0)
      while not (lex.current == fence and lex.peek() == fence and lex.peek(2) == fence):
        if lex.current == '\0':
          break
        lex.strbuf.add(lex.current)
        lex.advance()
      if lex.current == fence:
        lex.advance(); lex.advance(); lex.advance()
      if lex.current in {'\n', '\r'}:
        lex.advance()
      return newTokenTuple(lex, mtkCodeBlock, lex.strbuf, wsno=wsno, attrs=some(@[lang]))
    elif lex.current == '`':
      # Inline code
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '`' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      if lex.current == '`':
        lex.advance()
      return newTokenTuple(lex, mtkInlineCode, lex.strbuf, wsno=wsno)
    else:
      # treat as text
      lex.strbuf.setLen(0)
      lex.strbuf.add(lex.current)
      lex.advance()
      return newTokenTuple(lex, mtkText, lex.strbuf, wsno=wsno)
  of '!':
    # Image
    if lex.peek() == '[':
      lex.advance(); lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != ']' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      let alt = lex.strbuf
      if lex.current == ']':
        lex.advance()
        if lex.current == '(':
          lex.advance()
          lex.strbuf.setLen(0)
          var src = ""
          var title = ""
          var inTitle = false
          while lex.current != ')' and lex.current != '\0':
            if lex.current == '"' and not inTitle:
              inTitle = true
              lex.advance()
              continue
            if inTitle:
              if lex.current == '"':
                inTitle = false
                lex.advance()
                continue
              title.add(lex.current)
            else:
              if lex.current == ' ':
                lex.advance()
                continue
              src.add(lex.current)
            lex.advance()
          if lex.current == ')':
            lex.advance()
          if title.len > 0:
            return newTokenTuple(lex, mtkImage, wsno=wsno, attrs=some(@[alt, src, title]))
          else:
            return newTokenTuple(lex, mtkImage, wsno=wsno, attrs=some(@[alt, src]))
    else:
      var text = "!"
      lex.advance()
      return newTokenTuple(lex, mtkText, text, wsno=wsno)
  of '[':
    # Link
    lex.advance()
    lex.strbuf.setLen(0)
    while lex.current != ']' and lex.current != '\0':
      lex.strbuf.add(lex.current)
      lex.advance()
    let text = lex.strbuf
    if lex.current == ']':
      lex.advance()
      if lex.current == '(':
        lex.advance()
        lex.strbuf.setLen(0)
        while lex.current != ')' and lex.current != '\0':
          lex.strbuf.add(lex.current)
          lex.advance()
        let href = lex.strbuf
        if lex.current == ')':
          lex.advance()
        return newTokenTuple(lex, mtkLink, wsno=wsno, attrs=some(@[text, href]))
    return newTokenTuple(lex, mtkText, text, wsno=wsno)
  of '*':
    # Emphasis or strong
    if lex.peek() == '*':
      lex.advance(); lex.advance()
      return newTokenTuple(lex, mtkStrong, wsno=wsno)
    else:
      return newTokenTuple(lex, mtkEmphasis, wsno=wsno)
  of ' ':
    # Line break (two or more spaces at end of line)
    if lex.peek() == ' ' and (lex.peek(2) == '\n' or lex.peek(2) == '\r'):
      lex.advance(); lex.advance();
      if lex.current in {'\n', '\r'}:
        lex.advance()
      return newTokenTuple(lex, mtkLineBreak, wsno=wsno)
    else:
      var text = " "
      lex.advance()
      return newTokenTuple(lex, mtkText, text, wsno=wsno)
  of '<':
    # Raw HTML
    lex.strbuf.setLen(0)
    var tag: string
    var stopTag = false
    while true:
      case lex.current
      of '>', '\0': break
      of ' ':
        stopTag = true
        lex.strbuf.add(lex.current)
      of 'a'..'z', 'A'..'Z', '0'..'9', '_', '-':
        lex.strbuf.add(lex.current)
        if not stopTag: tag.add(lex.current)
      else:
        lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '>':
      lex.strbuf.add(lex.current)
      lex.advance()
    return newTokenTuple(lex, mtkHtml, lex.strbuf, wsno=wsno, attrs=some(@[tag]))
  of '|':
    # Table row
    lex.strbuf.setLen(0)
    while lex.current notin {'\n', '\r', '\0'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    return newTokenTuple(lex, mtkTable, lex.strbuf, wsno=wsno)
  else:
    # Paragraph or plain text
    lex.strbuf.setLen(0)
    # Stop at markdown delimiters
    while lex.current notin {'\n', '\r', '\0', '*', '_', '[', ']', '!', '`', '<'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.strbuf.len > 0:
      return newTokenTuple(lex, mtkText, lex.strbuf, wsno=wsno)
    return newTokenTuple(lex, mtkUnknown, wsno=wsno)