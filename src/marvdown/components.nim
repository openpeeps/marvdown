import std/[strutils, tables, os]

type ComponentScope* = OrderedTableRef[string, string]

proc newComponentScope*(): ComponentScope =
  newOrderedTable[string, string]()

proc resolveVariables*(text: string, scope: ComponentScope): string =
  result = newStringOfCap(text.len)
  var i = 0
  while i < text.len:
    if text[i] == '\\' and i + 1 < text.len and text[i+1] == '$':
      result.add('$')
      i += 2
    elif text[i] == '$':
      var j = i + 1
      if j < text.len and text[j] in IdentChars:
        var varName = ""
        while j < text.len and text[j] in IdentChars:
          varName.add(text[j])
          inc j
        if varName.len > 0 and scope.hasKey(varName):
          result.add(scope[varName])
        else:
          result.add('$')
          result.add(varName)
        i = j
      else:
        result.add(text[i])
        inc i
    else:
      result.add(text[i])
      inc i

proc processHtmlContent*(html: sink string, scope: var ComponentScope): string =
  var cleaned = newStringOfCap(html.len)
  var i = 0
  while i < html.len:
    if html[i] == '<':
      cleaned.add('<')
      inc i
      var tagContent = ""
      while i < html.len and html[i] != '>':
        tagContent.add(html[i])
        inc i
      var hadClose = false
      if i < html.len:
        hadClose = true
        inc i
      var processedTag = newStringOfCap(tagContent.len)
      var j = 0
      while j < tagContent.len:
        if tagContent[j] == '@' and (j == 0 or tagContent[j-1] in {' ', '\t'}):
          if j > 0 and tagContent[j-1] in {' ', '\t'} and processedTag.len > 0 and processedTag[^1] in {' ', '\t'}:
            processedTag.setLen(processedTag.len - 1)
          var k = j + 1
          var attrName = ""
          while k < tagContent.len and (tagContent[k] in IdentChars or tagContent[k] == '-'):
            attrName.add(tagContent[k])
            inc k
          if attrName.len > 0:
            while k < tagContent.len and tagContent[k] in {' ', '\t'}:
              inc k
            if k < tagContent.len and tagContent[k] == '=':
              inc k
              while k < tagContent.len and tagContent[k] in {' ', '\t'}:
                inc k
              if k < tagContent.len and tagContent[k] in {'"', '\''}:
                let q = tagContent[k]
                inc k
                var val = newStringOfCap(64)
                while k < tagContent.len and tagContent[k] != q:
                  val.add(tagContent[k])
                  inc k
                if k < tagContent.len:
                  inc k
                scope[attrName] = val
              else:
                scope[attrName] = "true"
            else:
              scope[attrName] = "true"
            j = k
            continue
        processedTag.add(tagContent[j])
        inc j
      if processedTag.len > 0 and processedTag[^1] == ' ':
        processedTag.setLen(processedTag.len - 1)
      cleaned.add(processedTag)
      if hadClose:
        cleaned.add('>')
    else:
      cleaned.add(html[i])
      inc i
  result = resolveVariables(cleaned, scope)

proc preprocess*(content: string, basePath: string, scope: var ComponentScope, visited: var seq[string]): string

proc processLineIncludes(line: string, basePath: string, scope: var ComponentScope, visited: var seq[string]): string =
  result = newStringOfCap(line.len)
  var i = 0
  while i < line.len:
    if i + 9 <= line.len and line[i] == '@' and line[i+1] == 'i' and
       line[i+2] == 'n' and line[i+3] == 'c' and line[i+4] == 'l' and
       line[i+5] == 'u' and line[i+6] == 'd' and line[i+7] == 'e' and
       line[i+8] == '(':
      var start = i + 9
      while start < line.len and line[start] in {' ', '\t'}:
        inc start
      if start < line.len and line[start] in {'"', '\''}:
        let q = line[start]
        var pend = start + 1
        while pend < line.len and line[pend] != q:
          inc pend
        if pend < line.len:
          let path = line[start+1..pend-1]
          var endParen = pend + 1
          while endParen < line.len and line[endParen] in {' ', '\t'}:
            inc endParen
          if endParen < line.len and line[endParen] == ')':
            if path.len > 0:
              let absPath = absolutePath(path, basePath)
              if absPath in visited:
                result.add("<!-- @include circular: " & path & " -->")
              else:
                visited.add(absPath)
                try:
                  let content = readFile(absPath)
                  let (_, _, ext) = splitFile(absPath)
                  if ext.toLowerAscii() == ".md":
                    result.add(preprocess(content, parentDir(absPath), scope, visited))
                  elif ext.toLowerAscii() == ".html":
                    result.add(processHtmlContent(content, scope))
                  else:
                    result.add(content)
                except IOError:
                  result.add("<!-- @include failed: " & path & " -->")
            i = endParen + 1
            continue
      result.add(line[i])
      inc i
    else:
      result.add(line[i])
      inc i

proc preprocess*(content: string, basePath: string, scope: var ComponentScope, visited: var seq[string]): string =
  var lines = content.splitLines()
  var inFence = false
  var fenceChar: char = '\0'
  var fenceLen = 0
  result = newStringOfCap(content.len)
  for line in lines:
    if not inFence:
      var i = 0
      while i < line.len and line[i] == ' ' and i < 3:
        inc i
      if i < line.len and line[i] in {'`', '~'}:
        var fl = 0
        fenceChar = line[i]
        while i < line.len and line[i] == fenceChar:
          inc fl
          inc i
        if fl >= 3:
          inFence = true
          fenceLen = fl
          result.add(line & "\n")
          continue
      result.add(processLineIncludes(line, basePath, scope, visited) & "\n")
    else:
      result.add(line & "\n")
      var i = 0
      while i < line.len and line[i] == ' ' and i < 3:
        inc i
      if i < line.len and line[i] == fenceChar:
        var cl = 0
        while i < line.len and line[i] == fenceChar:
          inc cl
          inc i
        if cl >= fenceLen:
          inFence = false
  if result.endsWith("\n"):
    result.setLen(result.len - 1)
