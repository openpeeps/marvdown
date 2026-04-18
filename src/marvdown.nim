# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

# Use Marvdown as Nimble library
import std/[htmlparser, xmltree]

import ./marvdown/[parser, ast]
export parser, ast

export hasSelectors, getSelectors, getTitle

proc toHtml*(content: sink string): owned string =
  ## Convert Markdown content to HTML
  var md = newMarkdown(content)
  md.toHtml()

proc toXML*(content: sink string): XmlNode =
  ## Convert Markdown content to XML Node
  var md = newMarkdown(content)
  htmlparser.parseHtml(md.toHtml())

proc toXML*(md: var Markdown): XmlNode =
  ## Convert a Markdown object to XML Node
  htmlparser.parseHtml(md.toHtml())

proc getAst*(content: sink string): string =
  ## Retrieve the Markdown AST as a stringified JSON
  var md = newMarkdown(content)
  md.toJson()

when defined napi_build:
  # Building Marvdown as a NAPI module
  # This allows Marvdown to be used in Node.js/Bun.js applications 
  import pkg/denim

  init proc(module: Module) =
    # Register and export functions using `export_napi` pragma
    proc initMarkdown(): napi_value {.export_napi.} =
      ## Initialize Marvdown (if needed)
      
      
    proc toHtml(content: string): napi_value {.export_napi.} =
      ## Convert Markdown to HTML via NAPI
      var md = newMarkdown(args.get("content").getStr)
      return %*(md.toHtml())

    proc getAst(content: string): napi_value {.export_napi.} =
      ## Retrieve the Markdown AST as a JSON object
      var md = newMarkdown(args.get("content").getStr)
      return %*(md.toJson())

elif isMainModule:
  # Use Marvdown as standalone CLI application
  import std/[os, strutils, times]
  
  import pkg/kapsis
  import pkg/kapsis/runtime
  import pkg/kapsis/interactive/prompts

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
          tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagDiv],
        enableAnchors: v.has("--optAnchors")
      )
      t = cpuTime() # start timer after reading file

    var md = newMarkdown(content, markdownOptions)

    var outputPath =
      if hasOutputPath:
        absolutePath(normalizedPath($(v.get("output").getFilename)))
      else: ""

    if not outputPath.endsWith(".html"):
      # ensure .html extension
      outputPath = outputPath & ".html"

    if not hasOutputPath:
      # write to console if no output path is specified
      stdout.writeLine(md.toHTML())
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

  proc jsonCommand(v: Values) =
    ## Convert Markdown to JSON via CLI
    if not v.has("md"):
      display("Nothing to parse. Missing `.md` doc")
      QuitFailure.quit

    let
      filePath = absolutePath(normalizedPath($(v.get("md").getPath)))
      content = readFile(filePath)

    var md = newMarkdown(content)

    # output JSON to console
    stdout.writeLine(md.toJson())

  # Kapsis CLI Application
  initKapsis do:
    commands:
      html path(md), ?filename(output),
        ?bool("--optAnchors"),
        ?bool("--bench"):
          ## Write a markdown document to HTML
      
      json path(md):
        ## Export the markdown AST as JSON