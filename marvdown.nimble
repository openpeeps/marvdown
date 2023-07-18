# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A stupid simple Markdown library & cli app. HTML, JSON, JsonNode, PDF or Image"
license       = "MIT"
srcDir        = "src"
bin           = @["marvdown"]
binDir        = "bin"
installExt    = @["nim"]

# Dependencies

requires "nim >= 1.6.0"
requires "toktok"
requires "kapsis"
requires "denim"
requires "nimwkhtmltox"
requires "httpx", "websocketx"
requires "watchout"

task bench, "Run some benchmarks":
  exec "nim c --mm:arc -d:release --opt:speed -d:danger --verbosity:0 -r ./bench/benchmark.nim"