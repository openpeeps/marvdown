import std/[os, strutils, times, htmlgen]
import kapsis/[runtime, cli]
import nimwkhtmltox/pdf
import ../marv, ./watch

proc runCommand*(v: Values) =
  if not v.has("md"):
    display("Nothing to parse. Missing `.md` doc")
    QuitFailure.quit
  let
    filePath = absolutePath(v.get("md").normalizedPath)
    size = filePath.getFileSize
  var toStdout = v.has("output") == false
  if toStdout and size > 100000:
    if not promptConfirm("Big things ahead ($1)! Are you sure you want to continue?" % [size.formatSize()]):
      QuitFailure.quit
    toStdout = true
  let
    content = filePath.readFile
    minify =
      if v.flag("minify") == false: false
      else: true
  let
    t = cpuTime()
    md = newMarkdown(content, minify)
  if toStdout:
    display(md.toHtml)
  else:
    let output = absolutePath(v.get("output").normalizedPath)
    if output.isValidFilename:
      if output.endsWith(".html") or output.endsWith(".htm"):
        # build a HTML from Markdown
        writeFile(output, md.toHtml)
      elif output.endsWith(".pdf"):
        # build a PDF from Markdown
        initPDF()
        let pdfSettings = createGlobalSettings()
        pdfSettings.setGlobalSetting("out", cstring(output))
        let
          conv = createConverter(pdfSettings)
          objSettings = createObjectSettings()
        conv.addObject(objSettings, md.toHtml)
        conv.convert()
        deinitPDF()
        if v.flag("watch"):
          runServer(filePath, output, 120)
      elif output.endsWith(".json"):
        # build a JSON from Markdown
        discard # todo
    else:
      display("Invalid `output` path")
      QuitFailure.quit
  display("Done in " & $(cpuTime() - t) & " sec")
  QuitSuccess.quit
