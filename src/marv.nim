# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

when defined napibuild:
  # Build a native NAPI addon using Denim
  import pkg/denim
  import ./marvpkg/parser

  init proc(module: Module) =
    proc toHtml(content: string, minify: bool) {.export_napi.} =
      ## Parse markdown contents to HTML
      var md = newMarkdown(args.get("content").getStr, args.get("minify").getBool)
      return %* toHtml(md)

    proc md2json(content: string, minify: bool) {.export_napi.} =
      ## Parse markdown contents to JSON
      var md = newMarkdown(args.get("content").getStr, args.get("minify").getBool)
      return %* toJSON(md)

elif isMainModule:
  # Use Marvdown as standalone CLI application
  import pkg/kapsis
  import ./marvpkg/cli/cCommand

  commands:
    compile path(`md`), ?path(`output`), ?string(`css`), bool(--min), bool(--watch):
      ## Build to HTML, JSON or PDF. CSS Styling is optional
else:
  # Use Marvdown as Nimble library
  import ./marvpkg/parser
  export parser
