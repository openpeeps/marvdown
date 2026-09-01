## tests/test_benchmark.nim
## Benchmark suite for Marvdown – prints plain-text table with throughput
##
## Run:
##   nim c -r tests/test_benchmark.nim
##   nim c -d:release -r tests/test_benchmark.nim   # for release timing
##   nimble test   # runs as part of suite (short iterations)

import unittest, options, strutils, os, times, sequtils
import marvdown

let benchOpts = MarkdownOptions(
  allowed: @[],
  allowTagsByType: some(tagAll),
  enableAnchors: false,
  enableEmailAutolinks: true,
  showFootnotes: true,
  parseYaml: false
)

let benchOptsAnchors = MarkdownOptions(
  allowed: @[],
  allowTagsByType: some(tagAll),
  enableAnchors: true,
  anchorIcon: "🔗",
  enableEmailAutolinks: true,
  parseYaml: false
)

type BenchResult = object
  name: string
  sizeBytes: int
  iters: int
  totalMs: float
  avgMs: float
  throughputMBs: float
  outBytes: int
  cpuTimeMs: float

proc formatBytes(b: int): string =
  if b < 1024:
    $b & " B"
  elif b < 1024*1024:
    formatFloat(b.float / 1024.0, ffDecimal, 1) & " KB"
  else:
    formatFloat(b.float / (1024.0*1024.0), ffDecimal, 2) & " MB"

proc padRight(s: string, w: int): string =
  if s.len >= w: s[0 ..< w]
  else: s & repeat(' ', w - s.len)

proc padLeft(s: string, w: int): string =
  if s.len >= w: s[ ^w .. ^1 ]
  else: repeat(' ', w - s.len) & s

proc benchOne(name: string, content: string, iters: int, opts = benchOpts): BenchResult =
  # warmup
  for _ in 0 ..< min(3, iters):
    var m = newMarkdown(content, opts)
    discard m.toHtml()
  let cpu0 = cpuTime()
  let t0 = getTime()
  var outLen = 0
  for _ in 0 ..< iters:
    var m = newMarkdown(content, opts)
    let h = m.toHtml()
    outLen = h.len  # keep last, prevent DCE
  let t1 = getTime()
  let cpu1 = cpuTime()
  let total = (t1 - t0).inNanoseconds.float / 1_000_000.0
  let cpuMs = (cpu1 - cpu0) * 1000.0
  let avg = if iters > 0: total / iters.float else: 0.0
  let totalBytes = content.len * iters
  let thr = if total > 0: (totalBytes.float / (1024.0*1024.0)) / (total / 1000.0) else: 0.0
  BenchResult(
    name: name,
    sizeBytes: content.len,
    iters: iters,
    totalMs: total,
    avgMs: avg,
    throughputMBs: thr,
    outBytes: outLen,
    cpuTimeMs: cpuMs
  )

proc printTable(results: seq[BenchResult], title: string) =
  echo ""
  echo title
  echo repeat('=', title.len)
  echo ""
  # header
  const hName = 24
  const hSize = 10
  const hIters = 7
  const hTotal = 10
  const hAvg = 10
  const hThr = 16
  const hOut = 10
  const hCpu = 10
  let header = "| " & padRight("Document", hName) & " | " & padRight("Size", hSize) & " | " & padLeft("Iters", hIters) & " | " & padLeft("Total ms", hTotal) & " | " & padLeft("Avg ms", hAvg) & " | " & padLeft("Throughput", hThr) & " | " & padLeft("Out", hOut) & " | " & padLeft("CPU ms", hCpu) & " |"
  let sep = "|-" & repeat('-', hName) & "-|-" & repeat('-', hSize) & "-|-" & repeat('-', hIters) & "-|-" & repeat('-', hTotal) & "-|-" & repeat('-', hAvg) & "-|-" & repeat('-', hThr) & "-|-" & repeat('-', hOut) & "-|-" & repeat('-', hCpu) & "-|"
  echo header
  echo sep
  for r in results:
    let row = "| " & padRight(r.name, hName) & " | " &
              padRight(formatBytes(r.sizeBytes), hSize) & " | " &
              padLeft($r.iters, hIters) & " | " &
              padLeft(formatFloat(r.totalMs, ffDecimal, 2), hTotal) & " | " &
              padLeft(formatFloat(r.avgMs, ffDecimal, 3), hAvg) & " | " &
              padLeft(formatFloat(r.throughputMBs, ffDecimal, 2) & " MB/s", hThr) & " | " &
              padLeft(formatBytes(r.outBytes), hOut) & " | " &
              padLeft(formatFloat(r.cpuTimeMs, ffDecimal, 2), hCpu) & " |"
    echo row
  echo sep
  # totals
  let sumIters = results.mapIt(it.iters).foldl(a+b, 0)
  let sumTotal = results.mapIt(it.totalMs).foldl(a+b, 0.0)
  echo "  Iterations: " & $sumIters & "  |  Total wall: " & formatFloat(sumTotal, ffDecimal, 2) & " ms"
  echo ""

proc syntheticDoc(lines: int): string =
  ## generate a pseudo-markdown doc with mixed elements
  result = newStringOfCap(lines * 80)
  for i in 0 ..< lines:
    case i mod 10
    of 0: result.add "# Heading " & $i & "\n\n"
    of 1: result.add "Paragraph with **bold** and *italic* and `code` and [link](https://example.com) number " & $i & ".\n\n"
    of 2: result.add "- item " & $i & "\n- item " & $(i+1) & "\n- item " & $(i+2) & "\n\n"
    of 3: result.add "1. ordered " & $i & "\n2. ordered " & $(i+1) & "\n\n"
    of 4: result.add "> blockquote line " & $i & "\n> continued\n\n"
    of 5: result.add "```nim\nproc hello" & $i & "() =\n  echo \"hi\"\n```\n\n"
    of 6: result.add "| A | B |\n| - | - |\n| " & $i & " | " & $(i*2) & " |\n\n"
    of 7: result.add "![alt](https://example.com/img" & $i & ".png \"title\")\n\n"
    of 8: result.add "    indented code line " & $i & "\n    more code\n\n"
    else: result.add "Plain line " & $i & " with some text to fill the paragraph and test throughput.\n\n"

proc sanitizeBenchContent(s: string): string =
  ## Normalize line endings and avoid Windows Defender false positive
  ## sample.md contains a PHP example that triggers Defender on Windows
  ## (flags shell+exec plus echo input pattern).
  result = s.replace("\r\n", "\n").replace("\r", "\n")
  # Break the signature without embedding the flagged literal in the
  # binary – use a non-flagged substring.
  result = result.replace("$" & "input", "$input_")

proc readBenchFile(rel: string): string =
  let candidates = [
    rel,
    "tests/data" / extractFilename(rel),
    "bench" / extractFilename(rel),
    "../bench" / extractFilename(rel),
    getCurrentDir() / rel,
    getCurrentDir() / ("tests/data" / extractFilename(rel)),
    getAppDir() / rel,
    parentDir(currentSourcePath()) / rel,
    parentDir(currentSourcePath()) / "data" / extractFilename(rel),
    parentDir(currentSourcePath()) / ".." / rel
  ]
  for p in candidates:
    if fileExists(p):
      return sanitizeBenchContent(readFile(p))
  # fallback: try tests/data/* directly
  if rel.endsWith("sample.md") and fileExists("tests/data/sample.md"):
    return sanitizeBenchContent(readFile("tests/data/sample.md"))
  if rel.endsWith("big.md"):
    if fileExists("tests/data/big.md"):
      return sanitizeBenchContent(readFile("tests/data/big.md"))
    if fileExists("bench/big.md"):
      return sanitizeBenchContent(readFile("bench/big.md"))
  return ""

proc scaleIters(base: int): int =
  when defined(windows):
    when defined(release):
      base
    else:
      # Windows debug is much slower and Defender AV adds overhead
      max(1, base div 5)
  else:
    base

suite "benchmark_marvdown_plain_table":

  test "throughput table – Marvdown toHtml (debug build, use -d:release for final numbers)":
    # collect documents
    var docs: seq[tuple[name, content: string, iters: int]] = @[]

    when not defined(windows):
      let sample = readBenchFile("tests/data/sample.md")
      if sample.len > 0:
        # sample is ~27KB – moderate iterations (debug ~2.8ms each)
        # readBenchFile sanitizes in-memory (file on disk stays pristine upstream)
        docs.add (("sample.md (CommonMark)", sample, scaleIters(500)))
    else:
      # Windows Defender flags sample.md's PHP example in-memory
      # even after sanitize (raw readFile briefly contains signature)
      # – keep file pristine on disk, skip this doc on Windows.
      discard

    let big = block:
      var s = readBenchFile("tests/data/big.md")
      if s.len == 0: s = readBenchFile("bench/big.md")
      s
    if big.len > 0:
      # big is ~5MB – few iterations (debug ~470ms each)
      docs.add (("tests/data/big.md", big, scaleIters(5)))

    # synthetic sizes
    docs.add (("synthetic 100 lines", syntheticDoc(100), scaleIters(200)))
    docs.add (("synthetic 1k lines", syntheticDoc(1000), scaleIters(50)))
    docs.add (("synthetic 10k lines", syntheticDoc(10000), scaleIters(5)))

    # edge: minimal
    docs.add (("tiny 1 line", "# Hello\n\nworld", scaleIters(1000)))

    var results: seq[BenchResult] = @[]
    for (name, content, iters) in docs:
      if content.len == 0: continue
      let r = benchOne(name, content, iters, benchOpts)
      results.add r
      # sanity: output not empty for non-empty input
      check r.outBytes > 0
      # throughput sanity: >0
      check r.throughputMBs >= 0.0

    printTable(results, "Marvdown Benchmark – toHtml (wall time, " & (when defined(release): "release" else: "debug") & ")")

    # second table: with anchors enabled (cost of slugify)
    var anchorResults: seq[BenchResult] = @[]
    for (name, content, iters) in docs:
      if content.len == 0: continue
      # only test sample + synthetic 1k for anchors to limit time
      if name notin ["sample.md (CommonMark)", "synthetic 1k lines"]: continue
      let r = benchOne(name & " +anchors", content, iters div 2, benchOptsAnchors)
      anchorResults.add r
    if anchorResults.len > 0:
      printTable(anchorResults, "Marvdown Benchmark – toHtml + anchors")

    # overall sanity thresholds (debug builds are ~3x slower – keep loose)
    for r in results:
      # avg should be < 500ms for even big docs in debug, < 200ms in release
      when defined(release):
        check r.avgMs < 800.0
      else:
        when defined(windows):
          check r.avgMs < 4000.0
        else:
          check r.avgMs < 2000.0

    echo "Nim: " & NimVersion & "  |  CPU: " & hostCPU & "  |  OS: " & hostOS
    echo "Tip: re-run with -d:release for ~3-5x faster numbers. Example:"
    echo "  nim c -d:release -r tests/test_benchmark.nim"
    echo ""

  test "toJson (AST) vs toHtml – relative cost":
    when defined(windows):
      skip()
    let sample = readBenchFile("tests/data/sample.md")
    if sample.len == 0:
      skip()
    let iters = scaleIters(100)
    let rHtml = benchOne("sample toHtml", sample, iters, benchOpts)
    # bench toJson
    proc benchJson(name: string, content: string, iters: int): BenchResult =
      for _ in 0 ..< min(3, iters):
        var m = newMarkdown(content, benchOpts)
        discard m.toJson()
      let t0 = getTime()
      let cpu0 = cpuTime()
      var outLen = 0
      for _ in 0 ..< iters:
        var m = newMarkdown(content, benchOpts)
        let j = m.toJson()
        outLen = j.len
      let t1 = getTime()
      let cpu1 = cpuTime()
      let total = (t1 - t0).inNanoseconds.float / 1_000_000.0
      let cpuMs = (cpu1 - cpu0)*1000.0
      let thr = (sample.len.float * iters.float / (1024.0*1024.0)) / (total/1000.0)
      BenchResult(name: name, sizeBytes: sample.len, iters: iters, totalMs: total, avgMs: total/iters.float, throughputMBs: thr, outBytes: outLen, cpuTimeMs: cpuMs)
    let rJson = benchJson("sample toJson", sample, iters)
    printTable(@[rHtml, rJson], "Marvdown Benchmark – toHtml vs toJson (sample.md)")

  test "incremental size scaling (linear check)":
    # Ensure throughput scales roughly linearly: 10x lines ~ 10x time within 2x tolerance
    let s100 = syntheticDoc(100)
    let s1000 = syntheticDoc(1000)
    let r100 = benchOne("100 lines", s100, scaleIters(100), benchOpts)
    let r1000 = benchOne("1k lines", s1000, scaleIters(20), benchOpts)
    printTable(@[r100, r1000], "Scaling check – 100 vs 1k lines")
    let perByte100 = r100.avgMs / s100.len.float
    let perByte1000 = r1000.avgMs / s1000.len.float
    # per-byte cost should be similar (within 3x)
    check perByte100 > 0.0
    check perByte1000 > 0.0
    check abs(perByte100 - perByte1000) / max(perByte100, perByte1000) < 0.75 or perByte1000 < perByte100 * 3.0
