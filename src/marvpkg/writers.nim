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
        result = indent(img(src = $(node.link), alt=label, title=node.linkTitle), node.wsno)
      else:
        result = indent(img(src = $(node.link), alt=label), node.wsno)
    else:
      if node.linkTitle.len > 0:
        result = indent(a(href = $(node.link), title=node.linkTitle, label), node.wsno)
      else:
        result = indent(a(href = $(node.link), label), node.wsno)
  of ntText:
    result = indent(node.text, node.wsno)
  of ntBold:
    add result, indent(b(writeInnerNodes(node.inlineNodes)), node.wsno)
  of ntTag:
    let attrs = if node.tagAttrs.len > 0: indent(node.tagAttrs.join(" "), 1) else: "" 
    add result,
      "<" & node.tagName & attrs & ">" & writeInnerNodes(node.tagInlineNodes) & "</" & node.tagName & ">"
  of ntItalic:
    add result, indent(em(writeInnerNodes(node.inlineNodes)), node.wsno)
  of ntInner:
    add result, writeInnerNodes(node.inner)
  of ntCode:
    add result, indent(code(node.text), node.wsno)
  of ntBr:
    result = br()
  else: discard

proc toHtml*(md: Markdown): string =
  ## Converts `Markdown` document to HTML
  let len = md.nodes.len - 1
  for n in 0 .. md.nodes.high:
    var el: string
    let nt = md.nodes[n].nt
    case nt
    of ntParagraph:
      for pNode in md.nodes[n].pNodes:
        case pNode.nt:
        of ntLink:
          if pNode.isImage:
            add result, writeInnerNode(pNode)
          else:
            add result, p(writeInnerNode(pNode))
        else:
          add result, p(writeInnerNode(pNode))
    of ntHeading:
      for inner in md.nodes[n].headingNodes:
        case inner.nt
          of ntText:
            add el, indent(inner.text, inner.wsno)
          else: discard
      if md.opts.useAnchors:
        el = el.strip
        let slug = md.stackSelector("#", el, md.nodes[n])
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
    of ntBlockCode:
      var strCode: string
      for line in md.nodes[n].blockCode:
        add strCode, line
      add result, pre(code(strCode))
    of ntBlockQuote:
      var el: string
      for node in md.nodes[n].inlineNodes:
        add el, writeInnerNode(node)
      add result, blockquote(el.strip)
    of ntBr:
      add result, br()
    else: discard
    setLen(el, 0)
    if n < len: add result, nl
  nl = "\n" # revert `\n`

proc `$`*(md: Markdown): string = toHtml(md)

proc toJson*(md: Markdown): string =
  ## Parses `md` document and returns stringified `JSON`

proc toJson*(md: Markdown, toJsonNode: bool): JsonNode =
  ## Parses `md` document and returns `JsonNode`
  discard

proc toPdf*(md: Markdown, output: string, style = "") =
  ## Compiles to `.pdf`. Optionally, you can provide some cool CSS to `style`
  discard 