## graycrown/blobs - Connected components analysis
##
## This module provides:
## - Connected component labeling (blob detection)
## - Blob properties (area, bounding box, centroid)
## - Contour tracing
## - Corner detection on blobs
## - Perspective correction

{.push raises: [].}

import ./core

# ============================================================================
# Label Array Type
# ============================================================================

type
  LabelArray* = object
    ## 2D array of labels for connected components
    width*, height*: uint32
    data*: ptr UncheckedArray[Label]

func initLabelArray*(data: ptr UncheckedArray[Label]; width, height: uint32): LabelArray =
  ## Create label array from existing buffer
  LabelArray(width: width, height: height, data: data)

func initLabelArray*(data: var openArray[Label]; width, height: uint32): LabelArray =
  ## Create label array from openArray
  assert data.len >= int(width * height), "Buffer too small"
  LabelArray(
    width: width,
    height: height,
    data: cast[ptr UncheckedArray[Label]](addr data[0])
  )

func `[]`*(labels: LabelArray; x, y: uint32): Label {.inline.} =
  if x < labels.width and y < labels.height:
    labels.data[y * labels.width + x]
  else:
    0

proc `[]=`*(labels: var LabelArray; x, y: uint32; value: Label) {.inline.} =
  if x < labels.width and y < labels.height:
    labels.data[y * labels.width + x] = value

proc clear*(labels: var LabelArray) =
  ## Clear all labels to 0
  for i in 0'u32 ..< labels.width * labels.height:
    labels.data[i] = 0

# ============================================================================
# Union-Find for Connected Components
# ============================================================================

func findRoot(x: Label; parents: var openArray[Label]): Label =
  ## Find root of label with path compression
  var current = x
  while parents[current] != current:
    # Path compression
    parents[current] = parents[parents[current]]
    current = parents[current]
  current

# ============================================================================
# Connected Component Labeling
# ============================================================================

proc findBlobs*(img: ImageView | GrayImage;
                labels: var LabelArray;
                blobs: var openArray[Blob];
                maxBlobs: uint32): uint32 =
  ## Find connected components (blobs) in binary image
  ##
  ## Uses 4-connectivity. Pixels > 128 are considered foreground.
  ##
  ## Parameters:
  ## - img: Input binary/grayscale image
  ## - labels: Output label map (same size as image)
  ## - blobs: Output blob array
  ## - maxBlobs: Maximum number of blobs to detect
  ##
  ## Returns: Number of blobs found
  assert img.isValid, "Image must be valid"
  assert labels.width == img.width and labels.height == img.height,
    "Labels dimensions must match image"
  assert maxBlobs > 0 and blobs.len >= int(maxBlobs),
    "Blob buffer must be large enough"

  let nLabels = maxBlobs + 1

  # Initialize
  labels.clear()

  # Parent array for union-find (stack allocated if small enough)
  var parents = newSeq[Label](nLabels)
  var cx = newSeq[uint32](nLabels) # Centroid x sum
  var cy = newSeq[uint32](nLabels) # Centroid y sum

  for i in 0 ..< int(nLabels):
    parents[i] = Label(i)

  # Initialize blobs
  for i in 0 ..< int(maxBlobs):
    blobs[i] = Blob(
      label: 0,
      area: 0,
      box: Rect(x: high(uint32), y: high(uint32), w: 0, h: 0),
      centroid: Point(x: 0, y: 0)
    )

  var nextLabel: Label = 1

  # First pass: label and union
  for y in 0'u32 ..< img.height:
    for x in 0'u32 ..< img.width:
      # Skip background pixels
      if img[x, y] < BinaryThreshold:
        continue

      # Get left and top neighbor labels
      let left = if x > 0: labels[x - 1, y] else: Label(0)
      let top = if y > 0: labels[x, y - 1] else: Label(0)

      # 4-connectivity: pick smallest from left and top, if any is non-zero
      var n: Label
      if left != 0 and top != 0:
        n = min(left, top)
      elif left != 0:
        n = left
      elif top != 0:
        n = top
      else:
        n = 0

      if n == 0:
        # New component
        if nextLabel > Label(maxBlobs):
          continue # Out of labels

        let idx = nextLabel - 1
        blobs[idx] = Blob(
          label: nextLabel,
          area: 1,
          box: Rect(x: x, y: y, w: x, h: y),  # Store br coords temporarily
          centroid: Point(x: x, y: y)
        )
        cx[nextLabel] = x
        cy[nextLabel] = y
        labels[x, y] = nextLabel
        nextLabel += 1
      else:
        # Existing component
        labels[x, y] = n
        let idx = n - 1

        # Update blob
        cx[n] += x
        cy[n] += y
        blobs[idx].area += 1
        blobs[idx].box.x = min(x, blobs[idx].box.x)
        blobs[idx].box.y = min(y, blobs[idx].box.y)
        blobs[idx].box.w = max(x, blobs[idx].box.w)  # Temporarily store max x
        blobs[idx].box.h = max(y, blobs[idx].box.h)  # Temporarily store max y

        # Union if labels are different
        if left != 0 and top != 0 and left != top:
          let root1 = findRoot(left, parents)
          let root2 = findRoot(top, parents)
          if root1 != root2:
            parents[max(root1, root2)] = min(root1, root2)

  # Merge blobs with same root
  for i in 0'u16 ..< nextLabel - 1:
    let root = findRoot(blobs[i].label, parents)
    if root != blobs[i].label:
      let rootIdx = root - 1
      blobs[rootIdx].area += blobs[i].area
      blobs[rootIdx].box.x = min(blobs[rootIdx].box.x, blobs[i].box.x)
      blobs[rootIdx].box.y = min(blobs[rootIdx].box.y, blobs[i].box.y)
      blobs[rootIdx].box.w = max(blobs[rootIdx].box.w, blobs[i].box.w)
      blobs[rootIdx].box.h = max(blobs[rootIdx].box.h, blobs[i].box.h)
      cx[root] += cx[blobs[i].label]
      cy[root] += cy[blobs[i].label]
      blobs[i].area = 0  # Mark as merged


  # Second pass: update labels to root
  for y in 0'u32 ..< img.height:
    for x in 0'u32 ..< img.width:
      let l = labels[x, y]
      if l != 0:
        labels[x, y] = findRoot(l, parents)

  # Compact blobs and convert box coords to width/height
  var m: uint32 = 0
  for i in 0'u16 ..< nextLabel - 1:
    if blobs[i].area == 0:
      continue

    # Convert box.w/h from max coords to actual width/height
    blobs[i].box.w = blobs[i].box.w - blobs[i].box.x + 1
    blobs[i].box.h = blobs[i].box.h - blobs[i].box.y + 1

    # Calculate centroid
    blobs[i].centroid.x = cx[blobs[i].label] div blobs[i].area
    blobs[i].centroid.y = cy[blobs[i].label] div blobs[i].area

    # Move to compacted position
    blobs[m] = blobs[i]
    m += 1

  m

# ============================================================================
# Blob Corner Detection
# ============================================================================

proc findBlobCorners*(img: ImageView | GrayImage;
                      labels: LabelArray;
                      blob: Blob;
                      corners: var array[4, Point]) =
  ## Find the 4 corners of a blob (useful for quadrilateral detection)
  ##
  ## Corners are found using sum and difference of coordinates:
  ## - Top-left: minimum x + y
  ## - Top-right: maximum x - y
  ## - Bottom-right: maximum x + y
  ## - Bottom-left: minimum x - y
  ##
  ## Output order: [topLeft, topRight, bottomRight, bottomLeft]
  assert img.isValid, "Image must be valid"

  var tl = blob.centroid
  var tr = blob.centroid
  var br = blob.centroid
  var bl = blob.centroid

  var minSum = high(int32)
  var maxSum = low(int32)
  var minDiff = high(int32)
  var maxDiff = low(int32)

  for y in blob.box.y ..< blob.box.bottom:
    for x in blob.box.x ..< blob.box.right:
      # Check if pixel belongs to this blob
      if img[x, y] < BinaryThreshold:
        continue
      if labels[x, y] != blob.label:
        continue

      let sum = int32(x) + int32(y)
      let diff = int32(x) - int32(y)

      if sum < minSum:
        minSum = sum
        tl = Point(x: x, y: y)

      if sum > maxSum:
        maxSum = sum
        br = Point(x: x, y: y)

      if diff < minDiff:
        minDiff = diff
        bl = Point(x: x, y: y)

      if diff > maxDiff:
        maxDiff = diff
        tr = Point(x: x, y: y)

  corners[0] = tl
  corners[1] = tr
  corners[2] = br
  corners[3] = bl

# ============================================================================
# Contour Tracing
# ============================================================================

const
  # 8-connectivity direction offsets (clockwise from right)
  DirDx: array[8, int] = [1, 1, 0, -1, -1, -1, 0, 1]
  DirDy: array[8, int] = [0, 1, 1, 1, 0, -1, -1, -1]

proc traceContour*(img: ImageView | GrayImage;
                   visited: var ImageView | var GrayImage;
                   contour: var Contour) =
  ## Trace contour starting from contour.start
  ##
  ## Uses Moore neighborhood tracing (8-connectivity).
  ## Marks visited pixels in the visited buffer.
  ##
  ## Parameters:
  ## - img: Binary input image
  ## - visited: Buffer to mark visited pixels (same size as img)
  ## - contour: On input, start point should be set; on output, filled with results
  assert img.isValid and visited.isValid, "Images must be valid"
  assert img.width == visited.width and img.height == visited.height,
    "Dimensions must match"

  contour.length = 0
  contour.box = Rect(x: contour.start.x, y: contour.start.y, w: 1, h: 1)

  var p = contour.start
  var dir: uint8 = 7  # Start searching from direction 7 (up-right)
  var seenStart = false

  while true:
    # Mark as visited and increment length if not already visited
    if visited[p.x, p.y] == 0:
      contour.length += 1
    visited[p.x, p.y] = MaxPixel

    # Search for next pixel (start from dir + 1, go clockwise)
    let startDir = (dir + 1) mod 8
    var found = false

    for i in 0 ..< 8:
      let d = (int(startDir) + i) mod 8
      let nx = int(p.x) + DirDx[d]
      let ny = int(p.y) + DirDy[d]

      if img.contains(nx, ny) and img[nx, ny] > BinaryThreshold:
        p = Point(x: uint32(nx), y: uint32(ny))
        dir = uint8((d + 6) mod 8)  # Update backtrack direction
        found = true
        break

    if not found:
      break  # Open contour

    # Update bounding box
    contour.box.x = min(contour.box.x, p.x)
    contour.box.y = min(contour.box.y, p.y)
    contour.box.w = max(contour.box.w, p.x - contour.box.x + 1)
    contour.box.h = max(contour.box.h, p.y - contour.box.y + 1)

    # Check if we returned to start
    if p.x == contour.start.x and p.y == contour.start.y:
      if seenStart:
        break  # Second time at start, contour is closed
      seenStart = true

proc findContourStart*(img: ImageView | GrayImage;
                       roi: Rect): Point =
  ## Find first foreground pixel in region (for contour tracing)
  for y in roi.y ..< roi.bottom:
    for x in roi.x ..< roi.right:
      if img.contains(x, y) and img[x, y] > BinaryThreshold:
        return Point(x: x, y: y)

  Point(x: roi.x, y: roi.y)

# ============================================================================
# Perspective Correction
# ============================================================================

proc perspectiveCorrect*(dst: var ImageView | var GrayImage;
                         src: ImageView | GrayImage;
                         corners: array[4, Point]) =
  ## Apply perspective correction using 4 corner points
  ##
  ## Transforms the quadrilateral defined by corners to fill dst.
  ## Uses bilinear interpolation for smooth results.
  ##
  ## Corner order: [topLeft, topRight, bottomRight, bottomLeft]
  assert dst.isValid and src.isValid, "Images must be valid"

  let w = float32(dst.width - 1)
  let h = float32(dst.height - 1)

  for y in 0'u32 ..< dst.height:
    for x in 0'u32 ..< dst.width:
      let u = float32(x) / w
      let v = float32(y) / h

      # Bilinear interpolation of corner positions
      let topX = float32(corners[0].x) * (1.0'f32 - u) + float32(corners[1].x) * u
      let topY = float32(corners[0].y) * (1.0'f32 - u) + float32(corners[1].y) * u
      let botX = float32(corners[3].x) * (1.0'f32 - u) + float32(corners[2].x) * u
      let botY = float32(corners[3].y) * (1.0'f32 - u) + float32(corners[2].y) * u

      var srcX = topX * (1.0'f32 - v) + botX * v
      var srcY = topY * (1.0'f32 - v) + botY * v

      # Clamp to valid range
      srcX = clamp(srcX, 0.0'f32, float32(src.width - 1))
      srcY = clamp(srcY, 0.0'f32, float32(src.height - 1))

      # Bilinear interpolation for sampling
      let sx = uint32(srcX)
      let sy = uint32(srcY)
      let sx1 = min(sx + 1, src.width - 1)
      let sy1 = min(sy + 1, src.height - 1)

      let dx = srcX - float32(sx)
      let dy = srcY - float32(sy)

      let c00 = float32(src[sx, sy])
      let c01 = float32(src[sx1, sy])
      let c10 = float32(src[sx, sy1])
      let c11 = float32(src[sx1, sy1])

      let pixel = c00 * (1.0'f32 - dx) * (1.0'f32 - dy) +
                  c01 * dx * (1.0'f32 - dy) +
                  c10 * (1.0'f32 - dx) * dy +
                  c11 * dx * dy

      dst[x, y] = uint8(clamp(pixel, 0.0'f32, 255.0'f32))

# ============================================================================
# Utility Functions
# ============================================================================

proc findLargestBlob*(blobs: openArray[Blob]; count: uint32): int =
  ## Find index of largest blob by area
  ## Returns -1 if count is 0
  if count == 0:
    return -1

  var largestIdx = 0
  var largestArea = blobs[0].area

  for i in 1 ..< int(count):
    if blobs[i].area > largestArea:
      largestArea = blobs[i].area
      largestIdx = i

  largestIdx

proc filterBlobsByArea*(blobs: var openArray[Blob];
                        count: uint32;
                        minArea: uint32;
                        maxArea: uint32 = high(uint32)): uint32 =
  ## Filter blobs by area, compacting the array
  ## Returns new count
  var writeIdx: uint32 = 0

  for i in 0'u32 ..< count:
    if blobs[i].area >= minArea and blobs[i].area <= maxArea:
      if writeIdx != i:
        blobs[writeIdx] = blobs[i]
      writeIdx += 1

  writeIdx

{.pop.} # raises: []
