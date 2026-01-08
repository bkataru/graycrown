## graycrown/lbp - Local Binary Pattern cascade detection
##
## This module provides LBP (Local Binary Pattern) cascade detection
## for object detection (e.g., faces, vehicles). Compatible with
## OpenCV's LBP cascade format.

{.push raises: [].}

import ./core
import ./integral

# ============================================================================
# LBP Code Computation
# ============================================================================

func lbpCode*(ii: IntegralImage;
              x, y: int;
              fx, fy, fw, fh: int): int =
  ## Compute 8-bit LBP code at given location
  ##
  ## Uses a 3x3 grid of cells, comparing each cell's sum to the center.
  ## Returns an 8-bit code where each bit indicates if that neighbor
  ## is >= the center cell.
  ##
  ## Grid layout:
  ##   TL TC TR     bit 7  bit 6  bit 5
  ##   L  C  R  =>  bit 0   ---   bit 4
  ##   BL BC BR     bit 1  bit 2  bit 3

  # Get sums for each cell in 3x3 grid
  let tl = regionSum(ii, uint32(x + fx), uint32(y + fy), uint32(fw), uint32(fh))
  let tc = regionSum(ii, uint32(x + fx + fw), uint32(y + fy), uint32(fw), uint32(fh))
  let tr = regionSum(ii, uint32(x + fx + 2 * fw), uint32(y + fy), uint32(fw), uint32(fh))
  let l = regionSum(ii, uint32(x + fx), uint32(y + fy + fh), uint32(fw), uint32(fh))
  let c = regionSum(ii, uint32(x + fx + fw), uint32(y + fy + fh), uint32(fw), uint32(fh))
  let r = regionSum(ii, uint32(x + fx + 2 * fw), uint32(y + fy + fh), uint32(fw), uint32(fh))
  let bl = regionSum(ii, uint32(x + fx), uint32(y + fy + 2 * fh), uint32(fw), uint32(fh))
  let bc = regionSum(ii, uint32(x + fx + fw), uint32(y + fy + 2 * fh), uint32(fw), uint32(fh))
  let br = regionSum(ii, uint32(x + fx + 2 * fw), uint32(y + fy + 2 * fh), uint32(fw), uint32(fh))

  # Build LBP code
  result = 0
  if tl >= c: result = result or (1 shl 7)
  if tc >= c: result = result or (1 shl 6)
  if tr >= c: result = result or (1 shl 5)
  if r >= c: result = result or (1 shl 4)
  if br >= c: result = result or (1 shl 3)
  if bc >= c: result = result or (1 shl 2)
  if bl >= c: result = result or (1 shl 1)
  if l >= c: result = result or (1 shl 0)

func lbpMatch*(code: int; subsets: ptr UncheckedArray[int32]; n: int): bool =
  ## Check if LBP code matches any pattern in subset array
  ## The subset array is a bitmask where each bit indicates if that LBP code
  ## is considered a "positive" pattern
  let idx = code div 32
  let bit = code mod 32
  idx < n and (subsets[idx] and (1'i32 shl bit)) != 0

# ============================================================================
# Cascade Window Evaluation
# ============================================================================

proc lbpEvaluateWindow*(cascade: LbpCascade;
                        ii: IntegralImage;
                        x, y: int;
                        scale: float32): bool =
  ## Evaluate cascade classifier at a single window position
  ##
  ## Returns true if the window passes all stages (positive detection)
  let winW = int(float32(cascade.windowW) * scale)
  let winH = int(float32(cascade.windowH) * scale)

  # Check bounds
  if x + winW > int(ii.width) or y + winH > int(ii.height):
    return false

  # Evaluate each stage
  for si in 0 ..< int(cascade.nStages):
    let stageStart = int(cascade.stageWeakStart[si])
    let stageNWeaks = int(cascade.stageNWeaks[si])
    var stageSum: float32 = 0.0

    # Evaluate each weak classifier in this stage
    for i in 0 ..< stageNWeaks:
      let wi = stageStart + i
      let fi = int(cascade.weakFeatureIdx[wi])

      # Get scaled feature position and size
      let fx = int(float32(cascade.features[fi * 4 + 0]) * scale)
      let fy = int(float32(cascade.features[fi * 4 + 1]) * scale)
      var fw = int(float32(cascade.features[fi * 4 + 2]) * scale)
      var fh = int(float32(cascade.features[fi * 4 + 3]) * scale)

      # Ensure minimum size
      if fw < 1: fw = 1
      if fh < 1: fh = 1

      # Compute LBP code and check against subsets
      let code = lbpCode(ii, x, y, fx, fy, fw, fh)
      let subsetOffset = int(cascade.weakSubsetOffset[wi])
      let numSubsets = int(cascade.weakNumSubsets[wi])

      let matches = lbpMatch(code,
                             cast[ptr UncheckedArray[int32]](addr cascade.subsets[subsetOffset]),
                             numSubsets)

      # Add weak classifier contribution
      if matches:
        stageSum += cascade.weakLeftVal[wi]
      else:
        stageSum += cascade.weakRightVal[wi]

    # Check stage threshold
    if stageSum < cascade.stageThreshold[si]:
      return false

  true  # Passed all stages

# ============================================================================
# Multi-Scale Detection
# ============================================================================

proc lbpDetect*(cascade: LbpCascade;
                ii: IntegralImage;
                rects: var openArray[Rect];
                maxRects: uint32;
                scaleFactor: float32 = 1.2'f32;
                minScale: float32 = 1.0'f32;
                maxScale: float32 = 4.0'f32;
                step: int = 1): uint32 =
  ## Detect objects using LBP cascade at multiple scales
  ##
  ## Parameters:
  ## - cascade: LBP cascade classifier
  ## - ii: Pre-computed integral image
  ## - rects: Output array of detection rectangles
  ## - maxRects: Maximum number of detections
  ## - scaleFactor: Scale multiplier between levels (typically 1.1-1.2)
  ## - minScale: Minimum detection scale
  ## - maxScale: Maximum detection scale
  ## - step: Step size for sliding window (1 = every pixel)
  ##
  ## Returns: Number of detections
  assert ii.isValid, "Integral image must be valid"
  assert maxRects > 0 and rects.len >= int(maxRects),
    "Rect buffer must be large enough"

  var nRects: uint32 = 0
  var scale = minScale

  while scale <= maxScale and nRects < maxRects:
    let winW = int(float32(cascade.windowW) * scale)
    let winH = int(float32(cascade.windowH) * scale)

    # Check if window fits
    if winW > int(ii.width) or winH > int(ii.height):
      break

    # Slide window
    var y = 0
    while y + winH <= int(ii.height) and nRects < maxRects:
      var x = 0
      while x + winW <= int(ii.width) and nRects < maxRects:
        if lbpEvaluateWindow(cascade, ii, x, y, scale):
          rects[nRects] = Rect(
            x: uint32(x),
            y: uint32(y),
            w: uint32(winW),
            h: uint32(winH)
          )
          nRects += 1
        x += step
      y += step

    scale *= scaleFactor

  nRects

# ============================================================================
# Non-Maximum Suppression for Detections
# ============================================================================

func intersectionOverUnion(a, b: Rect): float32 =
  ## Compute IoU (Intersection over Union) of two rectangles
  let interRect = intersection(a, b)
  if interRect.w == 0 or interRect.h == 0:
    return 0.0'f32

  let interArea = float32(interRect.area)
  let unionArea = float32(a.area) + float32(b.area) - interArea

  if unionArea > 0:
    interArea / unionArea
  else:
    0.0'f32

proc groupRectangles*(rects: var openArray[Rect];
                      count: uint32;
                      minNeighbors: int = 3;
                      iouThreshold: float32 = 0.3'f32): uint32 =
  ## Group overlapping rectangles and filter by neighbor count
  ##
  ## This performs non-maximum suppression by grouping overlapping
  ## detections and keeping only groups with enough members.
  ##
  ## Parameters:
  ## - rects: Array of detection rectangles (modified in place)
  ## - count: Number of rectangles
  ## - minNeighbors: Minimum group size to keep
  ## - iouThreshold: IoU threshold for considering rects as neighbors
  ##
  ## Returns: New count after filtering
  if count == 0:
    return 0

  # Group labels for each rectangle
  var labels = newSeq[int](count)
  for i in 0 ..< int(count):
    labels[i] = i

  # Union-find to group overlapping rectangles
  proc findLabel(labels: var seq[int]; i: int): int =
    var current = i
    while labels[current] != current:
      labels[current] = labels[labels[current]]
      current = labels[current]
    current

  for i in 0 ..< int(count):
    for j in i + 1 ..< int(count):
      if intersectionOverUnion(rects[i], rects[j]) > iouThreshold:
        let rootI = findLabel(labels, i)
        let rootJ = findLabel(labels, j)
        if rootI != rootJ:
          labels[max(rootI, rootJ)] = min(rootI, rootJ)

  # Count group sizes and compute merged rectangles
  var groupSizes = newSeq[int](count)
  var groupSumX = newSeq[int](count)
  var groupSumY = newSeq[int](count)
  var groupSumW = newSeq[int](count)
  var groupSumH = newSeq[int](count)

  for i in 0 ..< int(count):
    let root = findLabel(labels, i)
    groupSizes[root] += 1
    groupSumX[root] += int(rects[i].x)
    groupSumY[root] += int(rects[i].y)
    groupSumW[root] += int(rects[i].w)
    groupSumH[root] += int(rects[i].h)

  # Output merged rectangles for groups >= minNeighbors
  var writeIdx: uint32 = 0
  for i in 0 ..< int(count):
    if findLabel(labels, i) == i and groupSizes[i] >= minNeighbors:
      let n = groupSizes[i]
      rects[writeIdx] = Rect(
        x: uint32(groupSumX[i] div n),
        y: uint32(groupSumY[i] div n),
        w: uint32(groupSumW[i] div n),
        h: uint32(groupSumH[i] div n)
      )
      writeIdx += 1

  writeIdx

proc lbpDetectWithNMS*(cascade: LbpCascade;
                       ii: IntegralImage;
                       rects: var openArray[Rect];
                       maxRects: uint32;
                       scaleFactor: float32 = 1.2'f32;
                       minScale: float32 = 1.0'f32;
                       maxScale: float32 = 4.0'f32;
                       minNeighbors: int = 3): uint32 =
  ## Detect objects with automatic non-maximum suppression
  ##
  ## Convenience function that runs detection and NMS in one call.
  let nRaw = lbpDetect(cascade, ii, rects, maxRects,
                       scaleFactor, minScale, maxScale, step = 1)

  if nRaw == 0:
    return 0

  groupRectangles(rects, nRaw, minNeighbors)

{.pop.} # raises: []
