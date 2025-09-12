# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/options

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
    mdkDocument,       # Root document node
    mdkUnknown         # Unknown or unsupported node

  MarkdownNodeList* {.acyclic.} = ref object
    items*: seq[MarkdownNode]
      ## Child nodes (for container nodes)

  MarkdownNode* {.acyclic.} = ref object
    case kind*: MarkdownNodeKind
    of mdkText:
      text*: string
    of mdkElement:
      tag*: HtmlTag
      attrs*: seq[(string, string)]
    of mdkCodeBlock:
      code*: string
      codeLang*: string
    of mdkHeading:
      level*: int
      textHeading*: string
      textAnchor*: Option[string]
        ## Anchor for the heading (for linking)
        ## Generated if `enableAnchors` is true in `MarkdownOptions`
    of mdkList:
      listOrdered*: bool
    of mdkLink:
      linkHref*: string
      linkTitle*: string
    of mdkImage:
      imageSrc*: string
      imageAlt*: string
      imageTitle*: string
    of mdkInlineCode:
      inlineCode*: string
        ## Inline code content
    of mdkHtml:
      html*: string
        ## Raw HTML content
    of mdkTable:
      headers*: seq[string]
      rows*: seq[seq[string]]
    of mdkUnknown:
      info*: string # For unknown or unsupported nodes
    else: discard
    children*: MarkdownNodeList
      ## Child nodes (for container nodes)