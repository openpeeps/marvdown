# Marv - A stupid simple Markdown parser
#
# (c) 2025 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import std/[htmlgen, strutils, options]
import ./ast

#
# Convert parsed Markdown to HTML
#
proc renderNode*(node: MarkdownNode): string =
  ## Render a single MarkdownNode to HTML. This proc is called recursively for child nodes.
  case node.kind
  of mdkText:
    result = node.text
  of mdkStrong:
    var content = ""
    for child in node.children.items:
      content.add(renderNode(child))
    result = strong(content)
  of mdkEmphasis:
    var content = ""
    for child in node.children.items:
      content.add(renderNode(child))
    result = em(content)
  of mdkLink:
    var linkContent = ""
    for child in node.children.items:
      linkContent.add(renderNode(child))
    result = a(href=node.linkHref, title=node.linkTitle, linkContent)
  of mdkImage:
    result = img(src=node.imageSrc, alt=node.imageAlt, title=node.imageTitle)
  of mdkList:
    var listItems = ""
    for item in node.children.items:
      listItems.add(renderNode(item))
    if node.listOrdered:
      result = ol(listItems)
    else:
      result = ul(listItems)
  of mdkListItem:
    var itemContent = ""
    for child in node.children.items:
      itemContent.add(renderNode(child))
    result = li(itemContent)
  of mdkHeading:
    # Write headline with anchor if enabled
    if node.textAnchor.isSome:
      let anchorlink = 
        a(href = "#" & node.textAnchor.get(), "🔗")
      add result,
        case node.level
        of 1: h1(id=node.textAnchor.get(), anchorlink, node.textHeading)
        of 2: h2(id=node.textAnchor.get(), anchorlink, node.textHeading)
        of 3: h3(id=node.textAnchor.get(), anchorlink, node.textHeading)
        of 4: h4(id=node.textAnchor.get(), anchorlink, node.textHeading)
        of 5: h5(id=node.textAnchor.get(), anchorlink, node.textHeading)
        else: h6(id=node.textAnchor.get(), anchorlink, node.textHeading)
    else:
      add result,
        case node.level
        of 1: h1(node.textHeading)
        of 2: h2(node.textHeading)
        of 3: h3(node.textHeading)
        of 4: h4(node.textHeading)
        of 5: h5(node.textHeading)
        else: h6(node.textHeading)
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
        paraContent.add(renderNode(child))
    add result, p(paraContent)
  of mdkCodeBlock:
    # Code block with optional language class
    let codeBlock = node.code.multiReplace(
        ("<", "&lt;"), (">", "&gt;"),
        ("\"", "&quot;"), ("&", "&amp;")
      )
    let classAttr = if node.codeLang.len > 0: " class=\"language-" & node.codeLang & "\"" else: ""
    result.add("<pre><code" & classAttr & ">" & codeBlock.strip() & "</code></pre>")
  of mdkInlineCode:
    let inlineCode = node.inlineCode.multiReplace(
        ("<", "&lt;"), (">", "&gt;"),
        ("\"", "&quot;"), ("&", "&amp;")
      )
    result = "<code>" & inlineCode & "</code>"
  else:
    discard
