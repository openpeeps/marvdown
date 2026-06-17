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
    mtkStrikethrough,  # Strikethrough text (~~text~~)
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
    indent: int        # Indentation level (in spaces) for list items
    attrs: Option[seq[string]]

  MarkdownLexer* = object
    input*: string
    current*: char
    pos*, line*, col*: int
    strbuf*: string
    pendingTokens: seq[MarkdownTokenTuple] # Buffer for tokens split from text
    enableEmailAutolinks*: bool

#
# Markdown Lexer
#
proc initLexer*(input: sink string, enableEmailAutolinks: bool = false): MarkdownLexer =
  result.input = input
  result.pos = 0
  result.line = 1
  result.col = 0
  result.strbuf = ""
  result.enableEmailAutolinks = enableEmailAutolinks
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
  (kind, "", lex.line, lex.pos, lex.col, 0, none(seq[string]))

# For tokens that need a value (identifiers, numbers, strings, etc)
proc initToken(lex: var MarkdownLexer, kind: MarkdownTokenKind,
                value: sink string): MarkdownTokenTuple =
  (kind, value, lex.line, lex.pos, lex.col, 0, none(seq[string]))

proc newTokenTuple(lex: MarkdownLexer, kind: MarkdownTokenKind,
            token: string = "",
            attrs: Option[seq[string]] = none(seq[string])
        ): MarkdownTokenTuple =
  (kind, token, lex.line, lex.col - token.len, lex.pos, 0, attrs)

proc parseIndentedCodeBlock(lex: var MarkdownLexer): MarkdownTokenTuple =
  lex.strbuf.setLen(0)
  while true:
    # Peek at the start of the next line to check indent level
    var peekPos = lex.pos
    var indentChars = 0
    var isTab = false
    while peekPos < lex.input.len and lex.input[peekPos] == ' ':
      inc indentChars
      inc peekPos
    if peekPos < lex.input.len and lex.input[peekPos] == '\t':
      isTab = true
    if peekPos < lex.input.len and lex.input[peekPos] in {'\n', '\r', '\0'}:
      # Blank line within code block
      if lex.strbuf.len > 0:
        lex.strbuf.add('\n')
      while lex.current in {'\n', '\r'}:
        if lex.current == '\r' and lex.peek() == '\n':
          lex.advance()
        lex.advance()
      continue
    if not (indentChars >= 4 or isTab):
      break
    # Consume the leading indent
    while lex.current == ' ':
      lex.advance()
    if lex.current == '\t':
      lex.advance()
    # Read the rest of the line
    while lex.current notin {'\n', '\r', '\0'}:
      lex.strbuf.add(lex.current)
      lex.advance()
    lex.strbuf.add('\n')
    # Consume newline(s)
    while lex.current in {'\n', '\r'}:
      if lex.current == '\r' and lex.peek() == '\n':
        lex.advance()
      lex.advance()
  return newTokenTuple(lex, mtkCodeBlock, lex.strbuf)

proc handleAutoLink(lex: var MarkdownLexer): MarkdownTokenTuple =
  var tempStrBuf = ""
  let startPos = lex.pos
  while lex.current notin {' ', '\t', '\n', '\r', '\0'}:
    tempStrBuf.add(lex.current)
    lex.advance()
  return newTokenTuple(lex, mtkLink, attrs=some(@[tempStrBuf, tempStrBuf]))

proc skipWhitespace(lex: var MarkdownLexer) =
  while lex.current in {' ', '\t'}:
    lex.advance()
    inc lex.col

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
      # Check for setext heading (=== or === underline)
      if (nextChar == '=' or nextChar == '-') and buf.len > 0:
        let ch = nextChar
        var peekPos = lex.pos + 1
        var underlineLen = 0
        while peekPos < lex.input.len and lex.input[peekPos] == ch:
          inc underlineLen
          inc peekPos
        while peekPos < lex.input.len and lex.input[peekPos] in {' ', '\t'}:
          inc peekPos
        if underlineLen >= 3 and (peekPos >= lex.input.len or
                                  lex.input[peekPos] in {'\n', '\r', '\0'}):
          let headingText = buf.strip()
          buf.setLen(0)
          lex.advance() # consume the newline
          # Consume the underline line
          while lex.current notin {'\n', '\r', '\0'}:
            lex.advance()
          if lex.current in {'\n', '\r'}:
            lex.advance()
          let level = if ch == '=': "1" else: "2"
          result.add(newTokenTuple(lex, mtkHeading, headingText, attrs=some(@[level])))
          return result
      # Single newline: treat as space
      buf.add(' ')
      lex.advance()
      continue
    # Check for hard line break (two spaces before newline)
    if lex.current == ' ' and lex.peek() == ' ' and (lex.peek(2) in {'\n', '\r'}):
      if buf.len > 0:
        result.add(newTokenTuple(lex, mtkText, buf))
        buf.setLen(0)
      lex.advance()  # skip first space
      lex.advance()  # skip second space
      if lex.current in {'\n', '\r'}:
        lex.advance()  # skip newline
      result.add(newTokenTuple(lex, mtkLineBreak))
      return result
    if lex.current in {'\0', '*', '_', '[', ']', '!', '`', '<', '|', '\\', '~'}:
      break # stop at special characters that may start a new token
    buf.add(lex.current)
    lex.advance()
  if buf.len > 0:
    result.add(newTokenTuple(lex, mtkText, buf))

proc nextToken*(lex: var MarkdownLexer): MarkdownTokenTuple =
  ## Lex the next token from the input

  # Return pending tokens from text scanning if available,
  # this must be checked before looking for new tokens or EOF,
  # otherwise we might miss auto-link tokens that are generated from text scanning.

  if lex.pendingTokens.len > 0:
    let tok = lex.pendingTokens[0]
    lex.pendingTokens = lex.pendingTokens[1..^1]
    return tok

  # Skip newlines and detect paragraph breaks
  var newlineCount = 0
  while lex.current == '\n' or lex.current == '\r':
    if lex.current == '\r' and lex.peek() == '\n':
      lex.advance()
    if lex.current == '\n' or lex.current == '\r':
      inc newlineCount
      lex.col = 0
      lex.advance()
      continue
    break

  if newlineCount >= 2:
    return newTokenTuple(lex, mtkParagraph)

  if lex.current == '\0':
    # End of input
    return newTokenTuple(lex, mtkEOF)

  # Indented code block (4 spaces or 1 tab at line start)
  if lex.current == ' ' and newlineCount > 0:
    var sc = 0
    var tp = lex.pos
    while tp < lex.input.len and lex.input[tp] == ' ':
      inc sc; inc tp
    if sc >= 4:
      return lex.parseIndentedCodeBlock()
  elif lex.current == '\t' and newlineCount > 0:
    return lex.parseIndentedCodeBlock()

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
  of '-', '_':
    # Horizontal rule or unordered list or emphasis/strong
    let indentCol = lex.col
    let ch = lex.current
    var count = 0
    while lex.current == ch:
      inc count
      lex.advance()

    if count >= 3 and (lex.current in {'\n', '\r', '\0'}):
      # Horizontal rule, or the beginning of a YAML front matter
      if lex.line == 1 and lex.current in {'\n', '\r'}:
        # Check if next line has content (not just blank)
        var peekPos = lex.pos + 1
        while peekPos < lex.input.len and lex.input[peekPos] in {' ', '\t'}:
          inc peekPos
        if peekPos < lex.input.len and lex.input[peekPos] notin {'\n', '\r', '\0'}:
          # YAML front matter detected
          lex.strbuf.setLen(0)
          while true:
            if lex.current == '\0':
              break
            if lex.current == '-' and lex.peek() == '-' and lex.peek(2) == '-':
              lex.advance(); lex.advance(); lex.advance()
              if lex.current in {'\n', '\r'}:
                lex.advance()
              break
            lex.strbuf.add(lex.current)
            lex.advance()
          return newTokenTuple(lex, mtkDocument, lex.strbuf.strip())
      return newTokenTuple(lex, mtkHorizontalRule, repeat(ch, count))

    if ch == '-' and (lex.current == ' ' or lex.current == '\t'):
      # Unordered list item; '*' and '+' have their own handlers
      lex.advance()
      skipWhitespace(lex)
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
          result = newTokenTuple(lex, mtkListItemCheckbox,
                  lex.strbuf.strip(), attrs=some(@["checkbox", checkState]))
          result.indent = indentCol
          return result

      # Otherwise, normal list item
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      result = newTokenTuple(lex, mtkListItem, lex.strbuf.strip())
      result.indent = indentCol
      return result

    if ch == '_':
      # Emphasis or strong with underscore
      if lex.peek() == '_':
        lex.advance(); lex.advance()
        return newTokenTuple(lex, mtkStrong)
      else:
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
    let indentCol = lex.col
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
      result = newTokenTuple(lex, mtkOListItem, lex.strbuf.strip())
      result.indent = indentCol
      return result
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
    elif lex.current == '~' and lex.peek() == '~':
      # Strikethrough (~~)
      lex.advance(); lex.advance()
      return newTokenTuple(lex, mtkStrikethrough)
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
    # Could be horizontal rule, emphasis, strong, or unordered list item
    let indentCol = lex.col
    var starCount = 1
    while lex.peek(starCount) == '*':
      inc starCount
    if starCount >= 3 and (lex.peek(starCount) in {'\n', '\r', '\0'}):
      # Horizontal rule (***)
      var i = 0
      while i < starCount:
        lex.advance()
        inc i
      return newTokenTuple(lex, mtkHorizontalRule, repeat('*', starCount))
    if indentCol == 0 and (lex.peek() == ' ' or lex.peek() == '\t'):
      # List item (e.g., "* item") only at start of line
      lex.advance()
      skipWhitespace(lex)
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      result = newTokenTuple(lex, mtkListItem, lex.strbuf.strip())
      result.indent = indentCol
      return result
    elif lex.peek() == '*':
      lex.advance(); lex.advance()
      return newTokenTuple(lex, mtkStrong)
    else:
      lex.advance()
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
  of '+':
    # Unordered list item (e.g., "+ item")
    let indentCol = lex.col
    lex.advance()
    if lex.current == ' ' or lex.current == '\t':
      skipWhitespace(lex)
      lex.strbuf.setLen(0)
      while lex.current notin {'\n', '\r', '\0'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      result = newTokenTuple(lex, mtkListItem, lex.strbuf.strip())
      result.indent = indentCol
      return result
    else:
      return newTokenTuple(lex, mtkText, "+")
  of '<':
    # Check for email autolink: <user@example.com>
    if lex.enableEmailAutolinks:
      var peekPos = lex.pos + 1
      var atPos = -1
      var dotAfterAt = false
      while peekPos < lex.input.len and lex.input[peekPos] notin {'>', ' ', '\t', '\n', '\r', '\0', '<'}:
        if lex.input[peekPos] == '@':
          atPos = peekPos
        if atPos > 0 and lex.input[peekPos] == '.' and peekPos > atPos:
          dotAfterAt = true
        inc peekPos
      if peekPos < lex.input.len and lex.input[peekPos] == '>' and atPos > 0 and dotAfterAt:
        let email = lex.input[lex.pos + 1 .. peekPos - 1]
        # Consume <email>
        lex.advance()  # skip '<'
        while lex.current != '>' and lex.current != '\0':
          lex.advance()
        if lex.current == '>':
          lex.advance()
        return newTokenTuple(lex, mtkLink, attrs=some(@[email, "mailto:" & email]))

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
        lex.advance()
      of 'a'..'z', 'A'..'Z', '0'..'9', '_', '-':
        lex.strbuf.add(lex.current)
        if not stopTagName:
          tag.add(lex.current)
        lex.advance()
      else:
        lex.strbuf.add(lex.current)
        lex.advance()
    # Check for self-closing tag (e.g., <br/> or <br />)
    let isSelfClosing = block:
      var found = false
      var i = lex.strbuf.len - 2  # skip trailing '>'
      while i >= 0 and lex.strbuf[i] in {' ', '\t'}:
        dec i
      found = i >= 0 and lex.strbuf[i] == '/'
      found
    var htmlContent = lex.strbuf
    var depth = if isSelfClosing: 0 else: 1
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
    lex.advance()
    return newTokenTuple(lex, mtkTable, "|")
  of '\\':
    # Backslash escape — produce the literal next character
    lex.advance()
    if lex.current in {'!', '"', '#', '$', '%', '&', '\'', '(', ')',
                        '*', '+', ',', '-', '.', '/', ':', ';', '<',
                        '=', '>', '?', '@', '[', '\\', ']', '^', '_',
                        '`', '{', '|', '}', '~'}:
      let ch = $lex.current
      lex.advance()
      return newTokenTuple(lex, mtkText, ch)
    else:
      # Not escapable — emit literal backslash
      lex.advance()
      return newTokenTuple(lex, mtkText, "\\")
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