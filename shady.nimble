version     = "0.1.5"
author      = "Andre von Houck"
description = "Nim to GPU shader language compiler and supporting utilities."
license     = "MIT"

srcDir = "src"

requires "nim >= 1.1.4"
requires "vmath >= 2.0.1"
requires "pixie >= 5.1.0"

task test, "Run Shady's stable CPU and codegen tests":
  exec "nim c -r tests/test_shady.nim"
  exec "nim c -r tests/test_cpu.nim"
  exec "nim c -r tests/test_backends.nim"
