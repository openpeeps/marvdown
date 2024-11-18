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
    var generatedCode = readFile(outputPath)
    bodyElement =
      main(
        `div`(class="topbar noselect", a(class="btn-switch-theme")),
        `div`(class="container",
          article(generatedCode)
        )
      )
    refreshNotifier = `div`(class="marvdown-notifier",
      `div`(class="marvdown-spinner"),
      `div`(class="marvdown-logo")
    )
    reset(generatedCode)
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
{
  let notifier = document.querySelector('.marvdown-notifier')
  setTimeout(() => {notifier.style.display = 'none'}, 520)
  function connectWatchoutServer() {      
    const watchout = new WebSocket('ws://127.0.0.1:6711/ws');
    watchout.addEventListener('message', (e) => {
      if(e.data == '1') {
        notifier.style.display = 'block'
        setTimeout(() => location.reload(), 120)
      }
    });
    watchout.addEventListener('close', () => {
      setTimeout(() => {
        console.log('Watchout WebSocket is closed. Try again...')
        connectWatchoutServer()
      }, 300)
    })
  }
  connectWatchoutServer()
}
""" % [refreshNotifier]
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
  let browserSyncDelay = 200
  let browserSyncPort = Port(6711)
  # Callback `onChange`
  proc onChange(file: watchout.File) =
    display("✨ Changes detected")
    display(file.getPath, indent = 2, br="after")
    let invokeMarv = execCmdEx("./marv compile '" & file.getPath & "' " & output)
    echo invokeMarv.output

  # Callback `onFound`
  proc onFound(file: watchout.File) =
    discard

  # Callback `onDelete`
  proc onDelete(file: watchout.File) =
    discard

  let watcher =
    newWatchout(
      dirs = @[input],
      onChange, onFound, onDelete,
      recursive = true,
      ext = @[".md"],
      delay = browserSyncDelay,
      browserSync =
        WatchoutBrowserSync(
          port: browserSyncPort,
          delay: browserSyncDelay
        )
      )
  # startThread(watchoutCallback, @[input], delay, shouldJoinThread = false)
  display("🪄 Marvdown runs in browser: http://localhost:6710", br="after")
  watcher.start()

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
      # of "/ws":
      #   try:
      #     var ws = await newWebSocket(req)
      #     await ws.send($toUnix(output.getLastModificationTime))
      #     while ws.readyState == Open:
      #       await ws.send($toUnix(output.getLastModificationTime))
      #     ws.close()
      #     reset(ws)
      #   except WebSocketClosedError:
      #     echo "Socket closed"
      #   except WebSocketProtocolMismatchError:
      #     echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
      #   except WebSocketError:
      #     req.send(Http404)
      else:
        req.send(Http404)

  run(onRequest, initSettings(port = 6710.Port))
