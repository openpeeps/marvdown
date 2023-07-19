# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

when defined napibuild:
  # Build a native NAPI addon using Denim
  import pkg/denim
  import ./marvdownpkg/marv

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
  # Marvdown as a standalone CLI app. cuz its cool
  import pkg/kapsis
  import pkg/kapsis/db
  import ./marvdownpkg/commands/cCommand
  App:
    settings(database = dbMsgPacked, mainCmd = "c")
    about:
      "This is Marv! A stupid simple Markdown parser"
      "Made by Humans from OpenPeeps"
      "https://github.com/openpeeps/marvdown"

    commands:
      $ "c" `md` `output` `css` ["min", "watch"]:
        ? "Build to HTML, JSON or PDF. CSS Styling is optional"
else:
  # Marvdown as a Nimble library <3
  import ./marvdownpkg/marv
  export marv
