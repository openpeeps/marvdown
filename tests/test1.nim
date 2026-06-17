import unittest, options, strutils
import marvdown

let opts = MarkdownOptions(
  allowed: @[
    tagA, tagAbbr, tagB, tagBlockquote, tagBr,
    tagCode, tagDel, tagDiv, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
    tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagSpan, tagStrong,
    tagTable, tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl
  ],
  allowTagsByType: none(TagType),
  allowInlineStyle: false,
  allowHtmlAttributes: false,
  enableAnchors: true,
  anchorIcon: "🔗"
)

let noAnchors = MarkdownOptions(
  allowed: opts.allowed,
  enableAnchors: false
)

let withEmailAutolinks = MarkdownOptions(
  allowed: opts.allowed,
  enableAnchors: false,
  enableEmailAutolinks: true
)

suite "basics":
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

  test "p + inline formatting":
    let sample = "This is a **bold** text and this is _italic_ text."
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p>This is a <strong>bold</strong> text and this is <em>italic</em> text.</p>"

  test "unordered list":
    let sample = "- Item 1\n- Item 2\n- Item 3"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"

  test "unordered list with star":
    let sample = "* Item 1\n* Item 2\n* Item 3"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"

  test "unordered list with plus":
    let sample = "+ Item 1\n+ Item 2\n+ Item 3"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"

  test "ordered list":
    let sample = "1. First\n2. Second\n3. Third"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<ol><li>First</li><li>Second</li><li>Third</li></ol>"

  test "auto-linking":
    let sample = "Check out https://www.example.com for more info."
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == """<p>Check out <a href="https://www.example.com">https://www.example.com</a> for more info.</p>"""

  test "strikethrough":
    let sample = "This is ~~strikethrough~~ text."
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p>This is <del>strikethrough</del> text.</p>"

  test "backslash escape":
    let sample = r"Escaped \*literal star"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p>Escaped *literal star</p>"

  test "setext heading level 1":
    let sample = "Heading\n======="
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<h1>Heading</h1>"

  test "setext heading level 2":
    let sample = "Heading\n-------"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<h2>Heading</h2>"

  test "fenced code block":
    let sample = "```\ncode\n```"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<pre><code class=\"\">code</code></pre>"

  test "fenced code block with lang":
    let sample = """```nim
echo "hi"
```"""
    var md = newMarkdown(sample, opts)
    assert md.toHtml().contains("language-nim")
    assert md.toHtml().contains("echo")

  test "inline code":
    let sample = "Use `code` inline."
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p>Use <code>code</code> inline.</p>"

  test "blockquote":
    let sample = "> A wise quote."
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<blockquote>A wise quote.</blockquote>"

  test "horizontal rule":
    let sample = "---"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<hr>"

  test "horizontal rule stars":
    let sample = "***"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<hr>"

  test "image":
    let sample = "![alt](https://example.com/img.png \"title\")"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == """<img src="https://example.com/img.png" alt="alt" title="title" />"""

  test "link":
    let sample = "[text](https://example.com \"Title\")"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == """<p><a href="https://example.com" title="Title">text</a></p>"""

  test "paragraphs":
    let sample = "First para.\n\nSecond para."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>First para.</p><p>Second para.</p>"

suite "extensions":
  test "yaml front matter":
    let sample = "---\ntitle: Test\n---\n\n# Hello"
    var md = newMarkdown(sample, opts)
    assert md.toHtml().contains("Hello")

  test "table":
    let sample = "| A | B |\n| - | - |\n| 1 | 2 |"
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html.contains("<table>")
    assert html.contains("<th>")
    assert html.contains("A")
    assert html.contains("B")
    assert html.contains("<td>")
    assert html.contains("1")

  test "html block":
    let sample = "<div>content</div>"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<div>content</div>"

  test "html inline":
    let sample = "<span>inline</span>"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p><span>inline</span></p>"

  test "nested list":
    let sample = "- Item 1\n  - Nested 1\n  - Nested 2\n- Item 2"
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html == "<ul><li>Item 1<ul><li>Nested 1</li><li>Nested 2</li></ul></li><li>Item 2</li></ul>"

  test "strikethrough in list":
    let sample = "- ~~strike~~"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<ul><li><del>strike</del></li></ul>"

  test "link in list":
    let sample = "- [link](https://example.com)"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == """<ul><li><a href="https://example.com">link</a></li></ul>"""

suite "edge_cases":
  test "empty input":
    var md = newMarkdown("", opts)
    assert md.toHtml() == ""

  test "blank lines":
    let sample = "a\n\n\nb"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>a</p><p>b</p>"

  test "special chars in text":
    let sample = "Hash # and dollar $ and percent %"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>Hash # and dollar $ and percent %</p>"

  test "line break":
    let sample = "line 1  \nline 2"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>line 1<br>line 2</p>"

suite "html":
  test "self-closing br":
    let sample = "<br/>"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p><br/></p>"

  test "self-closing br with space":
    let sample = "<br />"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<p><br /></p>"

  test "self-closing hr":
    let sample = "<hr/>"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<hr/>"

suite "email_autolinks":
  test "email autolink enabled":
    let sample = "<user@example.com>"
    var md = newMarkdown(sample, withEmailAutolinks)
    assert md.toHtml() == """<p><a href="mailto:user@example.com">user@example.com</a></p>"""

  test "email autolink disabled":
    let sample = "<user@example.com>"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p><user@example.com></p>"

suite "html_entities":
  test "ampersand entity":
    let sample = "AT&amp;T"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>AT&T</p>"

  test "lt and gt entities":
    let sample = "Use &lt;tag&gt; in HTML."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>Use <tag> in HTML.</p>"

  test "numeric decimal entity":
    let sample = "&#123;"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>{</p>"

  test "numeric hex entity":
    let sample = "&#x7B;"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>{</p>"

  test "unknown entity passes through":
    let sample = "&unknown;"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>&unknown;</p>"
