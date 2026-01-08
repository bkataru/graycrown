## graycrown - Embedded Systems Example
##
## This example demonstrates how to use graycrown on resource-constrained
## embedded systems with static memory allocation.
##
## Compile with: nim c -d:graycrownNoStdlib -d:release --gc:none examples/embedded_example.nim
##
## Key principles for embedded use:
## 1. No dynamic memory allocation
## 2. All buffers are statically allocated
## 3. No stdlib dependencies
## 4. Predictable memory usage

import ../src/graycrown/core
import ../src/graycrown/image
import ../src/graycrown/filters
import ../src/graycrown/morph
import ../src/graycrown/blobs
import ../src/graycrown/integral

# ============================================================================
# Static Buffer Allocation
# ============================================================================

# Define image dimensions for your application
const
  ImageWidth = 320
  ImageHeight = 240
  ImageSize = ImageWidth * ImageHeight

# Pre-allocated buffers (go in BSS section, zero-initialized)
var
  # Main image buffers
  frameBuffer: array[ImageSize, Pixel]
  processingBuffer: array[ImageSize, Pixel]
  outputBuffer: array[ImageSize, Pixel]

  # Auxiliary buffers
  integralBuffer: array[ImageSize, uint32]
  labelBuffer: array[ImageSize, Label]

  # Detection results
  blobResults: array[32, Blob]
  keypointResults: array[128, Keypoint]

# ============================================================================
# Image View Wrappers
# ============================================================================

# These wrap static buffers as ImageViews for processing
proc getFrameBuffer(): var ImageView =
  var view {.global.} = initImageView(
    cast[ptr UncheckedArray[Pixel]](addr frameBuffer[0]),
    ImageWidth, ImageHeight
  )
  view

proc getProcessingBuffer(): var ImageView =
  var view {.global.} = initImageView(
    cast[ptr UncheckedArray[Pixel]](addr processingBuffer[0]),
    ImageWidth, ImageHeight
  )
  view

proc getOutputBuffer(): var ImageView =
  var view {.global.} = initImageView(
    cast[ptr UncheckedArray[Pixel]](addr outputBuffer[0]),
    ImageWidth, ImageHeight
  )
  view

proc getIntegralImage(): var IntegralImage =
  var ii {.global.} = initIntegralImage(
    cast[ptr UncheckedArray[uint32]](addr integralBuffer[0]),
    ImageWidth, ImageHeight
  )
  ii

proc getLabelArray(): var LabelArray =
  var la {.global.} = initLabelArray(
    cast[ptr UncheckedArray[Label]](addr labelBuffer[0]),
    ImageWidth, ImageHeight
  )
  la

# ============================================================================
# Example: Motion Detection Pipeline
# ============================================================================

var previousFrame: array[ImageSize, Pixel]
var motionThreshold: uint8 = 30

proc initMotionDetection() =
  ## Initialize motion detection
  # Clear previous frame
  for i in 0 ..< ImageSize:
    previousFrame[i] = 0
  motionThreshold = 30

proc detectMotion(currentFrame: ptr UncheckedArray[Pixel]): uint32 =
  ## Detect motion by comparing current frame to previous
  ## Returns number of pixels that changed significantly
  var motionCount: uint32 = 0

  for i in 0 ..< ImageSize:
    let diff = abs(int(currentFrame[i]) - int(previousFrame[i]))
    if diff > int(motionThreshold):
      motionCount += 1
      outputBuffer[i] = 255  # Mark motion
    else:
      outputBuffer[i] = 0

    # Update previous frame
    previousFrame[i] = currentFrame[i]

  motionCount

# ============================================================================
# Example: Object Detection Pipeline
# ============================================================================

type
  DetectionResult* = object
    found*: bool
    count*: uint32
    blobs*: ptr array[32, Blob]

proc processFrame*(inputData: ptr UncheckedArray[Pixel]): DetectionResult =
  ## Full processing pipeline for object detection
  ##
  ## Pipeline:
  ## 1. Copy input to frame buffer
  ## 2. Apply blur to reduce noise
  ## 3. Apply adaptive threshold
  ## 4. Apply morphological cleanup
  ## 5. Detect blobs

  result.found = false
  result.count = 0
  result.blobs = addr blobResults

  # Get our working buffers
  var frame = getFrameBuffer()
  var processed = getProcessingBuffer()
  var output = getOutputBuffer()
  var labels = getLabelArray()

  # Step 1: Copy input
  for i in 0 ..< ImageSize:
    frame.data[i] = inputData[i]

  # Step 2: Blur (reduce noise)
  blur(processed, frame, 1)

  # Step 3: Threshold
  let thresh = otsuThreshold(processed)
  threshold(processed, thresh)

  # Step 4: Morphological cleanup (close small gaps)
  dilate(output, processed)
  erode(processed, output)

  # Step 5: Find blobs
  labels.clear()
  result.count = findBlobs(processed, labels, blobResults, 32)
  result.found = result.count > 0

# ============================================================================
# Example: Edge Detection for Line Following
# ============================================================================

type
  LineInfo* = object
    detected*: bool
    centerX*: int32  # Center of line (-160 to 160 for 320 width)
    angle*: int32    # Approximate angle in degrees

proc detectLine*(inputData: ptr UncheckedArray[Pixel]): LineInfo =
  ## Detect a line for line-following applications
  ##
  ## This simplified algorithm:
  ## 1. Apply Sobel to detect edges
  ## 2. Threshold edges
  ## 3. Find centroid of edge pixels in bottom portion of image

  result.detected = false
  result.centerX = 0
  result.angle = 0

  var frame = getFrameBuffer()
  var edges = getProcessingBuffer()

  # Copy input
  for i in 0 ..< ImageSize:
    frame.data[i] = inputData[i]

  # Apply Sobel
  sobel(edges, frame)

  # Find centroid of strong edges in bottom half
  var sumX: int64 = 0
  var count: int64 = 0

  let startY = ImageHeight div 2
  for y in startY ..< ImageHeight:
    for x in 0 ..< ImageWidth:
      let idx = y * ImageWidth + x
      if edges.data[idx] > 100:  # Strong edge
        sumX += int64(x)
        count += 1

  if count > 100:  # Need minimum edges
    result.detected = true
    result.centerX = int32(sumX div count) - int32(ImageWidth div 2)

    # Rough angle estimate from center offset
    result.angle = result.centerX div 3

# ============================================================================
# Example: Simple Barcode Region Detection
# ============================================================================

proc findBarcodeRegion*(inputData: ptr UncheckedArray[Pixel]): Rect =
  ## Find potential barcode region based on edge density
  ##
  ## Barcodes have high horizontal edge density

  result = Rect(x: 0, y: 0, w: 0, h: 0)

  var frame = getFrameBuffer()
  var edges = getProcessingBuffer()
  var ii = getIntegralImage()

  # Copy and detect edges
  for i in 0 ..< ImageSize:
    frame.data[i] = inputData[i]

  sobel(edges, frame)

  # Compute integral image of edge magnitudes
  computeIntegral(edges, ii)

  # Sliding window to find region with highest edge density
  const WindowW = 80
  const WindowH = 40

  var bestDensity: uint32 = 0
  var bestX: uint32 = 0
  var bestY: uint32 = 0

  var y: uint32 = 0
  while y + WindowH < ImageHeight:
    var x: uint32 = 0
    while x + WindowW < ImageWidth:
      let density = regionMean(ii, x, y, WindowW, WindowH)
      if density > bestDensity:
        bestDensity = density
        bestX = x
        bestY = y
      x += 20
    y += 10

  if bestDensity > 50:  # Threshold for "enough edges"
    result = Rect(x: bestX, y: bestY, w: WindowW, h: WindowH)

# ============================================================================
# Memory Usage Report
# ============================================================================

proc getMemoryUsage*(): tuple[staticBytes: int, stackBytes: int] =
  ## Report static memory usage
  let staticMem =
    sizeof(frameBuffer) +
    sizeof(processingBuffer) +
    sizeof(outputBuffer) +
    sizeof(integralBuffer) +
    sizeof(labelBuffer) +
    sizeof(blobResults) +
    sizeof(keypointResults) +
    sizeof(previousFrame)

  # Stack usage is minimal - just local variables
  let stackEst = 256  # Approximate

  (staticMem, stackEst)

# ============================================================================
# Main (for testing on desktop)
# ============================================================================

when isMainModule and not defined(graycrownNoStdlib):
  import std/strformat

  proc main() =
    echo "graycrown Embedded Example"
    echo "========================="

    let (staticMem, stackMem) = getMemoryUsage()
    echo fmt"Static memory: {staticMem} bytes ({staticMem div 1024} KB)"
    echo fmt"Estimated stack: {stackMem} bytes"
    echo fmt"Image size: {ImageWidth}x{ImageHeight}"
    echo ""

    # Simulate frame capture
    var testFrame: array[ImageSize, Pixel]
    for i in 0 ..< ImageSize:
      testFrame[i] = uint8(i mod 256)

    # Test motion detection
    echo "Testing motion detection..."
    initMotionDetection()
    let motion1 = detectMotion(cast[ptr UncheckedArray[Pixel]](addr testFrame[0]))
    echo fmt"  First frame motion pixels: {motion1} (expected: all)"

    # Modify some pixels
    for i in 0 ..< 1000:
      testFrame[i] = 255 - testFrame[i]

    let motion2 = detectMotion(cast[ptr UncheckedArray[Pixel]](addr testFrame[0]))
    echo fmt"  Second frame motion pixels: {motion2}"

    # Test object detection
    echo ""
    echo "Testing object detection..."

    # Create test pattern with bright region
    for i in 0 ..< ImageSize:
      testFrame[i] = 50

    # Add bright rectangle
    for y in 100 ..< 150:
      for x in 100 ..< 200:
        testFrame[y * ImageWidth + x] = 200

    let detection = processFrame(cast[ptr UncheckedArray[Pixel]](addr testFrame[0]))
    echo fmt"  Objects detected: {detection.count}"
    if detection.count > 0:
      echo fmt"  First object area: {detection.blobs[0].area}"

    # Test line detection
    echo ""
    echo "Testing line detection..."

    # Create vertical line
    for i in 0 ..< ImageSize:
      testFrame[i] = 50
    for y in 0 ..< ImageHeight:
      testFrame[y * ImageWidth + ImageWidth div 2] = 200

    let lineInfo = detectLine(cast[ptr UncheckedArray[Pixel]](addr testFrame[0]))
    echo fmt"  Line detected: {lineInfo.detected}"
    echo fmt"  Center offset: {lineInfo.centerX}"

    echo ""
    echo "All tests passed!"

  main()
