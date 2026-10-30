# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

# Use Marvdown as Nimble library
import std/xmltree
import ./marvdown/[parser, ast, components]
export parser, ast, components

export hasSelectors, getSelectors, getSelectorItems, getTitle

proc toHtml*(content: sink string): owned string =
  ## Convert Markdown content to HTML
  var md = newMarkdown(content)
  md.toHtml()

proc toXML*(content: sink string): XmlNode =
  ## Convert Markdown content to XML Node
  var md = newMarkdown(content)
  # htmlparser.parseHtml(md.toHtml())

proc toXML*(md: var Markdown): XmlNode =
  ## Convert a Markdown object to XML Node
  # htmlparser.parseHtml(md.toHtml())

proc getAst*(content: sink string): string =
  ## Retrieve the Markdown AST as a stringified JSON
  var md = newMarkdown(content)
  md.toJson()

when defined(napi_build) and isMainModule:
  # Building Marvdown itself as a NAPI module entry point. isMainModule
  # keeps this out of plain dependency compiles: denim defines
  # `napibuild` (== `napi_build`, Nim ignores underscores) for the whole
  # closure, so without the entry check every addon transitively
  # importing marvdown would declare a second `init proc`.
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
  # Use Marvdown as standalone CLI application (stdlib only, no kapsis)
  import std/[os, parseopt, strutils, times, json]
  import ./marvdown/parser

  const nimbleSpec = staticRead("../marvdown.nimble")

  const versionStr = block:
    var v = "0.0.0"
    for line in nimbleSpec.splitLines():
      let t = line.strip()
      if t.startsWith("version"):
        let q1 = t.find('"')
        let q2 = t.rfind('"')
        if q1 >= 0 and q2 > q1:
          v = t[q1 + 1 ..< q2]
        break
    v

  const
    ansiReset = "\e[0m"
    ansiBoldWhite = "\e[1;37m"
    ansiGrey = "\e[90m"
    ansiRed = "\e[31m"

  proc useColor(): bool =
    getEnv("NO_COLOR") == "" and getEnv("TERM") != "dumb"

  proc paint(s, code: string): string =
    if useColor():
      code & s & ansiReset
    else:
      s

  proc label(s: string): string =
    paint(s, ansiBoldWhite)

  proc grey(s: string): string =
    paint(s, ansiGrey)

  proc errPrefix(): string =
    paint("error:", ansiRed)

  proc printHelp() =
    echo grey("marvdown " & versionStr & " – stupid simple markdown parser") & "\n"
    echo grey("MIT license | Made by Humans from OpenPeeps\n  https://github.com/openpeeps/marvdown")
    echo ""
    echo "usage: marvdown <html|json> input.md [options]"
    echo ""
    echo label("commands:")
    echo "  html <input.md>         " & grey("convert markdown to HTML (JSON envelope when parse_yaml is on)")
    echo "  json <input.md>         " & grey("export the markdown AST as JSON")
    echo ""
    echo label("options:")
    echo "  -o, --output:<file>     " & grey("write to file instead of stdout (adds .html if missing)")
    echo "  -c, --config:<file>     " & grey("load settings from .json/.yaml (snake_case keys)")
    echo "  --bench                 " & grey("print timing stats")
    echo "  -h, --help              " & grey("show this help")
    echo "  --version               " & grey("show version")

  proc runHtml(inputPath, outputArg, configArg: string,
      showBench: bool): int =
    if not fileExists(inputPath):
      echo errPrefix() & " input not found: " & inputPath
      return 1
    let
      filePath = absolutePath(normalizedPath(inputPath))
      content = readFile(filePath)
      t = cpuTime() # start timer after reading file
    # Base options (used when no `--config` is given)
    var markdownOptions = MarkdownOptions(
      allowed: @[tagA, tagAbbr, tagB, tagBlockquote, tagBr,
        tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
        tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
        tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagDiv],
      enableAnchors: false,
      enableComponents: false,
      componentBaseDir: ""
    )
    if configArg.len > 0:
      # `-c, --config:<file>`: overlay JSON/YAML settings (snake_case) onto base
      try:
        markdownOptions = loadMarkdownOptions(configArg, markdownOptions)
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
        return 1
    if markdownOptions.componentBaseDir.len == 0:
      # default @include resolution to the input file's directory
      markdownOptions.componentBaseDir = filePath.parentDir()
    var md = newMarkdown(content, markdownOptions)
    let htmlStr = md.toHtml()
    let output =
      if markdownOptions.parseYaml:
        # envelope with front matter as JSON (fields = {} without front matter)
        var envelope = newJObject()
        envelope["html"] = newJString(htmlStr)
        envelope["fields"] = md.headerJson()
        $envelope
      else:
        htmlStr
    if outputArg.len == 0:
      # write to console if no output path is specified
      stdout.writeLine(output)
      if showBench:
        # show stats if `--bench` flag is set
        stdout.writeLine("🔥 Done in " & $(cpuTime() - t) & " sec")
    else:
      var outputPath = absolutePath(normalizedPath(outputArg))
      if not outputPath.endsWith(".html"):
        # ensure .html extension
        outputPath = outputPath & ".html"
      # end timer before writing file to
      # disk to be more accurate
      let benchTime = cpuTime() - t
      # save to file
      try:
        writeFile(outputPath, output)
      except OSError as e:
        echo errPrefix() & " cannot write: " & e.msg
        return 1
      except IOError as e:
        echo errPrefix() & " cannot write: " & e.msg
        return 1
      if showBench:
        # show stats if `--bench` flag is set
        stdout.writeLine("🔥 Done in " & $benchTime & " sec")
    return 0

  proc runJson(inputPath, configArg: string): int =
    if not fileExists(inputPath):
      echo errPrefix() & " input not found: " & inputPath
      return 1
    let
      filePath = absolutePath(normalizedPath(inputPath))
      content = readFile(filePath)
    var opts = defaultOptions
    if configArg.len > 0:
      # `-c, --config:<file>`: overlay JSON/YAML settings (snake_case) onto defaults
      try:
        opts = loadMarkdownOptions(configArg, opts)
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
        return 1
    var md = newMarkdown(content, opts)
    # output JSON to console
    stdout.writeLine(md.toJson())
    return 0

  proc normalizeArgs(params: seq[string]): seq[string] =
    ## Rewrite `--flag value` (space form) to `--flag:value` for flags that
    ## take a value, since parseopt only attaches `:`/`=` values. A bare
    ## `--flag` (at the end or followed by another flag) is left untouched.
    const valueFlags = ["--output", "--out", "-o", "--config", "-c"]
    result = @[]
    var i = 0
    while i < params.len:
      let a = params[i]
      if a in valueFlags and i + 1 < params.len and
          not params[i + 1].startsWith("-"):
        result.add(a & ":" & params[i + 1])
        i += 2
      else:
        result.add(a)
        inc i

  proc main(): int =
    var
      command = ""            # subcommand: `html` or `json`
      positionals: seq[string] = @[] # positional args after the subcommand (input.md, [output])
      outputArg = ""          # `-o, --output:<file>`: write HTML to file instead of stdout
      configArg = ""          # `-c, --config:<file>`: JSON/YAML settings file (snake_case keys)
      showBench = false       # `--bench`: print conversion timing stats
      showHelp = false        # `-h, --help`: show usage
      showVersion = false     # `--version`: print version from .nimble
    # shortNoVal={'h'} so `-c:cfg` / `-o:out` keep working as short options;
    # space forms (`-c cfg`, `--output out`) are normalized above
    var p = initOptParser(normalizeArgs(commandLineParams()), shortNoVal = {'h'})
    for kind, key, val in p.getopt():
      case kind
      of cmdArgument:
        if command == "":
          command = key
        else:
          positionals.add(key)
      of cmdLongOption, cmdShortOption:
        let k = key.toLowerAscii()
        case k
        of "help", "h":
          # `-h, --help`: show usage and exit
          showHelp = true
        of "version":
          # `--version`: print version and exit
          showVersion = true
        of "output", "out", "o":
          # `-o, --output:<file>` (also `--output=file`, `--output file`):
          # destination HTML file; `.html` is appended when missing
          outputArg = val
        of "config", "c":
          # `-c, --config:<file>` (also `--config=file`, `-c file`):
          # JSON/YAML settings file with snake_case keys
          configArg = val
        of "bench":
          # `--bench`: print timing stats after converting
          showBench = true
        else:
          echo errPrefix() & " unknown option --" & key
          printHelp()
          return 1
      of cmdEnd:
        discard
    if showVersion:
      echo versionStr
      return 0
    if showHelp or command == "" or command == "help":
      printHelp()
      return 0
    if command notin ["html", "json"]:
      echo errPrefix() & " unknown command: " & command
      printHelp()
      return 1
    if command == "html":
      if positionals.len == 0:
        printHelp()
        echo "\n" & errPrefix() & " input is required"
        return 1
      # bare `marvdown html in.md out.html`: second positional is the output
      var inputPath = positionals[0]
      var outPath = outputArg
      if outPath.len == 0 and positionals.len >= 2:
        outPath = positionals[1]
      if positionals.len > 2:
        echo errPrefix() & " only one input allowed"
        printHelp()
        return 1
      return runHtml(inputPath, outPath, configArg, showBench)
    # command == "json"
    if positionals.len == 0:
      printHelp()
      echo "\n" & errPrefix() & " input is required"
      return 1
    if positionals.len > 1:
      echo errPrefix() & " only one input allowed"
      printHelp()
      return 1
    return runJson(positionals[0], configArg)

  quit(main())