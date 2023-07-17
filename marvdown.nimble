# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "This is Marv, a stupid simple Markdown parser that writes HTML or JSON"
license       = "MIT"
srcDir        = "src"
bin           = @["marvdown"]
binDir        = "bin"

# Dependencies

requires "nim >= 1.6.0"
requires "toktok"
requires "kapsis"