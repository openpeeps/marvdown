# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import ../parser
import kapsis/[runtime, cli]
import httpx, websocketx, watchout, nimwkhtmltox/pdf
import std/[os, strutils, times, options, osproc,
        asyncdispatch, macros, httpcore, htmlgen]

const
  basePath = getProjectPath() / "marvpkg" / "cli"
  htmlStyle = staticRead(basePath / "style.css")
  marvLogo = staticRead(basePath / "marv.png")
proc getScreen(isPDF: bool, outputPath: string): string =
  var styleElement, bodyElement, refreshNotifier: string
  if isPDF:
    styleElement = style("*{margin:0; padding:0;}iframe{border:0; position: fixed; width: 100%;height: 100%;}")
    bodyElement = iframe(src="/preview.pdf")
  else:
    styleElement = style(`type`="text/css", htmlStyle)
    bodyElement =
      main(
        `div`(class="topbar noselect", a(class="btn-switch-theme")),
        `div`(class="container",
          article(readFile(outputPath))
        )
      )
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
      body(
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
        script("""
const lightIcon = `<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>` 
const darkIcon = `<circle cx="12" cy="12" r="5"></circle><line x1="12" y1="1" x2="12" y2="3"></line><line x1="12" y1="21" x2="12" y2="23"></line><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line><line x1="1" y1="12" x2="3" y2="12"></line><line x1="21" y1="12" x2="23" y2="12"></line><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>`

document.addEventListener('DOMContentLoaded', function(){
  if (localStorage.getItem('theme') == "dark") {
    document.body.classList.add('dark')
  }
  var btn = document.querySelector('.btn-switch-theme')
  btn.innerHTML = `
    <svg class="dark-theme" viewBox="0 0 24 24" width="24" height="24" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">${lightIcon}</svg>
    <svg class="light-theme" viewBox="0 0 24 24" width="24" height="24" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">${darkIcon}</svg>
  `
  btn.addEventListener('click', (e) => {
    if (localStorage.getItem('theme') == "dark") {
      localStorage.setItem('theme', 'light')
      document.body.classList.remove('dark')
    } else {
      localStorage.setItem('theme', 'dark')
      document.body.classList.add('dark')
    }
  })
})
"""     ),
        bodyElement
      )
    )

proc runServer*(input, output: string, delay: int) =
  proc watchoutCallback(file: watchout.File) {.closure.} =
    display("✨ Changes detected")
    display(file.getPath, indent = 2, br="after")
    let broCommand = execCmdEx("./marv " & file.getPath & " " & output)
    echo broCommand.output

  startThread(watchoutCallback, @[input], delay, shouldJoinThread = false)
  display("🪄 The Wet Bandits in Browser: http://localhost:6710", br="after")

  proc onRequest(req: Request) {.async.} =
    if req.httpMethod == some(HttpGet):
      let reqPath = req.path.get()
      case reqPath
      of "/":
        req.send(Http200, "<!DOCTYPE html>" & getScreen(output.endsWith(".pdf"), output), headers = "content-type: text/html")
      of "/preview.pdf":
        if output.endsWith(".pdf"):
          let pdfContent = readFile(output)
          req.send(Http200, pdfContent, headers= "content-type: application/pdf")
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
