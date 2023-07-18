# Marvdown, a stupid simple Markdown parser
#
# (c) 2023 George Lemon | MIT License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/marvdown

import kapsis/[runtime, cli]
import httpx, websocketx, watchout, nimwkhtmltox/pdf
import std/[os, strutils, times, options, osproc,
        asyncdispatch, macros, httpcore, htmlgen]
import ../marv

const
  pdfScreen =
    html(dir="ltr",
      head(
        meta(charset="utf-8"),
        meta(name="viewport", content="width=device-width, initial-scale=1, maximum-scale=1"),
        # meta(name="google", content="notranslate"),
        title("Marvdown"),
        style("""
* {margin:0; padding:0;}
iframe {
  border:0;
  position: fixed;
  width: 100%;
  height: 100%;
}
"""
        ),
      ),
      body(tabindex="1",
        iframe(src="/preview.pdf"),
        script("""document.addEventListener("DOMContentLoaded", function(){
  const msocket = new WebSocket("ws://127.0.0.1:6710/ws");
  var lastTimeModified = localStorage.getItem("watchout") || 0
  msocket.addEventListener("message", (e) => {
    if(parseInt(e.data) > lastTimeModified) {
      localStorage.setItem("watchout", e.data)
      lastTimeModified = e.data
      location.reload()
    }
  })
})"""
        )
      )
    )

proc runServer*(input, output: string, delay: int) =
  proc watchoutCallback(file: watchout.File) {.closure.} =
    display("✨ Changes detected")
    display(file.getPath, indent = 2, br="after")
    let broCommand = execCmdEx("./marvdown " & file.getPath & " " & output)
    # display(broCommand.output)
    # display("Done in " & $(getMonotime() - t).inMilliseconds & "ms")

  startThread(watchoutCallback, @[input], delay, shouldJoinThread = false)
  
  display("🪄 The Wet Bandits in Browser: http://localhost:6710", br="after")
  # let defaults = """Cache-Control:no-cache,no-store,must-revalidate;Pragma:no-cache;Expires: 0;""" 
  let defaults = ""
  proc onRequest(req: Request) {.async.} =
    if req.httpMethod == some(HttpGet):
      let reqPath = req.path.get()
      case reqPath
      of "/":
        req.send(Http200, "<!DOCTYPE html>" & pdfScreen, headers = defaults & "content-type: text/html")
      # of "/sweetsyntax.worker.js":
        # req.send("")
      of "/preview.pdf":
        req.send(Http200, readFile(output), headers= defaults & "scontent-type: application/pdf")
      of "/ws":
        try:
          var ws = await newWebSocket(req)
          await ws.send($toUnix(output.getLastModificationTime))
          while ws.readyState == Open:
            await ws.send($toUnix(output.getLastModificationTime))
          ws.close()
        except WebSocketClosedError:
          echo "Socket closed"
        except WebSocketProtocolMismatchError:
          echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
        except WebSocketError:
          req.send(Http404)
      else:
        req.send(Http404)
  run(onRequest, initSettings(port = 6710.Port))
