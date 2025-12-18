# Package

version       = "0.1.0"
author        = "bkataru"
description   = "A zero-dependency grayscale image processing library for embedded systems - Nim port of grayskull"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "Run all tests":
  exec "nim c -r tests/test_all.nim"

task testRelease, "Run all tests in release mode":
  exec "nim c -d:release -r tests/test_all.nim"

task testEmbedded, "Run tests with no-stdlib mode (embedded)":
  exec "nim c -d:release -d:knullNoStdlib -r tests/test_embedded.nim"

task docs, "Generate documentation":
  exec "nim doc --project --index:on --outdir:docs src/knull.nim"

task example, "Run the basic example":
  exec "nim c -r examples/basic_usage.nim"

task bench, "Run benchmarks":
  exec "nim c -d:release -d:danger -r benchmarks/bench_all.nim"

# Build options for embedded targets
when defined(knullNoStdlib):
  switch("gc", "none")
  switch("define", "useMalloc")
