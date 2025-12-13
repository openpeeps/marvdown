# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[options, json]
import pkg/jsony

from std/htmlparser import HtmlTag

type
  MarkdownNodeKind* = enum
    mdkText,           # Plain text
    mdkElement,        # Generic HTML element
    mdkCodeBlock,      # Code block (fenced or indented)
    mdkHeading,        # Heading (h1, h2, h3, etc.)
    mdkList,           # Ordered or unordered list
    mdkListItem,       # List item
    mdkBlockquote,     # Blockquote
    mdkHorizontalRule, # Horizontal rule (--- or ***)
    mdkLink,           # Hyperlink
    mdkImage,          # Image
    mdkEmphasis,       # Emphasized text (italic)
    mdkStrong,         # Strongly emphasized text (bold)
    mdkInlineCode,     # Inline code
    mdkLineBreak,      # Line break
    mdkHtml,           # Raw HTML content
    mdkTable,          # Table
    mdkParagraph,      # Paragraph
    mdkFootnoteDef,    # Footnote definition
    mdkFootnoteRef,    # Footnote reference
    mdkDocument,       # Root document node
    mdkUnknown         # Unknown or unsupported node

  MarkdownNodeList* {.acyclic.} = ref object
    items*: seq[MarkdownNode]
      ## Child nodes (for container nodes)

  MarkdownNode* {.acyclic.} = ref object
    case kind*: MarkdownNodeKind
    of mdkText:
      text*: string
        ## Plain text content
    of mdkElement:
      tag*: HtmlTag
        ## HTML tag information
      attrs*: seq[(string, string)]
        ## HTML attributes as (name, value) pairs
    of mdkCodeBlock:
      code*: string
        ## Code block content
      codeLang*: string
        ## Language identifier (if any)
    of mdkHeading:
      level*: range[1..6]
        ## Heading level (1-6)
      textAnchor*: Option[string]
        ## Anchor for the heading (for linking)
        ## Generated if `enableAnchors` is true in `MarkdownOptions`
    of mdkList:
      listOrdered*: bool
    of mdkLink:
      linkHref*: string
        ## URL for the link
      linkTitle*: string
        ## Title text for the link
    of mdkImage:
      imageSrc*: string
        ## Image source URL
      imageAlt*: string
        ## Alt text for the image
      imageTitle*: string
        ## Title text for the image
    of mdkInlineCode:
      inlineCode*: string
        ## Inline code content
    of mdkHtml:
      html*: string
        ## Raw HTML content
    of mdkTable:
      headers*: seq[string]
        ## Table headers
      rows*: seq[seq[string]]
        ## Table rows
    of mdkUnknown:
      info*: string # For unknown or unsupported nodes
    of mdkFootnoteRef:
      footnoteRefId*: string
        ## Identifier for the footnote reference
    of mdkFootnoteDef:
      footnoteId*: string
        ## Identifier for the footnote definition
    else: discard
    children*: MarkdownNodeList
      ## Child nodes (for container nodes)
    line*: int
      ## Line number in the source markdown

proc debugEcho*(n: MarkdownNode) =
  echo toJson(n)

proc newText*(text: string, ln: int): MarkdownNode =
  result = MarkdownNode(kind: mdkText)
  result.text = text
  result.line = ln

proc newImage*(alt, src, title: string, ln: int): MarkdownNode =
  result = MarkdownNode(kind: mdkImage)
  result.imageAlt = alt
  result.imageSrc = src
  result.imageTitle = title
  result.line = ln

proc newLink*(href, title: string, ln: int): MarkdownNode =
  result = MarkdownNode(kind: mdkLink, children: MarkdownNodeList())
  result.linkHref = href
  result.linkTitle = title
  result.line = ln

proc newRawHtml*(html: string, ln: int): MarkdownNode =
  result = MarkdownNode(kind: mdkHtml)
  result.html = html
  result.line = ln

proc newHeading*(level: range[1..6], ln: int): MarkdownNode =
  ## Create a new heading node
  MarkdownNode(
    kind: mdkHeading,
    level: level,
    children: MarkdownNodeList(),
    line: ln
  )