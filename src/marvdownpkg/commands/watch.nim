# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import ../marv
import kapsis/[runtime, cli]
import httpx, websocketx, watchout, nimwkhtmltox/pdf
import std/[os, strutils, times, options, osproc,
        asyncdispatch, macros, httpcore, htmlgen]

const
  basePath = getProjectPath() / "marvdownpkg" / "commands"
  htmlStyle = staticRead(basePath / "style.css")
  marvLogo = staticRead(basePath / "marv.png")
proc getScreen(isPDF: bool, outputPath: string): string =
  var styleElement, bodyElement, refreshNotifier: string
  if isPDF:
    styleElement = style("*{margin:0; padding:0;}iframe{border:0; position: fixed; width: 100%;height: 100%;}")
    bodyElement = iframe(src="/preview.pdf")
  else:
    styleElement = style(`type`="text/css", htmlStyle)
    bodyElement = main(article(readFile(outputPath)))
    refreshNotifier = `div`(class="marvdown-notifier", style="display:none;",
      `div`(class="marvdown-spinner"),
      `div`(class="marvdown-logo")
    )
  result = 
    html(dir="ltr",
      head(
        meta(charset="utf-8"),
        meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1"),
        title("Marvdown"),
        styleElement,
      ),
      body(tabindex="1",
        script("""
document.body.insertAdjacentHTML('afterbegin', `$1`);
let notifier = document.querySelector('.marvdown-notifier')
const msocket = new WebSocket('ws://127.0.0.1:6710/ws');
var lastTimeModified = localStorage.getItem('watchout') || 0
msocket.addEventListener('message', (e) => {
  if(parseInt(e.data) > lastTimeModified) {
    notifier.style.display = 'block'
    localStorage.setItem('watchout', e.data)
    lastTimeModified = e.data
    setTimeout(() => location.reload(), 320)
  }
})""" % [refreshNotifier]
        ),
        bodyElement
      )
    )

proc runServer*(input, output: string, delay: int) =
  proc watchoutCallback(file: watchout.File) {.closure.} =
    display("✨ Changes detected")
    display(file.getPath, indent = 2, br="after")
    let broCommand = execCmdEx("./marvdown " & file.getPath & " " & output)
    echo broCommand.output

  startThread(watchoutCallback, @[input], delay, shouldJoinThread = false)
  display("🪄 The Wet Bandits in Browser: http://localhost:6710", br="after")

  let defaults = ""
  proc onRequest(req: Request) {.async.} =
    if req.httpMethod == some(HttpGet):
      let reqPath = req.path.get()
      case reqPath
      of "/":
        req.send(Http200, "<!DOCTYPE html>" & getScreen(output.endsWith(".pdf"), output), headers = defaults & "content-type: text/html")
      of "/preview.pdf":
        if output.endsWith(".pdf"):
          let pdfContent = readFile(output)
          req.send(Http200, pdfContent, headers= defaults & "content-type: application/pdf")
        else:
          req.send(Http404)
      of "/marv.png":
        req.send(Http200, marvLogo, headers = "content-type: image/png")
      of "/ws":
        try:
          var ws = await newWebSocket(req)
          await ws.send($toUnix(output.getLastModificationTime))
          while ws.readyState == Open:
            await ws.send($toUnix(output.getLastModificationTime))
          ws.close()
          reset(ws)
        except WebSocketClosedError:
          echo "Socket closed"
        except WebSocketProtocolMismatchError:
          echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
        except WebSocketError:
          req.send(Http404)
      else:
        req.send(Http404)
  run(onRequest, initSettings(port = 6710.Port))
