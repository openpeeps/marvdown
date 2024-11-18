import std/[os, strutils, times, htmlgen]
import kapsis/[runtime, cli]
# import nimwkhtmltox/pdf
import ../parser, ./watch

proc compileCommand*(v: Values) =
  if not v.has("md"):
    display("Nothing to parse. Missing `.md` doc")
    QuitFailure.quit
  let
    filePath = absolutePath(normalizedPath($(v.get("md").getPath)))
    size = filePath.getFileSize
  var toStdout = v.has("output") == false
  if toStdout and size > 100000:
    if not promptConfirm("Big things printing to stdout! ($1) Continue?" % [size.formatSize()]):
      QuitFailure.quit
    toStdout = true
  let
    content = readFile(filePath)
    minify =
      if v.has("--min") == false: false
      else: true
  let
    t = cpuTime()
    md = newMarkdown(content, minify,
          MarkdownOptions(
            allowHtmlAttributes: true,
            enableAnchors: true
          )
        )
  if toStdout:
    display(md.toHtml)
  else:
    let output = absolutePath(normalizedPath($(v.get("output").getPath)))
    if output.isValidFilename:
      if output.endsWith(".html") or output.endsWith(".htm"):
        # build a HTML from Markdown
        writeFile(output, md.toHtml)
        if v.has("--watch"):
          runServer(filePath, output, 120)
        # elif output.endsWith(".pdf"):
        #   # build a PDF from Markdown
        #   initPDF()
        #   let pdfSettings = createGlobalSettings()
        #   pdfSettings.setGlobalSetting("out", cstring(output))
        #   let
        #     conv = createConverter(pdfSettings)
        #     objSettings = createObjectSettings()
        #   conv.addObject(objSettings, md.toHtml)
        #   conv.convert()
        #   deinitPDF()
        #   if v.has("--watch"):
        #     runServer(filePath, output, 120)
      elif output.endsWith(".json"):
        # build a JSON from Markdown
        discard # todo
      else:
        display("Unknown extension. Use either .html, .json or .pdf")
    else:
      display("Invalid `output` path")
      QuitFailure.quit
  display("Done in " & $(cpuTime() - t) & " sec")
  QuitSuccess.quit
