## graycrown embedded mode test
##
## Tests that the library works without stdlib
## Compile with: nim c -d:graycrownNoStdlib -d:release tests/test_embedded.nim

when not defined(graycrownNoStdlib):
  {.error: "This test must be compiled with -d:graycrownNoStdlib".}

import ../src/graycrown/core
import ../src/graycrown/image
import ../src/graycrown/filters
import ../src/graycrown/morph
import ../src/graycrown/blobs
import ../src/graycrown/integral

# Static buffers for embedded operation
var
  imageBuffer1: array[100 * 100, Pixel]
  imageBuffer2: array[100 * 100, Pixel]
  labelBuffer: array[100 * 100, Label]
  integralBuffer: array[100 * 100, uint32]
  blobBuffer: array[20, Blob]

proc testCore() =
  # Test point
  let p = initPoint(10'u32, 20'u32)
  assert p.x == 10
  assert p.y == 20

  # Test rect
  let r = initRect(0'u32, 0'u32, 100'u32, 100'u32)
  assert r.area == 10000

  # Test math
  assert abs(sinApprox(0.0'f32)) < 0.01
  assert abs(cosApprox(0.0'f32) - 1.0'f32) < 0.01

proc testImage() =
  # Create image from static buffer
  var img = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer1[0]),
    100, 100
  )

  assert img.isValid
  assert img.width == 100
  assert img.height == 100

  # Fill with value
  for i in 0'u32 ..< img.size:
    img.data[i] = 128

  assert img[50, 50] == 128

  # Copy
  var dst = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer2[0]),
    100, 100
  )
  copy(dst, img.toView)
  assert dst[50, 50] == 128

proc testFilters() =
  var img1 = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer1[0]),
    10, 10
  )
  var img2 = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer2[0]),
    10, 10
  )

  # Create gradient
  for y in 0'u32 ..< 10:
    for x in 0'u32 ..< 10:
      img1[x, y] = uint8(x * 25)

  # Test blur
  boxBlur(img2, img1.toView, 1)

  # Test threshold
  for i in 0'u32 ..< img1.size:
    img1.data[i] = if i < 50: 50'u8 else: 200'u8
  let thresh = otsuThreshold(img1.toView)
  # Threshold should be between the two clusters (inclusive of boundaries is ok)
  assert thresh >= 50 and thresh <= 200

  threshold(img1, thresh)
  # After thresholding, dark values should be 0 and bright should be 255
  # (as long as thresh is strictly between 50 and 200, or equals one boundary)
  assert img1.data[0] == 0 or thresh == 50
  assert img1.data[99] == 255 or thresh == 200

proc testMorph() =
  var img1 = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer1[0]),
    10, 10
  )
  var img2 = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer2[0]),
    10, 10
  )

  # Clear
  for i in 0'u32 ..< 100:
    img1.data[i] = 0

  # Create small white square
  for y in 3'u32 ..< 7:
    for x in 3'u32 ..< 7:
      img1[x, y] = 255

  # Erode
  erode(img2, img1.toView)
  assert img2[5, 5] == 255  # Center still white

  # Dilate back
  dilate(img1, img2.toView)

proc testIntegral() =
  var img = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer1[0]),
    10, 10
  )

  # Fill with 1s
  for i in 0'u32 ..< img.size:
    img.data[i] = 1

  var ii = initIntegralImage(
    cast[ptr UncheckedArray[uint32]](addr integralBuffer[0]),
    10, 10
  )
  computeIntegral(img.toView, ii)

  # Full sum should be 100
  assert ii[9, 9] == 100

  # Region sum of 5x5 in corner
  let sum = regionSum(ii, 0, 0, 5, 5)
  assert sum == 25

proc testBlobs() =
  var img = initGrayImage(
    cast[ptr UncheckedArray[Pixel]](addr imageBuffer1[0]),
    10, 10
  )

  # Clear
  for i in 0'u32 ..< 100:
    img.data[i] = 0

  # Create blob
  for y in 2'u32 ..< 5:
    for x in 2'u32 ..< 5:
      img[x, y] = 255

  var labels = initLabelArray(
    cast[ptr UncheckedArray[Label]](addr labelBuffer[0]),
    10, 10
  )

  let n = findBlobs(img.toView, labels, blobBuffer, 20)
  assert n == 1
  assert blobBuffer[0].area == 9

# Main test runner
proc main() =
  testCore()
  testImage()
  testFilters()
  testMorph()
  testIntegral()
  testBlobs()

main()
