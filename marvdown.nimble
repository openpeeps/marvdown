# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A stupid simple Markdown library"
license       = "MIT"
srcDir        = "src"
bin          = @["marvdown"]
binDir       = "bin"

# Dependencies

requires "nim >= 2.0.0"
requires "openparser >= 0.1.2"
requires "kapsis"