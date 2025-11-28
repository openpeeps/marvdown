# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A stupid simple Markdown library"
license       = "MIT"
srcDir        = "src"
bin           = @["marvdown"]
binDir        = "bin"
installExt    = @["nim"]

# Dependencies

requires "nim >= 2.0.0"
requires "kapsis#head"
requires "denim#head"
requires "jsony#head"
requires "nyml#head"

task napi, "Build Marvdown as a Node.js addon using N-API":
  exec "denim build src/marvdown.nim --cmake -y"