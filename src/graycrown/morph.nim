## graycrown/morph - Morphological operations
##
## This module provides morphological image processing operations:
## - Erosion
## - Dilation
## - Opening (erosion followed by dilation)
## - Closing (dilation followed by erosion)

{.push raises: [].}

import ./core

# ============================================================================
# Basic Morphological Operations
# ============================================================================

type
  MorphOp* = enum
    ## Morphological operation type
    MorphErode
    MorphDilate

proc morphOp*(dst: var ImageView | var GrayImage;
              src: ImageView | GrayImage;
              op: MorphOp) =
  ## Apply morphological operation with 3x3 structuring element
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert dst.isValid and src.isValid, "Images must be valid"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var val: uint8 = case op
        of MorphErode: MaxPixel   # Start with max, find min
        of MorphDilate: MinPixel  # Start with min, find max

      # 3x3 neighborhood
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          let sy = int(y) + dy
          let sx = int(x) + dx

          if src.contains(sx, sy):
            let pixel = src[sx, sy]
            case op
            of MorphErode:
              if pixel < val: val = pixel
            of MorphDilate:
              if pixel > val: val = pixel

      dst[x, y] = val

proc erode*(dst: var ImageView | var GrayImage;
            src: ImageView | GrayImage) {.inline.} =
  ## Erosion: shrinks bright regions
  ## Each pixel becomes the minimum of its 3x3 neighborhood
  morphOp(dst, src, MorphErode)

proc dilate*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage) {.inline.} =
  ## Dilation: expands bright regions
  ## Each pixel becomes the maximum of its 3x3 neighborhood
  morphOp(dst, src, MorphDilate)

# ============================================================================
# Extended Morphological Operations
# ============================================================================

proc erode*(dst: var ImageView | var GrayImage;
            src: ImageView | GrayImage;
            radius: uint32) =
  ## Erosion with larger structuring element
  ## radius=1 is equivalent to 3x3 erode
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  let radiusInt = int(radius)

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var val: uint8 = MaxPixel

      for dy in -radiusInt .. radiusInt:
        for dx in -radiusInt .. radiusInt:
          let sy = int(y) + dy
          let sx = int(x) + dx

          if src.contains(sx, sy):
            let pixel = src[sx, sy]
            if pixel < val: val = pixel

      dst[x, y] = val

proc dilate*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage;
             radius: uint32) =
  ## Dilation with larger structuring element
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  let radiusInt = int(radius)

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var val: uint8 = MinPixel

      for dy in -radiusInt .. radiusInt:
        for dx in -radiusInt .. radiusInt:
          let sy = int(y) + dy
          let sx = int(x) + dx

          if src.contains(sx, sy):
            let pixel = src[sx, sy]
            if pixel > val: val = pixel

      dst[x, y] = val

# ============================================================================
# Iterative Operations
# ============================================================================

proc erodeN*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage;
             temp: var ImageView | var GrayImage;
             iterations: uint32) =
  ## Apply erosion N times
  ## Requires temporary buffer for ping-pong operation
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert temp.width == src.width and temp.height == src.height,
    "Temp buffer dimensions must match"

  if iterations == 0:
    dst.copy(src)
    return

  # First iteration: src -> dst
  erode(dst, src)

  if iterations == 1:
    return

  # Remaining iterations: ping-pong between dst and temp
  for i in 1'u32 ..< iterations:
    if (i and 1) == 1:
      erode(temp, dst)
    else:
      erode(dst, temp)

  # If odd number of remaining iterations, result is in temp
  if ((iterations - 1) and 1) == 1:
    dst.copy(temp)

proc dilateN*(dst: var ImageView | var GrayImage;
              src: ImageView | GrayImage;
              temp: var ImageView | var GrayImage;
              iterations: uint32) =
  ## Apply dilation N times
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert temp.width == src.width and temp.height == src.height,
    "Temp buffer dimensions must match"

  if iterations == 0:
    dst.copy(src)
    return

  dilate(dst, src)

  if iterations == 1:
    return

  for i in 1'u32 ..< iterations:
    if (i and 1) == 1:
      dilate(temp, dst)
    else:
      dilate(dst, temp)

  if ((iterations - 1) and 1) == 1:
    dst.copy(temp)

# ============================================================================
# Compound Operations
# ============================================================================

proc morphOpen*(dst: var ImageView | var GrayImage;
                src: ImageView | GrayImage;
                temp: var ImageView | var GrayImage) =
  ## Morphological opening: erosion followed by dilation
  ## Removes small bright spots (noise) while preserving larger structures
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert temp.width == src.width and temp.height == src.height,
    "Temp buffer dimensions must match"

  erode(temp, src)
  dilate(dst, temp)

proc morphClose*(dst: var ImageView | var GrayImage;
                 src: ImageView | GrayImage;
                 temp: var ImageView | var GrayImage) =
  ## Morphological closing: dilation followed by erosion
  ## Fills small dark spots (holes) while preserving larger structures
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert temp.width == src.width and temp.height == src.height,
    "Temp buffer dimensions must match"

  dilate(temp, src)
  erode(dst, temp)

proc morphGradient*(dst: var ImageView | var GrayImage;
                    src: ImageView | GrayImage;
                    dilated: var ImageView | var GrayImage;
                    eroded: var ImageView | var GrayImage) =
  ## Morphological gradient: difference between dilation and erosion
  ## Highlights edges/boundaries
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  dilate(dilated, src)
  erode(eroded, src)

  for i in 0'u32 ..< dst.size:
    dst.data[i] = dilated.data[i] - eroded.data[i]

proc topHat*(dst: var ImageView | var GrayImage;
             src: ImageView | GrayImage;
             temp: var ImageView | var GrayImage) =
  ## Top-hat transform: difference between image and opening
  ## Extracts bright features smaller than structuring element
  morphOpen(temp, src, dst)  # Using dst as temp for opening

  for i in 0'u32 ..< dst.size:
    if src.data[i] > temp.data[i]:
      dst.data[i] = src.data[i] - temp.data[i]
    else:
      dst.data[i] = 0

proc blackHat*(dst: var ImageView | var GrayImage;
               src: ImageView | GrayImage;
               temp: var ImageView | var GrayImage) =
  ## Black-hat transform: difference between closing and image
  ## Extracts dark features smaller than structuring element
  morphClose(temp, src, dst)  # Using dst as temp for closing

  for i in 0'u32 ..< dst.size:
    if temp.data[i] > src.data[i]:
      dst.data[i] = temp.data[i] - src.data[i]
    else:
      dst.data[i] = 0

# ============================================================================
# Cross Structuring Element Operations
# ============================================================================

proc erodeCross*(dst: var ImageView | var GrayImage;
                 src: ImageView | GrayImage) =
  ## Erosion with cross-shaped (4-connected) structuring element
  ## Only considers top, bottom, left, right neighbors
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var val = src[x, y]

      # Only 4-connected neighbors
      if src.contains(int(x) - 1, int(y)):
        let p = src[x - 1, y]
        if p < val: val = p
      if src.contains(int(x) + 1, int(y)):
        let p = src[x + 1, y]
        if p < val: val = p
      if src.contains(int(x), int(y) - 1):
        let p = src[x, y - 1]
        if p < val: val = p
      if src.contains(int(x), int(y) + 1):
        let p = src[x, y + 1]
        if p < val: val = p

      dst[x, y] = val

proc dilateCross*(dst: var ImageView | var GrayImage;
                  src: ImageView | GrayImage) =
  ## Dilation with cross-shaped structuring element
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var val = src[x, y]

      if src.contains(int(x) - 1, int(y)):
        let p = src[x - 1, y]
        if p > val: val = p
      if src.contains(int(x) + 1, int(y)):
        let p = src[x + 1, y]
        if p > val: val = p
      if src.contains(int(x), int(y) - 1):
        let p = src[x, y - 1]
        if p > val: val = p
      if src.contains(int(x), int(y) + 1):
        let p = src[x, y + 1]
        if p > val: val = p

      dst[x, y] = val

{.pop.} # raises: []
