## knull/core - Core types and utilities for knull
##
## This module provides the fundamental data structures used throughout
## the knull image processing library. Designed for embedded systems
## with optional stdlib-free operation.
##
## Key types:
## - `GrayImage` - Grayscale image with owned or borrowed data
## - `ImageView` - Non-owning view into image data
## - `Rect`, `Point` - Geometric primitives
## - `Blob`, `Contour`, `Keypoint` - Analysis results

{.push raises: [].}

when not defined(knullNoStdlib):
  import std/math
else:
  # Embedded mode: no stdlib dependencies
  {.hint: "knull running in no-stdlib embedded mode".}

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
    pointer*: Point
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

when defined(nimskullNoStdlib):
  func absVal*(x: int): int {.inline.} =
    ## Absolute value for integers (embedded mode)
    if x < 0: -x else: x

  func absVal*(x: float32): float32 {.inline.} =
    ## Absolute value for float32 (embedded mode)
    if x < 0: -x else: x

  func atan2Approx*(y, x: float32): float32 =
    ## Fast atan2 approximation for embedded systems
    ## Accuracy: ~0.01 radians
    if x == 0.0'f32:
      return (if y > 0.0'f32: HalfPi
              elif y < 0.0'f32: -HalfPi
              else: 0.0'f32)

    let absY = abs(y)
    var r, angle: float32

    if x >= 0.0'f32:
      r = (x - absY) / (x + absY)
      angle = 0.785398'f32 - 0.785398'f32 * r
    else:
      r = (x + absY) / (absY - x)
      angle = 3.0'f32 * 0.785398'f32 - 0.785398'f32 * r

    if y < 0.0'f32: -angle else: angle

  func sinApprox*(x: float32): float32 =
    ## Fast sine approximation for embedded systems
    ## Uses Taylor series with range reduction
    var x = x

    # Normalize to [-PI, PI]
    while x > Pi: x -= 2.0'f32 * Pi
    while x < -Pi: x += 2.0'f32 * Pi

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
    if x <= 0.0'f32: return 0.0'f32

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
