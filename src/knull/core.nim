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
    ptr*: Point
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
