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
  enableAnchors: true
)

test "basic MD to HTML":
  let sample = """
## Hello World
This is a **bold** text and this is _italic_ text."""
  let md = newMarkdown(sample, opts)
  assert md.toHtml() == """<h2 id="hello-world"><a href="#hello-world">🔗</a>Hello World</h2><p>This is a <strong>bold</strong>text and this is <em>italic</em>text.</p>"""