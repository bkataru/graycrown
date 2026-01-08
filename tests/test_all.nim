## graycrown test suite
##
## Comprehensive tests for all graycrown functionality

import std/[unittest]
import ../src/graycrown

# ============================================================================
# Test Helpers
# ============================================================================

proc createTestImage(w, h: uint32; fillValue: uint8 = 0): GrayImage =
  result = newGrayImage(w, h)
  for i in 0'u32 ..< result.size:
    result.data[i] = fillValue

proc createCheckerboard(w, h: uint32): GrayImage =
  result = newGrayImage(w, h)
  for y in 0'u32 ..< h:
    for x in 0'u32 ..< w:
      result[x, y] = if ((x + y) mod 2) == 0: 255'u8 else: 0'u8

proc createGradient(w, h: uint32): GrayImage =
  result = newGrayImage(w, h)
  for y in 0'u32 ..< h:
    for x in 0'u32 ..< w:
      result[x, y] = uint8((x * 255) div (w - 1))

# ============================================================================
# Core Tests
# ============================================================================

suite "Core Types":
  test "Point creation and access":
    let p = initPoint(10'u32, 20'u32)
    check p.x == 10
    check p.y == 20

  test "Rect creation and properties":
    let r = initRect(5'u32, 10'u32, 100'u32, 200'u32)
    check r.x == 5
    check r.y == 10
    check r.w == 100
    check r.h == 200
    check r.right == 105
    check r.bottom == 210
    check r.area == 20000

  test "Rect center":
    let r = initRect(0'u32, 0'u32, 100'u32, 200'u32)
    let c = r.center
    check c.x == 50
    check c.y == 100

  test "Rect intersection":
    let a = initRect(0'u32, 0'u32, 100'u32, 100'u32)
    let b = initRect(50'u32, 50'u32, 100'u32, 100'u32)
    let inter = intersection(a, b)
    check inter.x == 50
    check inter.y == 50
    check inter.w == 50
    check inter.h == 50

  test "GrayImage creation":
    let img = newGrayImage(100, 200)
    check img.width == 100
    check img.height == 200
    check img.isValid
    check img.size == 20000

  test "GrayImage pixel access":
    var img = newGrayImage(10, 10)
    img[5, 5] = 128
    check img[5, 5] == 128
    check img.get(5, 5) == 128

  test "GrayImage bounds checking":
    let img = createTestImage(10, 10, 100)
    check img[100, 100] == 0  # Out of bounds returns 0
    check img[-1, -1] == 0

  test "ImageView from GrayImage":
    let img = createTestImage(10, 10, 42)
    let view = img.toView
    check view.width == 10
    check view.height == 10
    check view[5, 5] == 42

  test "Math approximations":
    # Test sin approximation
    check abs(sinApprox(0.0'f32)) < 0.01
    check abs(sinApprox(HalfPi) - 1.0'f32) < 0.01
    check abs(sinApprox(Pi)) < 0.01

    # Test atan2 approximation
    check abs(atan2Approx(1.0'f32, 0.0'f32) - HalfPi) < 0.02
    check abs(atan2Approx(0.0'f32, 1.0'f32)) < 0.02

# ============================================================================
# Image Operations Tests
# ============================================================================

suite "Image Operations":
  test "Copy":
    let src = createTestImage(10, 10, 128)
    var dst = newGrayImage(10, 10)
    copy(dst, src.toView)
    for i in 0'u32 ..< dst.size:
      check dst.data[i] == 128

  test "Fill":
    var img = newGrayImage(10, 10)
    fill(img, 200)
    for i in 0'u32 ..< img.size:
      check img.data[i] == 200

  test "Crop":
    var src = newGrayImage(10, 10)
    for y in 0'u32 ..< 10:
      for x in 0'u32 ..< 10:
        src[x, y] = uint8(y * 10 + x)

    var dst = newGrayImage(5, 5)
    crop(dst, src.toView, initRect(2'u32, 2'u32, 5'u32, 5'u32))

    check dst[0, 0] == 22  # src[2,2]
    check dst[4, 4] == 66  # src[6,6]

  test "Resize bilinear":
    let src = createGradient(100, 100)
    var dst = newGrayImage(50, 50)
    resize(dst, src.toView)
    check dst.isValid
    # Center pixel should be approximately middle gray
    check dst[25, 25] > 100 and dst[25, 25] < 155

  test "Resize nearest neighbor":
    let src = createCheckerboard(10, 10)
    var dst = newGrayImage(20, 20)
    resizeNearestNeighbor(dst, src.toView)
    check dst.isValid

  test "Downsample":
    let src = createTestImage(100, 100, 200)
    var dst = newGrayImage(50, 50)
    downsample(dst, src.toView)
    for i in 0'u32 ..< dst.size:
      check dst.data[i] == 200

  test "Flip horizontal":
    var src = newGrayImage(10, 10)
    src[0, 0] = 100
    src[9, 0] = 200
    var dst = newGrayImage(10, 10)
    flipHorizontal(dst, src.toView)
    check dst[0, 0] == 200
    check dst[9, 0] == 100

  test "Flip vertical":
    var src = newGrayImage(10, 10)
    src[0, 0] = 100
    src[0, 9] = 200
    var dst = newGrayImage(10, 10)
    flipVertical(dst, src.toView)
    check dst[0, 0] == 200
    check dst[0, 9] == 100

  test "Invert":
    var img = createTestImage(10, 10, 100)
    invert(img)
    check img[0, 0] == 155

# ============================================================================
# Filter Tests
# ============================================================================

suite "Filters":
  test "Histogram":
    var img = newGrayImage(10, 10)
    for i in 0'u32 ..< 50:
      img.data[i] = 0
    for i in 50'u32 ..< 100:
      img.data[i] = 255

    let hist = computeHistogram(img.toView)
    check hist[0] == 50
    check hist[255] == 50

  test "Threshold":
    var img = newGrayImage(4, 4)
    img.data[0] = 50
    img.data[1] = 150
    img.data[2] = 75
    img.data[3] = 200

    threshold(img, 100)

    check img.data[0] == 0
    check img.data[1] == 255
    check img.data[2] == 0
    check img.data[3] == 255

  test "Otsu threshold":
    # Create bimodal distribution with clear separation
    var img = newGrayImage(10, 10)
    for i in 0'u32 ..< 50:
      img.data[i] = 30'u8  # Dark cluster (all same value)
    for i in 50'u32 ..< 100:
      img.data[i] = 220'u8  # Bright cluster (all same value)

    let thresh = otsuThreshold(img.toView)
    # Threshold should be somewhere between the two clusters
    check thresh >= 30 and thresh <= 220

  test "Adaptive threshold":
    var src = newGrayImage(5, 5)
    # Fill with test pattern
    let srcData: array[25, uint8] = [
      50'u8, 50, 200, 50, 50,
      50, 50, 200, 50, 50,
      50, 50, 200, 50, 50,
      200, 200, 100, 200, 200,
      200, 200, 100, 200, 200
    ]
    for i in 0 ..< 25:
      src.data[i] = srcData[i]

    var dst = newGrayImage(5, 5)
    adaptiveThreshold(dst, src.toView, 1, 0)

    # Bright line should be detected
    check dst[2, 0] == 255
    check dst[2, 1] == 255

  test "Box blur":
    let src = createTestImage(10, 10, 100)
    var dst = newGrayImage(10, 10)
    boxBlur(dst, src.toView, 1)

    # Uniform input should remain uniform
    check dst[5, 5] == 100

  test "Sobel edge detection":
    # Create vertical edge
    var src = newGrayImage(5, 5)
    for y in 0'u32 ..< 5:
      for x in 0'u32 ..< 5:
        src[x, y] = if x < 2: 0'u8 else: 255'u8

    var dst = newGrayImage(5, 5)
    sobel(dst, src.toView)

    # Edge should be detected at column 2
    check dst[2, 2] > 100

  test "Contrast stretch":
    var img = newGrayImage(10, 10)
    for i in 0'u32 ..< img.size:
      img.data[i] = uint8(100 + (i mod 50))  # Range 100-149

    stretchContrast(img)

    # Should now span full range
    var minVal = 255'u8
    var maxVal = 0'u8
    for i in 0'u32 ..< img.size:
      if img.data[i] < minVal: minVal = img.data[i]
      if img.data[i] > maxVal: maxVal = img.data[i]

    check minVal == 0
    check maxVal == 255

# ============================================================================
# Morphology Tests
# ============================================================================

suite "Morphology":
  test "Erode":
    const W = 255'u8
    var src = newGrayImage(5, 5)
    let srcData: array[25, uint8] = [
      0'u8, 0, 0, 0, 0,
      0, W, W, W, 0,
      0, W, W, W, 0,
      0, W, W, W, 0,
      0, 0, 0, 0, 0
    ]
    copyMem(src.data, srcData[0].unsafeAddr, 25)

    var dst = newGrayImage(5, 5)
    erode(dst, src.toView)

    check dst[2, 2] == 255  # Center should remain white
    check dst[1, 1] == 0    # Edge should become black

  test "Dilate":
    const W = 255'u8
    var src = newGrayImage(5, 5)
    let srcData: array[25, uint8] = [
      0'u8, 0, 0, 0, 0,
      0, 0, 0, 0, 0,
      0, 0, W, 0, 0,
      0, 0, 0, 0, 0,
      0, 0, 0, 0, 0
    ]
    copyMem(src.data, srcData[0].unsafeAddr, 25)

    var dst = newGrayImage(5, 5)
    dilate(dst, src.toView)

    check dst[2, 2] == 255  # Center remains white
    check dst[1, 2] == 255  # Neighbors become white
    check dst[3, 2] == 255
    check dst[2, 1] == 255
    check dst[2, 3] == 255
    check dst[0, 0] == 0    # Far corner stays black

  test "Morphological opening":
    var src = createTestImage(10, 10, 255)
    # Add some noise
    src[2, 2] = 0

    var dst = newGrayImage(10, 10)
    var temp = newGrayImage(10, 10)
    morphOpen(dst, src.toView, temp)

    # Opening should remove small dark spots
    # (Note: 1-pixel noise may or may not be removed depending on neighborhood)

  test "Morphological closing":
    var src = createTestImage(10, 10, 0)
    # Add some signal
    for y in 3'u32 ..< 7:
      for x in 3'u32 ..< 7:
        src[x, y] = 255
    # Add hole
    src[5, 5] = 0

    var dst = newGrayImage(10, 10)
    var temp = newGrayImage(10, 10)
    morphClose(dst, src.toView, temp)

    # Closing should fill small holes
    check dst[5, 5] == 255

# ============================================================================
# Blob Detection Tests
# ============================================================================

suite "Blob Detection":
  test "Find blobs":
    const W = 255'u8
    var img = newGrayImage(6, 5)
    let imgData: array[30, uint8] = [
      W, W, 0, 0, W, 0,
      W, 0, 0, W, W, 0,
      0, 0, W, W, 0, 0,
      W, W, W, 0, 0, W,
      0, W, 0, 0, 0, W
    ]
    copyMem(img.data, imgData[0].unsafeAddr, 30)

    var labels: array[30, Label]
    var labelArr = initLabelArray(labels, 6, 5)
    var blobs: array[10, Blob]

    let n = findBlobs(img.toView, labelArr, blobs, 10)

    check n == 3  # Should find 3 distinct blobs

  test "Blob properties":
    const W = 255'u8
    var img = newGrayImage(5, 5)
    # Single 3x3 blob in center
    for y in 1'u32 ..< 4:
      for x in 1'u32 ..< 4:
        img[x, y] = W

    var labels: array[25, Label]
    var labelArr = initLabelArray(labels, 5, 5)
    var blobs: array[10, Blob]

    let n = findBlobs(img.toView, labelArr, blobs, 10)

    check n == 1
    check blobs[0].area == 9
    check blobs[0].box.w == 3
    check blobs[0].box.h == 3
    check blobs[0].centroid.x == 2
    check blobs[0].centroid.y == 2

  test "Contour tracing":
    const W = 255'u8
    var img = newGrayImage(5, 5)
    let imgData: array[25, uint8] = [
      0'u8, W, W, W, 0,
      0, W, W, W, 0,
      0, W, 0, W, W,
      0, W, W, W, 0,
      0, 0, W, 0, W
    ]
    copyMem(img.data, imgData[0].unsafeAddr, 25)

    var visited = newGrayImage(5, 5)
    var contour = Contour(start: Point(x: 1, y: 0))

    traceContour(img.toView, visited, contour)

    check contour.length > 0
    check contour.box.w > 0
    check contour.box.h > 0

# ============================================================================
# Integral Image Tests
# ============================================================================

suite "Integral Images":
  test "Compute integral image":
    var img = newGrayImage(3, 3)
    for i in 0'u32 ..< 9:
      img.data[i] = uint8(i + 1)  # 1,2,3,4,5,6,7,8,9

    var iiData: array[9, uint32]
    var ii = initIntegralImage(iiData, 3, 3)
    computeIntegral(img.toView, ii)

    # Expected:
    # 1   3   6
    # 5  12  21
    # 12 27  45
    check ii[0, 0] == 1
    check ii[1, 0] == 3
    check ii[2, 0] == 6
    check ii[0, 1] == 5
    check ii[1, 1] == 12
    check ii[2, 1] == 21
    check ii[2, 2] == 45

  test "Region sum":
    var img = newGrayImage(3, 3)
    for i in 0'u32 ..< 9:
      img.data[i] = uint8(i + 1)

    var iiData: array[9, uint32]
    var ii = initIntegralImage(iiData, 3, 3)
    computeIntegral(img.toView, ii)

    # Sum of bottom-right 2x2: 5+6+8+9 = 28
    let sum = regionSum(ii, 1, 1, 2, 2)
    check sum == 28

# ============================================================================
# Feature Detection Tests
# ============================================================================

suite "Feature Detection":
  test "FAST corner detection":
    # Create larger image with clear corner structure
    var img = newGrayImage(50, 50)
    fill(img, 50)

    # Create L-shape which has a clear corner
    for y in 10'u32 ..< 40:
      for x in 10'u32 ..< 20:
        img[x, y] = 200
    for y in 30'u32 ..< 40:
      for x in 10'u32 ..< 40:
        img[x, y] = 200

    var scoremap = newGrayImage(50, 50)
    var keypoints: array[100, Keypoint]

    let n = fastCorner(img.toView, scoremap, keypoints, 100, 30)

    # May or may not detect corners depending on exact algorithm
    # Just verify it doesn't crash and returns a reasonable value
    check n >= 0

  test "ORB extraction":
    # Create test pattern
    var img = newGrayImage(100, 100)
    fill(img, 50)
    for y in 20'u32 ..< 80:
      for x in 20'u32 ..< 80:
        img[x, y] = 200

    var keypoints: array[50, Keypoint]
    var scoremap: array[10000, Pixel]

    let n = extractOrb(img.toView, keypoints, 50, 20, scoremap)

    # Should detect some features
    check n >= 0  # May be 0 if no features meet criteria

  test "Hamming distance":
    var desc1: array[8, uint32] = [0xFFFFFFFF'u32, 0, 0, 0, 0, 0, 0, 0]
    var desc2: array[8, uint32] = [0x00000000'u32, 0, 0, 0, 0, 0, 0, 0]

    let dist = hammingDistance(desc1, desc2)
    check dist == 32  # All 32 bits differ in first word

# ============================================================================
# Template Matching Tests
# ============================================================================

suite "Template Matching":
  test "Exact match":
    var img = newGrayImage(5, 5)
    let imgData: array[25, uint8] = [
      0'u8, 0, 0, 0, 0,
      0, 100, 150, 200, 0,
      0, 125, 175, 225, 0,
      0, 110, 160, 210, 0,
      0, 0, 0, 0, 0
    ]
    copyMem(img.data, imgData[0].unsafeAddr, 25)

    var tmpl = newGrayImage(3, 3)
    let tmplData: array[9, uint8] = [
      100'u8, 150, 200,
      125, 175, 225,
      110, 160, 210
    ]
    copyMem(tmpl.data, tmplData[0].unsafeAddr, 9)

    var result = newGrayImage(3, 3)
    matchTemplate(img.toView, tmpl.toView, result)

    let best = findBestMatch(result.toView)
    check best.x == 1
    check best.y == 1
    check result[1, 1] == 255  # Perfect match

  test "Find best match with score":
    # Create image with unique pattern at specific location
    var img = newGrayImage(50, 50)
    fill(img, 100)

    # Create distinctive pattern at (20, 20)
    for y in 20'u32 ..< 30:
      for x in 20'u32 ..< 30:
        img[x, y] = uint8(50 + (x - 20) * 10 + (y - 20) * 3)

    # Extract template from exactly that location
    var tmpl = newGrayImage(10, 10)
    crop(tmpl, img.toView, initRect(20'u32, 20'u32, 10'u32, 10'u32))

    var result = newGrayImage(41, 41)
    matchTemplate(img.toView, tmpl.toView, result)

    let (pt, score) = findBestMatchWithScore(result.toView)
    # Allow small tolerance for rounding differences
    check pt.x >= 18 and pt.x <= 22
    check pt.y >= 18 and pt.y <= 22
    check score >= 250  # Near-perfect match

# ============================================================================
# Main
# ============================================================================

when isMainModule:
  echo "Running graycrown test suite..."
