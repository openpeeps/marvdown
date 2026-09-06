# Package

version       = "0.2.3"
author        = "George Lemon"
description   = "A stupid simple Markdown library"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
installDirs   = @["marvdown"]
bin           = @["marvdown"]
binDir        = "bin"

# Dependencies

requires "nim >= 2.0.0"
requires "openparser >= 0.2.0"
requires "kapsis >= 0.4.8"