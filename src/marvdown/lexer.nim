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
    mtkListItemCheckbox, # List item checkbox
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
    mtkFootnoteRef,    # Footnote reference
    mtkFootnoteDef,    # Footnote definition
    mtkDocument,       # Root document node
    mtkUnknown         # Unknown or unsupported token
    mtkEOF             # End of file/input

  MarkdownTokenTuple* = tuple
    kind: MarkdownTokenKind
    token: string
    line: int
    col: int
    post: int
    attrs: Option[seq[string]] # For future use, e.g., link title, image title, etc.

  MarkdownLexer* = object
    input*: string
    current*: char
    pos*, line*, col*: int
    strbuf*: string
    pendingTokens: seq[MarkdownTokenTuple] # Buffer for tokens split from text

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
    elif lex.current in {' ', '\t'}:
      inc lex.col
    elif lex.current == '\r':
      # Treat CR similarly to other non-leading whitespace; do not
      # increment wsno for it.
      inc lex.col
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
proc initToken(lex: var MarkdownLexer, kind: static MarkdownTokenKind): MarkdownTokenTuple =
  (kind, "", lex.line, lex.pos, lex.col, none(seq[string]))

# For tokens that need a value (identifiers, numbers, strings, etc)
proc initToken(lex: var MarkdownLexer, kind: MarkdownTokenKind,
                value: sink string): MarkdownTokenTuple =
  (kind, value, lex.line, lex.pos, lex.col, none(seq[string]))

proc newTokenTuple(lex: MarkdownLexer, kind: MarkdownTokenKind,
            token: string = "",
            attrs: Option[seq[string]] = none(seq[string])
        ): MarkdownTokenTuple =
  (kind, token, lex.line, lex.col - token.len, lex.pos, attrs)

proc handleAutoLink(lex: var MarkdownLexer): MarkdownTokenTuple =
  var tempStrBuf = ""
  let startPos = lex.pos
  while lex.current notin {' ', '\t', '\n', '\r', '\0'}:
    tempStrBuf.add(lex.current)
    lex.advance()
  return newTokenTuple(lex, mtkLink, attrs=some(@[tempStrBuf, tempStrBuf]))

const newSpace = " "
proc scanTextWithLinks(lex: var MarkdownLexer): seq[MarkdownTokenTuple] =
  var buf = ""
  while true:
    # Check for http(s):// at current position
    if lex.current == 'h' and lex.peek() == 't' and lex.peek(2) == 't' and lex.peek(3) == 'p':
      let isHttp = lex.peek(4) == ':' and lex.peek(5) == '/' and lex.peek(6) == '/'
      let isHttps = lex.peek(4) == 's' and lex.peek(5) == ':' and lex.peek(6) == '/' and lex.peek(7) == '/'
      if isHttp or isHttps:
        if buf.len > 0:
          result.add(newTokenTuple(lex, mtkText, buf))
          buf.setLen(0)
        result.add(lex.handleAutoLink())
        continue
    if lex.current in {'\n', '\r'}:
      # Check for two consecutive newlines (paragraph break)
      let nextChar = lex.peek()
      if (lex.current == '\n' and nextChar == '\n'):
        break # paragraph break
      elif (lex.current == '\r' and nextChar == '\r') or
         ((lex.current == '\n' or lex.current == '\r') and (nextChar == '\r' or nextChar == '\n')):
        lex.advance() # consume first newline
        lex.advance() # consume second newline
        break
      # Single newline: treat as space
      buf.add(' ')
      lex.advance()
      continue
    if lex.current in {'\0', '*', '_', '[', ']', '!', '`', '<'}:
      break
    buf.add(lex.current)
    lex.advance()
  if buf.len > 0:
    result.add(newTokenTuple(lex, mtkText, buf))

proc nextToken*(lex: var MarkdownLexer): MarkdownTokenTuple =
  ## Lex the next token from the input
  # Remove local wsno, use lex.wsno
  # Skip whitespace and newlines before token
  var newlineCount = 0
  while lex.current == '\n' or lex.current == '\r':
    # CRLF -> consume both as a single newline
    if lex.current == '\r' and lex.peek() == '\n':
      lex.advance() # consume '\r', now at '\n'
    # consume the newline character
    if lex.current == '\n' or lex.current == '\r':
      inc newlineCount
      lex.col = 0
      lex.advance()
      continue
    break

  if newlineCount >= 2:
    # adding a paragraph token for multiple newlines
    return newTokenTuple(lex, mtkParagraph)

  if lex.current == '\0':
    # End of input
    return newTokenTuple(lex, mtkEOF)

  # Return buffered tokens if present
  if lex.pendingTokens.len > 0:
    let tok = lex.pendingTokens[0]
    lex.pendingTokens = lex.pendingTokens[1..^1]
    return tok

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
      return newTokenTuple(lex, mtkHeading, lex.strbuf.strip(), attrs=some(@[$level]))
    else:
      return newTokenTuple(lex, mtkText, repeat('#', level))
  of '-', #['*',]# '_':
    # Horizontal rule or unordered list or emphasis/strong

    let ch = lex.current
    var count = 0
    while lex.current == ch:
      inc count
      lex.advance()
    
    if count >= 3 and (lex.current == '\n' or lex.current == '\0'):
      # Horizontal rule, or the begining of a YAML front matter
      if lex.line == 1:
        # YAML front matter detected
        lex.strbuf.setLen(0)
        while true:
          if lex.current == '\0':
            break
          if lex.current == '-' and lex.peek() == '-' and lex.peek(2) == '-':
            # End of front matter
            lex.advance(); lex.advance(); lex.advance()
            if lex.current in {'\n', '\r'}:
              lex.advance()
            break
          lex.strbuf.add(lex.current)
          lex.advance()
        let frontMatter = lex.strbuf.strip()
        return newTokenTuple(lex, mtkDocument, frontMatter)
      else:
        return newTokenTuple(lex, mtkHorizontalRule, repeat(ch, count))

    if (ch in {'-', '*', '+'}) and (lex.current == ' ' or lex.current == '\t'):
      # Unordered list item
      lex.advance()
      while lex.current == ' ' or lex.current == '\t':
        lex.advance()
      
      # Check for checkbox pattern
      while lex.current == ' ' or lex.current == '\t':
        lex.advance()

      if lex.current == '[' and (lex.peek() == 'x' or lex.peek() == ' '):
        lex.advance() # skip '['
        let cbChar = lex.current
        lex.advance() # skip 'x' or ' '
        if lex.current == ']':
          lex.advance()
          # Skip whitespace after checkbox
          while lex.current == ' ' or lex.current == '\t':
            lex.advance()
          # Read rest of line as item text
          lex.strbuf.setLen(0)
          while lex.current notin {'\n', '\r', '\0'}:
            lex.strbuf.add(lex.current)
            lex.advance()
          let checkState =
            if cbChar == 'x': "checked"
                        else: "unchecked"
          return newTokenTuple(lex, mtkListItemCheckbox,
                  lex.strbuf.strip(), attrs=some(@["checkbox", checkState]))
      
      # Otherwise, normal list item
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      return newTokenTuple(lex, mtkListItem, lex.strbuf.strip())
    
    if ch in {'*', '_'}:
      # Emphasis or strong
      if lex.peek() == ch:
        lex.advance(); lex.advance() # skip both delimiters
        return newTokenTuple(lex, mtkStrong)
      else:
        # lex.advance(); not needed, already advanced
        return newTokenTuple(lex, mtkEmphasis)
    else:
      return newTokenTuple(lex, mtkText, repeat(ch, count))
  of '>':
    # Blockquote
    lex.advance()
    if lex.current == ' ':
      lex.advance()
    lex.strbuf.setLen(0)
    while lex.current notin {'\n', '\r', '\0'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    return newTokenTuple(lex, mtkBlockquote, lex.strbuf.strip())
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
      return newTokenTuple(lex, mtkOListItem, lex.strbuf.strip())
    else:
      return newTokenTuple(lex, mtkText, lex.strbuf)
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
      return newTokenTuple(lex, mtkCodeBlock, lex.strbuf, attrs=some(@[lang]))
    elif lex.current == '`':
      # Inline code
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '`' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      if lex.current == '`':
        lex.advance()
      return newTokenTuple(lex, mtkInlineCode, lex.strbuf)
    else:
      # treat as text
      lex.strbuf.setLen(0)
      lex.strbuf.add(lex.current)
      lex.advance()
      return newTokenTuple(lex, mtkText, lex.strbuf)
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
            return newTokenTuple(lex, mtkImage, attrs=some(@[alt, src, title]))
          else:
            return newTokenTuple(lex, mtkImage, attrs=some(@[alt, src]))
    else:
      var text = "!"
      lex.advance()
      return newTokenTuple(lex, mtkText, text)
  of '[':
    # Link, Checkbox, or Footnote
    if lex.peek() == '^':
      # Footnote reference or definition
      lex.advance() # skip '['
      lex.advance() # skip '^'
      lex.strbuf.setLen(0)
      while lex.current != ']' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      let footId = lex.strbuf
      if lex.current == ']':
        lex.advance()
        if lex.current == ':' and (lex.peek() == ' ' or lex.peek() == '\t'):
          # Footnote definition: [^id]: text
          lex.advance() # skip ':'
          while lex.current == ' ' or lex.current == '\t':
            lex.advance()
          lex.strbuf.setLen(0)
          while lex.current notin {'\n', '\r', '\0'}:
            lex.strbuf.add(lex.current)
            lex.advance()
          return newTokenTuple(lex, mtkFootnoteDef,
                    lex.strbuf.strip(), attrs=some(@[footId]))
        else:
          # Footnote reference: [^id]
          return newTokenTuple(lex, mtkFootnoteRef, "", attrs=some(@[footId]))
    # Regular link or checkbox
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
        # Parse href
        while lex.current notin {' ', '\t', ')', '\n', '\r', '\0'}:
          lex.strbuf.add(lex.current)
          lex.advance()
        let href = lex.strbuf
        var title = ""
        # Parse optional title
        while lex.current == ' ' or lex.current == '\t':
          lex.advance()
        if lex.current == '"':
          lex.advance()
          var titleBuf = ""
          while lex.current != '"' and lex.current != '\0' and lex.current != ')':
            titleBuf.add(lex.current)
            lex.advance()
          title = titleBuf
          if lex.current == '"':
            lex.advance()
        # Skip whitespace before closing ')'
        while lex.current == ' ' or lex.current == '\t':
          lex.advance()
        if lex.current == ')':
          lex.advance()
        if title.len > 0:
          return newTokenTuple(lex, mtkLink, attrs=some(@[text, href, title]))
        else:
          return newTokenTuple(lex, mtkLink, attrs=some(@[text, href]))
      let checkState =
        if text == "x": "checked"
          else: "unchecked"
      return newTokenTuple(lex, mtkListItemCheckbox, attrs=some(@["checkbox", checkState]))
    return newTokenTuple(lex, mtkText, text)
  of '*':
    # Emphasis or strong
    if lex.peek() == '*':
      lex.advance(); lex.advance()
      return newTokenTuple(lex, mtkStrong)
    else:
      lex.advance();
      return newTokenTuple(lex, mtkEmphasis)
  of ' ':
    # Line break (two or more spaces at end of line)
    # Also accept tabs as whitespace that should be emitted as text tokens.
    if lex.peek() == ' ' and (lex.peek(2) == '\n' or lex.peek(2) == '\r'):
      lex.advance(); lex.advance();
      if lex.current in {'\n', '\r'}:
        lex.advance()
        return newTokenTuple(lex, mtkLineBreak)
    else:
      lex.advance()
      return newTokenTuple(lex, mtkText, newSpace)
  of '\t':
    # treat tabs as text tokens similar to spaces.
    var text = "\t"
    lex.advance()
    return newTokenTuple(lex, mtkText, text)
  of '<':
    # Raw HTML block: consume until matching closing tag (handles nesting)
    lex.strbuf.setLen(0)
    var tag: string
    var stopTagName = false
    # Parse opening tag and get tag name
    let tagStart = lex.pos
    while true:
      case lex.current
      of '>', '\0': break
      of ' ':
        stopTagName = true
        lex.strbuf.add(lex.current)
      of 'a'..'z', 'A'..'Z', '0'..'9', '_', '-':
        lex.strbuf.add(lex.current)
        if not stopTagName:
          tag.add(lex.current)
      else:
        lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '>':
      lex.strbuf.add(lex.current)
      lex.advance()
    # now consume until outermost closing tag
    # TODO test for self-closing tags
    var htmlContent = lex.strbuf
    var depth = 1
    while depth > 0 and lex.current != '\0':
      if lex.current == '<':
        if lex.peek() == '/':
          # Possible closing tag
          var closeTag = ""
          var tempPos = lex.pos + 2
          while tempPos < lex.input.len and lex.input[tempPos] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
            closeTag.add(lex.input[tempPos])
            inc tempPos
          if closeTag == tag:
            depth -= 1
          # Add chars to htmlContent until '>'
          while lex.current != '>' and lex.current != '\0':
            htmlContent.add(lex.current)
            lex.advance()
          if lex.current == '>':
            htmlContent.add(lex.current)
            lex.advance()
          continue
        else:
          # Possible nested opening tag
          var openTag = ""
          var tempPos = lex.pos + 1
          while tempPos < lex.input.len and lex.input[tempPos] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
            openTag.add(lex.input[tempPos])
            inc tempPos
          if openTag == tag:
            depth += 1
      htmlContent.add(lex.current)
      lex.advance()
    return newTokenTuple(lex, mtkHtml, htmlContent, attrs=some(@[tag]))
  of '|':
    if lex.col == 0:
      # table row
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      return newTokenTuple(lex, mtkTable, lex.strbuf)
    else:
      # treat as text
      lex.advance()
      return newTokenTuple(lex, mtkText, "|")
  else:
    # Paragraph or plain text
    # Scan for auto links anywhere in the text
    let tokens = lex.scanTextWithLinks() # This should be optional, no?
    if tokens.len > 0:
      if tokens.len > 1:
        lex.pendingTokens = tokens[1..^1]
      return tokens[0]
    return newTokenTuple(lex, mtkUnknown)

when isMainModule:
  var lexer = initLexer(readFile("bin/test.md"))
  while true:
    let token = lexer.nextToken()
    echo token
    if token.kind == mtkEOF:
      break