import unittest, options, strutils, tables
import marvdown
import pkg/openparser/yaml as yamlmod
import std/os

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

let fixturesDir = absolutePath("tests/fixtures")

let componentOpts = MarkdownOptions(
  allowed: opts.allowed,
  enableAnchors: false,
  enableComponents: true,
  componentBaseDir: fixturesDir
)

let withLazyloadIframes = MarkdownOptions(
  allowed: @[tagIframe, tagDiv],
  enableAnchors: false,
  lazyloadIframes: true
)

let noLazyloadIframes = MarkdownOptions(
  allowed: @[tagIframe, tagDiv],
  enableAnchors: false,
  lazyloadIframes: false
)

let withLazyloadVideos = MarkdownOptions(
  allowed: @[tagVideo, tagAudio, tagSource, tagDiv],
  enableAnchors: false,
  lazyloadVideos: true
)

let withLazyloadImages = MarkdownOptions(
  allowed: @[tagImg, tagDiv],
  enableAnchors: false,
  lazyloadImages: true
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

  test "getSelectorItems returns levels in document order":
    let sample = """
# Intro
## Example
### Example with curl
### Example with Python
## Another"""
    var md = newMarkdown(sample, opts)
    discard md.toHtml()
    let items = md.getSelectorItems()
    assert items.len == 5
    assert items[0] == (1, "intro", "Intro")
    assert items[1] == (2, "example", "Example")
    assert items[2] == (3, "example-with-curl", "Example with curl")
    assert items[3] == (3, "example-with-python", "Example with Python")
    assert items[4] == (2, "another", "Another")

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

suite "alerts":
  test "warning alert":
    let sample = "> [!WARNING]\n> The library is not production-ready."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() ==
      "<div class=\"alert alert-warning rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">The library is not production-ready.</div></div>"

  test "note alert":
    let sample = "> [!NOTE]\n> Plain note here."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() ==
      "<div class=\"alert alert-info rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">Plain note here.</div></div>"

  test "tip alert":
    let sample = "> [!TIP]\n> Use this trick."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() ==
      "<div class=\"alert alert-success rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">Use this trick.</div></div>"

  test "important alert":
    let sample = "> [!IMPORTANT]\n> Read carefully."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() ==
      "<div class=\"alert alert-primary rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">Read carefully.</div></div>"

  test "caution alert":
    let sample = "> [!CAUTION]\n> Handle with care."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() ==
      "<div class=\"alert alert-danger rounded-4\" role=\"alert\">" &
      "<div class=\"alert-content\">Handle with care.</div></div>"

  test "alert multi-line content with inline formatting":
    let sample = "> [!WARNING]\n> Some **bold** and `code` here,\n> wrapped over two lines."
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html.startsWith("<div class=\"alert alert-warning rounded-4\" role=\"alert\"><div class=\"alert-content\">")
    assert html.contains("<strong>bold</strong>")
    assert html.contains("<code>code</code>")
    assert html.contains("wrapped over two lines")
    assert not html.contains("[!WARNING]")

  test "plain blockquote unaffected":
    let sample = "> A wise quote."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<blockquote>A wise quote.</blockquote>"

  test "unknown marker stays a blockquote":
    let sample = "> [!FOO]\n> Not an alert."
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<blockquote>[!FOO]Not an alert.</blockquote>"

suite "extensions":
  test "yaml front matter":
    let sample = "---\ntitle: Test\n---\n\n# Hello"
    var md = newMarkdown(sample, opts)
    assert md.toHtml().contains("Hello")

  test "yaml getHeader":
    let sample = "---\ntitle: Introduction\ndescription: \"hello world\"\n---\n\nContent"
    var md = newMarkdown(sample, opts)
    let h = md.getHeader()
    assert not h.isNil
    assert h.hasKey("title")
    assert h.hasKey("description")
    assert yamlmod.getStr(h["title"]) == "Introduction"
    assert yamlmod.getStr(h["description"]) == "hello world"

  test "table":
    let sample = "| A | B |\n| - | - |\n| 1 | 2 |"
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html == "<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>"

  test "table with footer":
    let sample = "| A | B |\n| - | - |\n| 1 | 2 |\n|--- |--- |\n| 3 | 4 |"
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html == "<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody><tfoot><tr><td>3</td><td>4</td></tr></tfoot></table>"

  test "table without separator footer":
    let sample = "| A |\n| - |\n| 1 |\n| 2 |"
    var md = newMarkdown(sample, noAnchors)
    let html = md.toHtml()
    assert html == "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr><tr><td>2</td></tr></tbody></table>"

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

suite "bugfixes":
  test "ATX heading level capped at 6":
    let sample = "####### not a heading"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>####### not a heading</p>"

  test "fenced code block with longer closing fence":
    let sample = "```\ncode\n````"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<pre><code class=\"\">code</code></pre>"

  test "thematic break with trailing spaces":
    let sample = "---  \n"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<hr>"

  test "stars thematic break with trailing spaces":
    let sample = "***  \n"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<hr>"

suite "backtick_spans":
  test "single backtick code span":
    let sample = "`code`"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p><code>code</code></p>"

  test "double backtick with inner backtick":
    let sample = "``code`here``"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p><code>code`here</code></p>"

suite "ordered_list_start":
  test "ordered list default start":
    let sample = "1. First\n2. Second"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<ol><li>First</li><li>Second</li></ol>"

  test "ordered list with higher start":
    let sample = "3. First\n4. Second"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<ol start=\"3\"><li>First</li><li>Second</li></ol>"

suite "hard_breaks":
  test "backslash newline hard break":
    let sample = "line 1\\\nline 2"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>line 1<br>line 2</p>"

  test "three spaces before newline hard break":
    let sample = "line 1   \nline 2"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>line 1 <br>line 2</p>"

suite "reference_links":
  test "explicit reference":
    let sample = "[ref]: https://example.com\n\nSee [example][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p>See <a href="https://example.com">example</a></p>"""

  test "collapsed reference":
    let sample = "[text]: https://example.com\n\n[text][]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://example.com">text</a></p>"""

  test "shortcut reference":
    let sample = "[text]: https://example.com\n\n[text]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://example.com">text</a></p>"""

  test "undefined shortcut reference":
    let sample = "[invalid]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p>[invalid]</p>"""

  test "undefined explicit reference":
    let sample = "[text][invalid]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p>[text][invalid]</p>"""

  test "reference with title":
    let sample = "[ref]: https://example.com \"Example\"\n\n[link][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://example.com" title="Example">link</a></p>"""

  test "case insensitive label":
    let sample = "[REF]: https://example.com\n\n[text][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://example.com">text</a></p>"""

  test "first definition wins":
    let sample = "[ref]: https://first.com\n[ref]: https://second.com\n\n[link][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://first.com">link</a></p>"""

  test "reference in list item":
    let sample = "[ref]: https://example.com\n\n- [text][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<ul><li><a href="https://example.com">text</a></li></ul>"""

  test "angle bracket url in definition":
    let sample = "[ref]: <https://example.com>\n\n[link][ref]"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == """<p><a href="https://example.com">link</a></p>"""

suite "lazyload_iframes":
  test "iframe src rewritten to data-src":
    let sample = "<iframe src=\"https://example.com/embed\"></iframe>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<p><iframe data-src=\"https://example.com/embed\"></iframe></p>"

  test "iframe src with attributes rewritten":
    let sample = "<iframe width=\"560\" src=\"https://example.com/embed\" height=\"315\"></iframe>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<p><iframe width=\"560\" data-src=\"https://example.com/embed\" height=\"315\"></iframe></p>"

  test "existing data-src is not double-rewritten":
    let sample = "<iframe data-src=\"https://example.com/embed\"></iframe>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<p><iframe data-src=\"https://example.com/embed\"></iframe></p>"

  test "srcdoc and srcset are untouched":
    let sample = "<iframe src=\"https://example.com/embed\" srcdoc=\"<p>hi</p>\" srcset=\"x\"></iframe>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<p><iframe data-src=\"https://example.com/embed\" srcdoc=\"<p>hi</p>\" srcset=\"x\"></iframe></p>"

  test "nested iframe inside block is rewritten":
    let sample = "<div><iframe src=\"https://example.com/embed\"></iframe></div>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<div><iframe data-src=\"https://example.com/embed\"></iframe></div>"

  test "option off passes iframe through unchanged":
    let sample = "<iframe src=\"https://example.com/embed\"></iframe>"
    var md = newMarkdown(sample, noLazyloadIframes)
    assert md.toHtml() == "<p><iframe src=\"https://example.com/embed\"></iframe></p>"

  test "other html is unaffected when option enabled":
    let sample = "<div>content</div>"
    var md = newMarkdown(sample, withLazyloadIframes)
    assert md.toHtml() == "<div>content</div>"

suite "lazyload_videos":
  test "video src rewritten to data-src":
    let sample = "<video src=\"https://example.com/video.mp4\"></video>"
    var md = newMarkdown(sample, withLazyloadVideos)
    assert md.toHtml() == "<p><video data-src=\"https://example.com/video.mp4\"></video></p>"

  test "video source src rewritten to data-src":
    let sample = "<video><source src=\"https://example.com/video.mp4\"></video>"
    var md = newMarkdown(sample, withLazyloadVideos)
    assert md.toHtml() == "<p><video><source data-src=\"https://example.com/video.mp4\"></video></p>"

  test "audio src rewritten to data-src":
    let sample = "<audio src=\"https://example.com/audio.mp3\"></audio>"
    var md = newMarkdown(sample, withLazyloadVideos)
    assert md.toHtml() == "<p><audio data-src=\"https://example.com/audio.mp3\"></audio></p>"

  test "video with attributes rewritten":
    let sample = "<video width=\"640\" src=\"https://example.com/video.mp4\" controls></video>"
    var md = newMarkdown(sample, withLazyloadVideos)
    assert md.toHtml() == "<p><video width=\"640\" data-src=\"https://example.com/video.mp4\" controls></video></p>"

  test "video not affected when option off":
    let sample = "<video src=\"https://example.com/video.mp4\"></video>"
    var md = newMarkdown(sample, noLazyloadIframes)
    assert md.toHtml() == "<p><video src=\"https://example.com/video.mp4\"></video></p>"

suite "lazyload_images":
  test "raw html img src rewritten to data-src":
    let sample = "<img src=\"https://example.com/image.png\" alt=\"alt\">"
    var md = newMarkdown(sample, withLazyloadImages)
    assert md.toHtml() == "<p><img data-src=\"https://example.com/image.png\" alt=\"alt\"></p>"

  test "nested raw html img rewritten to data-src":
    let sample = "<div><img src=\"https://example.com/image.png\" alt=\"alt\"></div>"
    var md = newMarkdown(sample, withLazyloadImages)
    assert md.toHtml() == "<div><img data-src=\"https://example.com/image.png\" alt=\"alt\"></div>"

  test "markdown image rewritten to data-src":
    let sample = "![alt](https://example.com/image.png)"
    var md = newMarkdown(sample, withLazyloadImages)
    assert md.toHtml() == "<img data-src=\"https://example.com/image.png\" alt=\"alt\" title=\"\" />"

  test "markdown image with title rewritten to data-src":
    let sample = "![alt](https://example.com/image.png \"Title\")"
    var md = newMarkdown(sample, withLazyloadImages)
    assert md.toHtml() == "<img data-src=\"https://example.com/image.png\" alt=\"alt\" title=\"Title\" />"

  test "img not affected when option off":
    let sample = "<img src=\"https://example.com/image.png\" alt=\"alt\">"
    var md = newMarkdown(sample, noLazyloadIframes)
    assert md.toHtml() == "<p><img src=\"https://example.com/image.png\" alt=\"alt\"></p>"

  test "markdown image not affected when option off":
    let sample = "![alt](https://example.com/image.png)"
    var md = newMarkdown(sample, opts)
    assert md.toHtml() == "<img src=\"https://example.com/image.png\" alt=\"alt\" title=\"\" />"

suite "components":
  test "include markdown":
    let sample = "Hello @include(\"simple.md\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<p>Hello world</p>"

  test "include html":
    let sample = "@include(\"attrs.html\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<div>body</div>"

  test "attr extraction and variable resolution":
    let sample = "@include(\"greeting.html\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<div><h1>Hello</h1><p>Welcome to the test</p></div>"
    assert md.scope["title"] == "Hello"
    assert md.scope["desc"] == "Welcome to the test"

  test "attr boolean and hyphenated":
    let sample = "@include(\"attrs.html\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.scope["data-value"] == "123"
    assert md.scope["enabled"] == "true"

  test "variable fallback":
    let sample = "@include(\"fallback.html\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<p>$unknown</p>"

  test "dollar escape":
    let sample = "@include(\"dollar.html\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<p>$literal</p>"

  test "nested include":
    let sample = "@include(\"nested/inner.md\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml() == "<p>inner world</p>"

  test "circular include":
    let sample = "@include(\"circular_a.md\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml().contains("circular")

  test "fenced code block skip":
    let sample = "@include(\"code.md\")"
    var md = newMarkdown(sample, componentOpts)
    assert md.toHtml().contains("@include(&quot;simple.md&quot;)")

  test "components disabled passes through":
    let sample = "Hello @include(\"simple.md\")"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>Hello @include(\"simple.md\")</p>"

let transformOpts = MarkdownOptions(
  allowed: opts.allowed,
  enableAnchors: false,
  customTransform: proc(line: string): string =
    line.replace("@foo", "<span class=\"ref\">foo</span>")
)

let cardOpts = MarkdownOptions(
  allowed: opts.allowed,
  enableAnchors: false,
  customTransform: proc(line: string): string =
    if line == "@card": "<div class=\"card\">Card</div>" else: line
)

suite "customTransform":
  test "inline text replacement":
    let sample = "See @foo here"
    var md = newMarkdown(sample, transformOpts)
    assert md.toHtml() == "<p>See </p><p><span class=\"ref\">foo</span> here</p>"

  test "block-level HTML on its own line":
    let sample = "Before\n\n@card\n\nAfter"
    var md = newMarkdown(sample, cardOpts)
    assert md.toHtml() == "<p>Before</p><div class=\"card\">Card</div><p>After</p>"

  test "fenced code blocks are skipped":
    let sample = "```\n@foo\n```"
    var md = newMarkdown(sample, transformOpts)
    assert md.toHtml().contains("@foo")
    assert not md.toHtml().contains("class=\"ref\"")

  test "front matter is skipped":
    let sample = "---\nsummary: \"@foo\"\n---\n\nBody @foo"
    var md = newMarkdown(sample, transformOpts)
    let h = md.getHeader()
    assert not h.isNil
    assert yamlmod.getStr(h["summary"]) == "@foo"
    assert md.toHtml().contains("<span class=\"ref\">foo</span>")

  test "disabled when the hook is nil":
    let sample = "See @foo here"
    var md = newMarkdown(sample, noAnchors)
    assert md.toHtml() == "<p>See @foo here</p>"
