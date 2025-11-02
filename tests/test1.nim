import unittest
import marvdown

let opts = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
    tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl
  ],
  allowTagsByType: tagNone,
  allowInlineStyle: false,
  allowHtmlAttributes: false,
  enableAnchors: true,
  anchorIcon: "🔗"
)
test "headings with anchors":
  let sample = """
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6"""
  var md = newMarkdown(sample, opts)
  assert md.toHtml() == """<h1 id="heading-1"><a href="#heading-1" class="anchor-link">🔗</a>Heading 1</h1><h2 id="heading-2"><a href="#heading-2" class="anchor-link">🔗</a>Heading 2</h2><h3 id="heading-3"><a href="#heading-3" class="anchor-link">🔗</a>Heading 3</h3><h4 id="heading-4"><a href="#heading-4" class="anchor-link">🔗</a>Heading 4</h4><h5 id="heading-5"><a href="#heading-5" class="anchor-link">🔗</a>Heading 5</h5><h6 id="heading-6"><a href="#heading-6" class="anchor-link">🔗</a>Heading 6</h6>""" 


test "basics":
  let sample = """
## Hello World
This is a **bold** text and this is _italic_ text."""
  var md = newMarkdown(sample, opts)
  assert md.toHtml() == """<h2 id="hello-world"><a href="#hello-world" class="anchor-link">🔗</a>Hello World</h2><p>This is a <strong>bold</strong> text and this is <em>italic</em> text.</p>"""