## graycrown/core - Core types and utilities for graycrown
##
## This module provides the fundamental data structures used throughout
## the graycrown image processing library. Designed for embedded systems
## with optional stdlib-free operation.
##
## Key types:
## - `GrayImage` - Grayscale image with owned or borrowed data
## - `ImageView` - Non-owning view into image data
## - `Rect`, `Point` - Geometric primitives
## - `Blob`, `Contour`, `Keypoint` - Analysis results

{.push raises: [].}

when not defined(graycrownNoStdlib):
  import std/math
else:
  # Embedded mode: no stdlib dependencies
  {.hint: "graycrown running in no-stdlib embedded mode".}

type
  ## Pixel type - 8-bit grayscale
  Pixel* = uint8

  ## Label type for connected components
  Label* = uint16

  ## 2D point with unsigned coordinates
  Point* = object
    x*, y*: uint32

  ## Rectangle defined by position and dimensions
  Rect* = object
    x*, y*, w*, h*: uint32

  ## Non-owning view into grayscale image data
  ## Suitable for stack-allocated or borrowed image data
  ImageView* = object
    width*, height*: uint32
    data*: ptr UncheckedArray[Pixel]

  ## Owning grayscale image with optional memory management
  ## When `owned` is true, data is freed on destruction
  GrayImage* = object
    width*, height*: uint32
    data*: ptr UncheckedArray[Pixel]
    owned*: bool
    capacity*: uint32

  ## Connected component (blob) information
  Blob* = object
    label*: Label
    area*: uint32
    box*: Rect
    centroid*: Point

  ## Contour tracing result
  Contour* = object
    box*: Rect
    start*: Point
    length*: uint32

  ## Feature keypoint with optional descriptor
  Keypoint* = object
    pt*: Point
    response*: uint32
    angle*: float32
    descriptor*: array[8, uint32]

  ## Feature match between two keypoints
  Match* = object
    idx1*, idx2*: uint32
    distance*: uint32

  ## LBP (Local Binary Pattern) cascade for object detection
  LbpCascade* = object
    windowW*, windowH*: uint16
    nFeatures*, nWeaks*, nStages*: uint16
    features*: ptr UncheckedArray[int8]
    weakFeatureIdx*: ptr UncheckedArray[uint16]
    weakLeftVal*: ptr UncheckedArray[float32]
    weakRightVal*: ptr UncheckedArray[float32]
    weakSubsetOffset*: ptr UncheckedArray[uint16]
    weakNumSubsets*: ptr UncheckedArray[uint16]
    subsets*: ptr UncheckedArray[int32]
    stageWeakStart*: ptr UncheckedArray[uint16]
    stageNWeaks*: ptr UncheckedArray[uint16]
    stageThreshold*: ptr UncheckedArray[float32]

# ============================================================================
# # Constants
# # ============================================================================

const
  ## Maximum pixel value
  MaxPixel* = 255'u8

  ## Minimum pixel value
  MinPixel* = 0'u8

  ## Threshold for binary operations (foreground vs background)
  BinaryThreshold* = 128'u8

  ## PI constant for angle calculations
  Pi* = 3.14159265358979323846'f32

  ## Half PI
  HalfPi* = 1.5707963267948966'f32

# ============================================================================
# Utility Templates and Inline Functions
# ============================================================================

# Note: Use system.min, system.max, system.clamp, system.abs for these operations

# ============================================================================
# Math functions (embedded-compatible implementations)
# ============================================================================

when defined(graycrownNoStdlib):
  func absVal*(x: int): int {.inline.} =
    ## Absolute value for integers (embedded mode)
    if x < 0:
      -x
    else:
      x

  func absVal*(x: float32): float32 {.inline.} =
    ## Absolute value for float32 (embedded mode)
    if x < 0:
      -x
    else:
      x

  func atan2Approx*(y, x: float32): float32 =
    ## Fast atan2 approximation for embedded systems
    ## Accuracy: ~0.01 radians
    if x == 0.0'f32:
      return (if y > 0.0'f32: HalfPi elif y < 0.0'f32: -HalfPi else: 0.0'f32)

    let absY = abs(y)
    var r, angle: float32

    if x >= 0.0'f32:
      r = (x - absY) / (x + absY)
      angle = 0.785398'f32 - 0.785398'f32 * r
    else:
      r = (x + absY) / (absY - x)
      angle = 3.0'f32 * 0.785398'f32 - 0.785398'f32 * r

    if y < 0.0'f32:
      -angle
    else:
      angle

  func sinApprox*(x: float32): float32 =
    ## Fast sine approximation for embedded systems
    ## Uses Taylor series with range reduction
    var x = x

    # Normalize to [-PI, PI]
    while x > Pi:
      x -= 2.0'f32 * Pi
    while x < -Pi:
      x += 2.0'f32 * Pi

    var sign: float32 = 1.0'f32
    if x < 0.0'f32:
      x = -x
      sign = -1.0'f32

    # Reduce to [0, PI/2]
    if x > HalfPi:
      x = Pi - x

    # Taylor approximation: sin(x) ≈ x - x³/6 + x⁵/120
    let x2 = x * x
    let res = x * (1.0'f32 - x2 * (0.16666667'f32 - 0.0083333310'f32 * x2))
    sign * res

  func cosApprox*(x: float32): float32 =
    ## Fast cosine approximation (cos(x) = sin(x + π/2))
    sinApprox(x + HalfPi)

  func sqrtApprox*(x: float32): float32 =
    ## Fast square root approximation using Newton-Raphson
    if x <= 0.0'f32:
      return 0.0'f32

    # Initial guess using bit manipulation
    var i = cast[uint32](x)
    i = 0x1fbd1df5'u32 + (i shr 1)
    var y = cast[float32](i)

    # Two Newton-Raphson iterations
    y = 0.5'f32 * (y + x / y)
    y = 0.5'f32 * (y + x / y)
    y
else:
  # Use stdlib math functions
  func atan2Approx*(y, x: float32): float32 {.inline.} =
    arctan2(y, x)

  func sinApprox*(x: float32): float32 {.inline.} =
    sin(x)

  func cosApprox*(x: float32): float32 {.inline.} =
    cos(x)

  func sqrtApprox*(x: float32): float32 {.inline.} =
    sqrt(x)

# ============================================================================
# ImageView and GrayImage operations
# ============================================================================

func isValid*(img: ImageView | GrayImage): bool {.inline.} =
  ## Check if image is valid (has data and non-zero dimensions)
  img.data != nil and img.width > 0 and img.height > 0

func size*(img: ImageView | GrayImage): uint32 {.inline.} =
  ## Get total number of pixels
  img.width * img.height

func contains*(img: ImageView | GrayImage, x, y: uint32): bool {.inline.} =
  ## Check if coordinates are within image bounds
  x < img.width and y < img.height

func contains*(img: ImageView | GrayImage, x, y: int): bool {.inline.} =
  ## Check if signed coordinates are within image bounds
  x >= 0 and y >= 0 and uint32(x) < img.width and uint32(y) < img.height

func idx*(img: ImageView | GrayImage, x, y: uint32): uint32 {.inline.} =
  ## Convert 2D coordinates to linear index
  y * img.width + x

func get*(img: ImageView | GrayImage, x, y: uint32): Pixel {.inline.} =
  ## Get pixel value at (x, y) with bounds checking
  ## Returns 0 for out-of-bounds coordinates
  if img.contains(x, y):
    img.data[img.idx(x, y)]
  else:
    0

func get*(img: ImageView | GrayImage, x, y: int): Pixel {.inline.} =
  ## Get pixel value with signed coordinates
  if img.contains(x, y):
    img.data[img.idx(uint32(x), uint32(y))]
  else:
    0

func `[]`*(img: ImageView | GrayImage, x, y: uint32): Pixel {.inline.} =
  ## Subscript operator for pixel access
  img.get(x, y)

func `[]`*(img: ImageView | GrayImage, x, y: int): Pixel {.inline.} =
  ## Subscript operator with signed coordinates
  img.get(x, y)

proc set*(img: var ImageView | var GrayImage, x, y: uint32, value: Pixel) {.inline.} =
  ## Set pixel value at (x, y) with bounds checking
  if img.contains(x, y):
    img.data[img.idx(x, y)] = value

proc set*(img: var ImageView | var GrayImage, x, y: int, value: Pixel) {.inline.} =
  ## Set pixel value with signed coordinates
  if img.contains(x, y):
    img.data[img.idx(uint32(x), uint32(y))] = value

proc `[]=`*(img: var ImageView | var GrayImage, x, y: uint32, value: Pixel) {.inline.} =
  ## Subscript assignment operator
  img.set(x, y, value)

proc `[]=`*(img: var ImageView | var GrayImage, x, y: int, value: Pixel) {.inline.} =
  ## Subscript assignment with signed coordinates
  img.set(x, y, value)

# ============================================================================
# ImageView creation
# ============================================================================

func toView*(img: GrayImage): ImageView {.inline.} =
  ## Create a non-owning view from GrayImage
  ImageView(width: img.width, height: img.height, data: img.data)

func initImageView*(
    data: ptr UncheckedArray[Pixel], width, height: uint32
): ImageView {.inline.} =
  ## Create ImageView from raw pointer and dimensions
  ImageView(width: width, height: height, data: data)

func initImageView*(data: var openArray[Pixel], width, height: uint32): ImageView =
  ## Create ImageView from openArray (stack or heap allocated)
  assert data.len >= int(width * height), "Buffer too small for image dimensions"
  ImageView(
    width: width, height: height, data: cast[ptr UncheckedArray[Pixel]](addr data[0])
  )

# ============================================================================
# GrayImage memory management
# ============================================================================

when not defined(graycrownNoStdlib):
  proc newGrayImage*(width, height: uint32): GrayImage =
    ## Allocate a new grayscale image with zeroed data
    ## Call freeGrayImage() when done, or use withImage template
    if width == 0 or height == 0:
      return GrayImage(width: 0, height: 0, data: nil, owned: false, capacity: 0)

    let size = width * height
    let data = cast[ptr UncheckedArray[Pixel]](alloc0(size))
    GrayImage(width: width, height: height, data: data, owned: true, capacity: size)

  proc freeGrayImage*(img: var GrayImage) =
    ## Free memory for owned GrayImage
    ## Call this when done with an image created by newGrayImage
    if img.owned and img.data != nil:
      dealloc(img.data)
      img.data = nil
      img.owned = false

  proc clone*(src: GrayImage): GrayImage =
    ## Create a deep copy of an image
    if src.data == nil:
      return GrayImage(width: 0, height: 0, data: nil, owned: false, capacity: 0)

    let size = src.width * src.height
    let data = cast[ptr UncheckedArray[Pixel]](alloc(size))
    copyMem(data, src.data, size)
    GrayImage(
      width: src.width, height: src.height, data: data, owned: true, capacity: size
    )

  proc wrapBuffer*(data: ptr UncheckedArray[Pixel], width, height: uint32): GrayImage =
    ## Wrap existing buffer as non-owning GrayImage
    GrayImage(
      width: width, height: height, data: data, owned: false, capacity: width * height
    )

  template withImage*(name: untyped, width, height: uint32, body: untyped) =
    ## RAII-style image management
    ## ```nim
    ## withImage(img, 640, 480):
    ##   fill(img, 128)
    ##   # img is automatically freed at end of block
    ## ```
    var name = newGrayImage(width, height)
    try:
      body
    finally:
      freeGrayImage(name)

else:
  # Embedded mode: no automatic allocation
  # User must provide buffers
  proc initGrayImage*(
      data: ptr UncheckedArray[Pixel], width, height: uint32
  ): GrayImage =
    ## Initialize GrayImage with external buffer (embedded mode)
    GrayImage(
      width: width, height: height, data: data, owned: false, capacity: width * height
    )

# ============================================================================
# Point and Rect operations
# ============================================================================

func initPoint*(x, y: uint32): Point {.inline.} =
  Point(x: x, y: y)

func initPoint*(x, y: int): Point {.inline.} =
  Point(x: uint32(max(0, x)), y: uint32(max(0, y)))

func initRect*(x, y, w, h: uint32): Rect {.inline.} =
  Rect(x: x, y: y, w: w, h: h)

func initRect*(x, y, w, h: int): Rect {.inline.} =
  Rect(
    x: uint32(max(0, x)),
    y: uint32(max(0, y)),
    w: uint32(max(0, w)),
    h: uint32(max(0, h)),
  )

func right*(r: Rect): uint32 {.inline.} =
  ## Get right edge x coordinate
  r.x + r.w

func bottom*(r: Rect): uint32 {.inline.} =
  ## Get bottom edge y coordinate
  r.y + r.h

func area*(r: Rect): uint32 {.inline.} =
  ## Get rectangle area
  r.w * r.h

func center*(r: Rect): Point {.inline.} =
  ## Get rectangle center poin
  Point(x: r.x + r.w div 2, y: r.y + r.h div 2)

func contains*(r: Rect, p: Point): bool {.inline.} =
  ## Check if rectangle contains point
  p.x >= r.x and p.x < r.right and p.y >= r.y and p.y < r.bottom

func overlaps*(a, b: Rect): bool {.inline.} =
  ## Check if two rectangles overlap
  not (a.right <= b.x or b.right <= a.x or a.bottom <= b.y or b.bottom <= a.y)

func intersection*(a, b: Rect): Rect =
  ## Get intersection of two rectangles
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.right, b.right)
  let y2 = min(a.bottom, b.bottom)

  if x2 > x1 and y2 > y1:
    Rect(x: x1, y: y1, w: x2 - x1, h: y2 - y1)
  else:
    Rect(x: 0, y: 0, w: 0, h: 0)

func boundingBox*(a, b: Rect): Rect =
  ## Get bounding box containing both rectangles
  let x1 = min(a.x, b.x)
  let y1 = min(a.y, b.y)
  let x2 = max(a.right, b.right)
  let y2 = max(a.bottom, b.bottom)
  Rect(x: x1, y: y1, w: x2 - x1, h: y2 - y1)

# ============================================================================
# Iterator for image pixels
# ============================================================================

iterator pixels*(img: ImageView | GrayImage): tuple[x, y: uint32, val: Pixel] =
  # Iterate over all pixels in image
  for y in 0'u32 ..< img.height:
    for x in 0'u32 ..< img.width:
      yield (x, y, img[x, y])

iterator coords*(img: ImageView | GrayImage): tuple[x, y: uint32] =
  ## Iterate over all coordinates in image
  for y in 0'u32 ..< img.height:
    for x in 0'u32 ..< img.width:
      yield (x, y)

iterator rectPixels*(
    img: ImageView | GrayImage, roi: Rect
): tuple[x, y: uint32, val: Pixel] =
  # Iterate over pixels within a rectangle
  let x2 = min(roi.right, img.width)
  let y2 = min(roi.bottom, img.height)
  for y in roi.y ..< y2:
    for x in roi.x ..< x2:
      yield (x, y, img[x, y])

{.pop.} # raises: []
