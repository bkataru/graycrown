## knull/image - Basic image operations
##
## This module provides fundamental image manipulation operations:
## - Copy and crop
## - Resize (nearest neighbor and bilinear)
## - Downsample
## - Fill operations

{.push raises: [].}

import ./core

# ============================================================================
# Copy and Fill Operations
# ============================================================================

proc fill*(dst: var ImageView | var GrayImage; value: Pixel) =
  ## Fill entire image with a single value
  if not dst.isValid: return
  for i in 0'u32 ..< dst.size:
    dst.data[i] = value

proc clear*(dst: var ImageView | var GrayImage) {.inline.} =
  ## Clear image (fill with black)
  dst.fill(MinPixel)

proc copy*(dst: var ImageView | var GrayImage; src: ImageView | GrayImage) =
  ## Copy source image to destination
  ## Dimensions must match
  assert dst.width == src.width and dst.height == src.height,
    "Image dimensions must match for copy"
  assert dst.isValid and src.isValid, "Images must be valid"

  for i in 0'u32 ..< dst.size:
    dst.data[i] = src.data[i]

proc copyTo*(src: ImageView | GrayImage; dst: var ImageView | var GrayImage) {.inline.} =
  ## Alternative copy syntax: src.copyTo(dst)
  dst.copy(src)

# ============================================================================
# Crop Operations
# ============================================================================

proc crop*(dst: var ImageView | var GrayImage;
           src: ImageView | GrayImage;
           roi: Rect) =
  ## Crop source image to region of interest
  ## dst dimensions must match roi dimensions
  assert dst.isValid and src.isValid, "Images must be valid"
  assert roi.x + roi.w <= src.width and roi.y + roi.h <= src.height,
    "ROI must be within source image bounds"
  assert dst.width == roi.w and dst.height == roi.h,
    "Destination dimensions must match ROI"

  for y in 0'u32 ..< roi.h:
    for x in 0'u32 ..< roi.w:
      dst[x, y] = src[roi.x + x, roi.y + y]

proc crop*(dst: var ImageView | var GrayImage;
           src: ImageView | GrayImage;
           x, y, w, h: uint32) {.inline.} =
  ## Crop with explicit coordinates
  dst.crop(src, initRect(x, y, w, h))

when not defined(knullNoStdlib):
  proc cropped*(src: GrayImage; roi: Rect): GrayImage =
    ## Create a new cropped image (allocates memory)
    assert src.isValid, "Source image must be valid"
    assert roi.x + roi.w <= src.width and roi.y + roi.h <= src.height,
      "ROI must be within source image bounds"

    result = newGrayImage(roi.w, roi.h)
    result.crop(src.toView, roi)

  proc cropped*(src: GrayImage; x, y, w, h: uint32): GrayImage {.inline.} =
    ## Create a new cropped image with explicit coordinates
    src.cropped(initRect(x, y, w, h))

# ============================================================================
# Resize Operations
# ============================================================================

proc resizeNearestNeighbor*(dst: var ImageView | var GrayImage;
                            src: ImageView | GrayImage) =
  ## Resize using nearest neighbor interpolation
  ## Fast but produces blocky results
  assert dst.isValid and src.isValid, "Images must be valid"

  for y in 0'u32 ..< dst.height:
    for x in 0'u32 ..< dst.width:
      let sx = x * src.width div dst.width
      let sy = y * src.height div dst.height
      dst[x, y] = src[sx, sy]


proc resize*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage) =
  ## Resize using bilinear interpolation
  ## Higher quality than nearest neighbor
  assert dst.isValid and src.isValid, "Images must be valid"

  for y in 0'u32 ..< dst.height:
    for x in 0'u32 ..< dst.width:
      # Map destination pixel to source coordinates (centered)
      var sx = (float32(x) + 0.5'f32) * float32(src.width) / float32(dst.width) - 0.5'f32
      var sy = (float32(y) + 0.5'f32) * float32(src.height) / float32(dst.height) - 0.5'f32

      # Clamp to valid range
      sx = clamp(sx, 0.0'f32, float32(src.width - 1))
      sy = clamp(sy, 0.0'f32, float32(src.height - 1))

      let sxInt = uint32(sx)
      let syInt = uint32(sy)
      let sx1 = min(sxInt + 1, src.width - 1)
      let sy1 = min(syInt + 1, src.height - 1)

      # Fractional parts
      let dx = sx - float32(sxInt)
      let dy = sy - float32(syInt)

      # Get 4 corner pixels
      let c00 = float32(src[sxInt, syInt])
      let c01 = float32(src[sx1, syInt])
      let c10 = float32(src[sxInt, sy1])
      let c11 = float32(src[sx1, sy1])

      # Bilinear interpolation
      let p = c00 * (1.0'f32 - dx) * (1.0'f32 - dy) +
              c01 * dx * (1.0'f32 - dy) +
              c10 * (1.0'f32 - dx) * dy +
              c11 * dx * dy

      dst[x, y] = uint8(clamp(p, 0.0'f32, 255.0'f32))

when not defined(knullNoStdlib):
  proc resized*(src: GrayImage; newWidth, newHeight: uint32): GrayImage =
    ## Create a new resized image using bilinear interpolation
    result = newGrayImage(newWidth, newHeight)
    result.resize(src.toView)

  proc resizedNN*(src: GrayImage; newWidth, newHeight: uint32): GrayImage =
    ## Create a new resized image using nearest neighbor
    result = newGrayImage(newWidth, newHeight)
    result.resizeNearestNeighbor(src.toView)   

# ============================================================================
# Downsample Operations
# ============================================================================

proc downsample*(dst: var ImageView | var GrayImage;
                 src: ImageView | GrayImage) =
  ## Downsample by 2x in each dimension using box filter
  ## dst dimensions must be exactly src.width/2 x src.height/2
  assert dst.isValid and src.isValid, "Images must be valid"
  assert dst.width == src.width div 2 and dst.height == src.height div 2,
    "Destination must be half the size of source"

  for y in 0'u32 ..< dst.height:
    for x in 0'u32 ..< dst.width:
      let srcX = x * 2
      let srcY = y * 2

      # Average 2x2 block
      let sum = uint32(src[srcX, srcY]) +
                uint32(src[srcX + 1, srcY]) +
                uint32(src[srcX, srcY + 1]) +
                uint32(src[srcX + 1, srcY + 1])

      dst[x, y] = uint8(sum div 4)

when not defined(knullNoStdlib):
  proc downsampled*(src: GrayImage): GrayImage =
    ## Create a new 2x downsampled image
    result = newGrayImage(src.width div 2, src.height div 2)
    result.downsample(src.toView)

# ============================================================================
# Pyramid Operations
# ============================================================================

type
  ImagePyramid* = object
    ## Multi-scale image pyramid
    levels*: seq[GrayImage]

when not defined(knullNoStdlib):
  proc buildPyramid*(src: GrayImage; nLevels: int; minSize: uint32 = 32): ImagePyramid =
    ## Build Gaussian pyramid with specified number of levels
    ## Stops early if image becomes smaller than minSize
    result.levels = @[]
    result.levels.add(src)

    var current = src
    for level in 1 ..< nLevels:
      let newW = current.width div 2
      let newH = current.height div 2

      if newW < minSize or newH < minSize:
        break

      var next = newGrayImage(newW, newH)
      next.downsample(current.toView)
      result.levels.add(next)
      current = next

  proc levelCount*(pyramid: ImagePyramid): int {.inline.} =
    pyramid.levels.len

  proc `[]`*(pyramid: ImagePyramid; level: int): GrayImage {.inline.} =
    pyramid.levels[level]

# ============================================================================
# Flip and Rotate Operations
# ============================================================================

proc flipHorizontal*(dst: var ImageView | var GrayImage;
                     src: ImageView | GrayImage) =
  ## Flip image horizontally (mirror)
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      dst[src.width - 1 - x, y] = src[x, y]

proc flipVertical*(dst: var ImageView | var GrayImage;
                   src: ImageView | GrayImage) =
  ## Flip image vertically
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      dst[x, src.height - 1 - y] = src[x, y]

proc rotate90CW*(dst: var ImageView | var GrayImage;
                 src: ImageView | GrayImage) =
  ## Rotate image 90 degrees clockwise
  ## dst dimensions must be (src.height, src.width)
  assert dst.width == src.height and dst.height == src.width,
    "Destination dimensions must be swapped from source"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      dst[src.height - 1 - y, x] = src[x, y]

proc rotate90CCW*(dst: var ImageView | var GrayImage;
                  src: ImageView | GrayImage) =
  ## Rotate image 90 degrees counter-clockwise
  ## dst dimensions must be (src.height, src.width)
  assert dst.width == src.height and dst.height == src.width,
    "Destination dimensions must be swapped from source"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      dst[y, src.width - 1 - x] = src[x, y]

# ============================================================================
# Invert Operation
# ============================================================================

proc invert*(img: var ImageView | var GrayImage) =
  ## Invert image in-place (negative)
  for i in 0'u32 ..< img.size:
    img.data[i] = 255 - img.data[i]

proc invert*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage) =
    ## Invert source image to destination
    assert dst.width == src.width and dst.height == src.height,
      "Dimensions must match"

    for i in 0'u32 ..< dst.size:
      dst.data[i] = 255 - src.data[i]

{.pop.} # raises: []
