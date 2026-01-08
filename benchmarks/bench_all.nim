## graycrown benchmarks
##
## Comprehensive benchmark suite for all graycrown operations.
## Run with: nim c -d:release -d:danger -r benchmarks/bench_all.nim

import std/[times, strformat, strutils]
import ../src/graycrown
import ../src/graycrown/cascades/frontalface

# ============================================================================
# Benchmark Infrastructure
# ============================================================================

type
  BenchResult = object
    name: string
    iterations: int
    totalTimeMs: float64
    avgTimeMs: float64
    opsPerSec: float64

proc benchmark(name: string; iterations: int; body: proc()) : BenchResult =
  ## Run a benchmark and return results
  let start = cpuTime()
  for i in 0 ..< iterations:
    body()
  let elapsed = cpuTime() - start
  let elapsedMs = elapsed * 1000.0

  result = BenchResult(
    name: name,
    iterations: iterations,
    totalTimeMs: elapsedMs,
    avgTimeMs: elapsedMs / float64(iterations),
    opsPerSec: float64(iterations) / elapsed
  )

proc printResult(r: BenchResult) =
  echo fmt"{r.name:<40} {r.iterations:>8} iters  {r.avgTimeMs:>10.3f} ms/op  {r.opsPerSec:>12.1f} ops/sec"

proc printHeader() =
  echo ""
  echo "=" .repeat(85)
  echo "GRAYCROWN BENCHMARK SUITE"
  echo "=" .repeat(85)
  echo "Benchmark                                   Iters      Avg Time      Throughput"
  echo "-" .repeat(85)

proc printSection(name: string) =
  echo ""
  echo fmt"--- {name} ---"

# ============================================================================
# Test Image Generation
# ============================================================================

proc createBenchImage(w, h: uint32): GrayImage =
  result = newGrayImage(w, h)
  for y in 0'u32 ..< h:
    for x in 0'u32 ..< w:
      # Create a pattern with some variation
      result[x, y] = uint8(((x * 7 + y * 13) mod 256))

proc createNoiseImage(w, h: uint32): GrayImage =
  result = newGrayImage(w, h)
  var seed = 12345'u32
  for i in 0'u32 ..< w * h:
    seed = seed * 1103515245 + 12345
    result.data[i] = uint8((seed shr 16) and 0xFF)

proc createBinaryImage(w, h: uint32): GrayImage =
  result = newGrayImage(w, h)
  for y in 0'u32 ..< h:
    for x in 0'u32 ..< w:
      if ((x div 20) + (y div 20)) mod 2 == 0:
        result[x, y] = 255
      else:
        result[x, y] = 0

# ============================================================================
# Benchmarks
# ============================================================================

proc benchImageOperations() =
  printSection("Image Operations")

  let src = createBenchImage(640, 480)
  var dst = newGrayImage(640, 480)

  # Copy
  printResult benchmark("copy 640x480", 1000, proc() =
    copy(dst, src.toView)
  )

  # Fill
  printResult benchmark("fill 640x480", 1000, proc() =
    fill(dst, 128)
  )

  # Invert
  var img = createBenchImage(640, 480)
  printResult benchmark("invert 640x480", 1000, proc() =
    invert(img)
  )

  # Crop
  var cropDst = newGrayImage(320, 240)
  printResult benchmark("crop 320x240 from 640x480", 1000, proc() =
    crop(cropDst, src.toView, initRect(160'u32, 120'u32, 320'u32, 240'u32))
  )

  # Resize (bilinear)
  var resizeDst = newGrayImage(320, 240)
  printResult benchmark("resize bilinear 640x480 -> 320x240", 500, proc() =
    resize(resizeDst, src.toView)
  )

  # Resize nearest neighbor
  printResult benchmark("resize nearest 640x480 -> 320x240", 1000, proc() =
    resizeNearestNeighbor(resizeDst, src.toView)
  )

  # Downsample
  printResult benchmark("downsample 640x480 -> 320x240", 1000, proc() =
    downsample(resizeDst, src.toView)
  )

  # Flip horizontal
  printResult benchmark("flip horizontal 640x480", 1000, proc() =
    flipHorizontal(dst, src.toView)
  )

  # Flip vertical
  printResult benchmark("flip vertical 640x480", 1000, proc() =
    flipVertical(dst, src.toView)
  )

  freeGrayImage(dst)
  freeGrayImage(cropDst)
  freeGrayImage(resizeDst)

proc benchFilters() =
  printSection("Filters")

  let src = createBenchImage(640, 480)
  var dst = newGrayImage(640, 480)

  # Histogram
  printResult benchmark("histogram 640x480", 1000, proc() =
    discard computeHistogram(src.toView)
  )

  # Threshold
  var img = createBenchImage(640, 480)
  printResult benchmark("threshold 640x480", 1000, proc() =
    threshold(img, 128)
  )

  # Otsu threshold
  printResult benchmark("otsu threshold 640x480", 500, proc() =
    discard otsuThreshold(src.toView)
  )

  # Adaptive threshold (slow O(n²×r²) implementation - use fewer iterations)
  printResult benchmark("adaptive threshold 640x480", 5, proc() =
    adaptiveThreshold(dst, src.toView, 5, 10)
  )

  # Box blur
  printResult benchmark("box blur r=1 640x480", 200, proc() =
    boxBlur(dst, src.toView, 1)
  )

  printResult benchmark("box blur r=3 640x480", 100, proc() =
    boxBlur(dst, src.toView, 3)
  )

  # Sobel
  printResult benchmark("sobel 640x480", 200, proc() =
    sobel(dst, src.toView)
  )

  # Contrast stretch
  var stretchImg = createBenchImage(640, 480)
  printResult benchmark("stretch contrast 640x480", 500, proc() =
    stretchContrast(stretchImg)
  )

  freeGrayImage(dst)
  freeGrayImage(stretchImg)

proc benchMorphology() =
  printSection("Morphology")

  let src = createBinaryImage(640, 480)
  var dst = newGrayImage(640, 480)
  var temp = newGrayImage(640, 480)

  # Erode
  printResult benchmark("erode 640x480", 200, proc() =
    erode(dst, src.toView)
  )

  # Dilate
  printResult benchmark("dilate 640x480", 200, proc() =
    dilate(dst, src.toView)
  )

  # Opening
  printResult benchmark("morph open 640x480", 100, proc() =
    morphOpen(dst, src.toView, temp)
  )

  # Closing
  printResult benchmark("morph close 640x480", 100, proc() =
    morphClose(dst, src.toView, temp)
  )

  freeGrayImage(dst)
  freeGrayImage(temp)

proc benchBlobs() =
  printSection("Blob Detection")

  let src = createBinaryImage(640, 480)
  var labels: array[640 * 480, Label]
  var labelArr = initLabelArray(labels, 640, 480)
  var blobs: array[1000, Blob]

  printResult benchmark("findBlobs 640x480", 50, proc() =
    discard findBlobs(src.toView, labelArr, blobs, 1000)
  )

proc benchIntegral() =
  printSection("Integral Images")

  let src = createBenchImage(640, 480)
  var iiData: array[640 * 480, uint32]
  var ii = initIntegralImage(iiData, 640, 480)

  printResult benchmark("compute integral 640x480", 500, proc() =
    computeIntegral(src.toView, ii)
  )

  # Pre-compute for region sum benchmark
  computeIntegral(src.toView, ii)

  printResult benchmark("region sum (10000 queries)", 100, proc() =
    for i in 0 ..< 10000:
      discard regionSum(ii, uint32(i mod 600), uint32(i mod 400), 40, 40)
  )

proc benchFeatures() =
  printSection("Feature Detection")

  let src = createBenchImage(640, 480)
  var scoremap = newGrayImage(640, 480)
  var keypoints: array[500, Keypoint]
  var scoremapData: array[640 * 480, Pixel]

  printResult benchmark("FAST corners 640x480", 50, proc() =
    discard fastCorner(src.toView, scoremap, keypoints, 500, 20)
  )

  printResult benchmark("ORB extraction 640x480", 20, proc() =
    discard extractOrb(src.toView, keypoints, 500, 20, scoremapData)
  )

  # Hamming distance
  var desc1: array[8, uint32] = [0xAAAAAAAA'u32, 0x55555555'u32, 0'u32, 0'u32, 0'u32, 0'u32, 0'u32, 0'u32]
  var desc2: array[8, uint32] = [0x55555555'u32, 0xAAAAAAAA'u32, 0'u32, 0'u32, 0'u32, 0'u32, 0'u32, 0'u32]

  printResult benchmark("hamming distance (100000 pairs)", 10, proc() =
    for i in 0 ..< 100000:
      discard hammingDistance(desc1, desc2)
  )

  freeGrayImage(scoremap)

proc benchTemplateMatch() =
  printSection("Template Matching")

  let src = createBenchImage(640, 480)
  var tmpl = newGrayImage(32, 32)
  for y in 0'u32 ..< 32:
    for x in 0'u32 ..< 32:
      tmpl[x, y] = uint8(((x * 7 + y * 13) mod 256))

  var result = newGrayImage(609, 449)  # 640-32+1, 480-32+1

  printResult benchmark("template match 32x32 in 640x480", 10, proc() =
    matchTemplate(src.toView, tmpl.toView, result)
  )

  # Find best match
  matchTemplate(src.toView, tmpl.toView, result)
  printResult benchmark("find best match 609x449", 500, proc() =
    discard findBestMatch(result.toView)
  )

  freeGrayImage(tmpl)
  freeGrayImage(result)

proc benchLbp() =
  printSection("LBP Detection")

  let src = createBenchImage(320, 240)
  var iiData: array[320 * 240, uint32]
  var ii = initIntegralImage(iiData, 320, 240)
  computeIntegral(src.toView, ii)

  let cascade = initFrontalfaceCascade()
  var rects: array[100, Rect]

  # Single window evaluation
  printResult benchmark("LBP evaluate window (1000 evals)", 100, proc() =
    for i in 0 ..< 1000:
      discard lbpEvaluateWindow(cascade, ii, 10, 10, 1.0)
  )

  # Full detection (small image for benchmark)
  let smallSrc = createBenchImage(160, 120)
  var smallIiData: array[160 * 120, uint32]
  var smallIi = initIntegralImage(smallIiData, 160, 120)
  computeIntegral(smallSrc.toView, smallIi)

  printResult benchmark("LBP detect 160x120", 20, proc() =
    discard lbpDetect(cascade, smallIi, rects, 100, step=2)
  )

  printResult benchmark("LBP detect with NMS 160x120", 20, proc() =
    discard lbpDetectWithNMS(cascade, smallIi, rects, 100)
  )

proc benchLargeImage() =
  printSection("Large Image Operations (1920x1080)")

  let src = createBenchImage(1920, 1080)
  var dst = newGrayImage(1920, 1080)

  printResult benchmark("copy 1920x1080", 200, proc() =
    copy(dst, src.toView)
  )

  printResult benchmark("box blur r=1 1920x1080", 50, proc() =
    boxBlur(dst, src.toView, 1)
  )

  printResult benchmark("sobel 1920x1080", 50, proc() =
    sobel(dst, src.toView)
  )

  # Use heap allocation to avoid stack overflow (8+ MB would exceed Windows 1MB stack)
  var iiData = cast[ptr UncheckedArray[uint32]](alloc(1920 * 1080 * sizeof(uint32)))
  var ii = IntegralImage(data: iiData, width: 1920, height: 1080)

  printResult benchmark("compute integral 1920x1080", 100, proc() =
    computeIntegral(src.toView, ii)
  )

  dealloc(iiData)
  freeGrayImage(dst)

# ============================================================================
# Main
# ============================================================================

when isMainModule:
  printHeader()

  benchImageOperations()
  benchFilters()
  benchMorphology()
  benchBlobs()
  benchIntegral()
  benchFeatures()
  benchTemplateMatch()
  benchLbp()
  benchLargeImage()

  echo ""
  echo "=" .repeat(85)
  echo "Benchmark complete."
  echo ""
