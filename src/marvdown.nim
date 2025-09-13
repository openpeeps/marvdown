# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

when defined napibuild:
  # Build a native NAPI addon using Denim
  import pkg/denim
  import ./marvdown/parser

  init proc(module: Module) =
    proc toHtml(content: string) {.export_napi.} =
      ## Convert Markdown content to HTML
      var md = newMarkdown(args.get("content").getStr)
      return %* toHtml(md)

elif isMainModule:
  # Use Marvdown as standalone CLI application
  import std/[os, strutils, times]
  
  import pkg/kapsis
  import pkg/kapsis/[runtime, cli]

  import ./marvdown/parser

  proc htmlCommand*(v: Values) =
    ## Convert Markdown to HTML via CLI
    if not v.has("md"):
      display("Nothing to parse. Missing `.md` doc")
      QuitFailure.quit

    let
      filePath = absolutePath(normalizedPath($(v.get("md").getPath)))
      hasOutputPath = v.has("output")
      size = filePath.getFileSize
      content = readFile(filePath)
      showBench = v.has("--bench")
      
      # Default Markdown options
      markdownOptions = MarkdownOptions(
        allowed: @[tagA, tagAbbr, tagB, tagBlockquote, tagBr,
          tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
          tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
          tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl],
        enableAnchors: v.has("--optAnchors")
      )
      t = cpuTime() # start timer after reading file
      md = newMarkdown(content, markdownOptions)

    var outputPath =
      if hasOutputPath:
        absolutePath(normalizedPath($(v.get("output").getFilename)))
      else: ""

    if not outputPath.endsWith(".html"):
      # ensure .html extension
      outputPath = outputPath & ".html"

    if not hasOutputPath:
      # write to console if no output path is specified
      stdout.writeLine(md.toHtml())
      if showBench:
        # show stats if `--bench` flag is set
        stdout.writeLine("🔥 Done in " & $(cpuTime() - t) & " sec")
    else:
      # end timer before writing file to
      # disk to be more accurate
      let benchTime = cpuTime() - t
      
      # save to file
      writeFile(outputPath, md.toHtml())
      if showBench:
        # show stats if `--bench` flag is set
        stdout.writeLine("🔥 Done in " & $benchTime & " sec")

  # Kapsis CLI Application
  commands:
    html path(`md`), ?filename(`output`),
      bool(--optAnchors),
      bool(--bench):
        ## Write a markdown document to HTML
    
else:
  # Use Marvdown as Nimble library
  import std/[htmlparser, xmltree]

  import ./marvdown/[parser, ast, renderer]
  export parser, ast, renderer

  proc toHtml*(content: sink string): owned string =
    ## Convert Markdown content to HTML
    var md = newMarkdown(content)
    md.toHtml()

  proc toXML*(content: sink string): XmlNode =
    ## Convert Markdown content to XML Node
    var md = newMarkdown(content)
    htmlparser.parseHtml(md.toHtml())