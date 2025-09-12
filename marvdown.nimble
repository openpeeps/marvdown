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
requires "kapsis"
requires "denim"
requires "jsony"

import os, strutils