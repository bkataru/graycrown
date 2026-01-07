## graycrown/features - Feature detection and description
##
## This module provides:
## - FAST corner detection
## - ORB feature extraction (Oriented FAST with rotated BRIEF)
## - Feature matching

{.push raises: [].}

import ./core
import ./image

# ============================================================================
# FAST Corner Detection
# ============================================================================

const
  # Bresenham circle of radius 3 (16 pixels)
  FastDx: array[16, int] = [0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3, -3, -3, -2, -1]
  FastDy: array[16, int] = [-3, -3, -2, -1, 0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3]

proc fastCorner*(
    img: ImageView | GrayImage,
    scoremap: var ImageView | var GrayImage,
    keypoints: var openArray[Keypoint],
    maxKeypoints: uint32,
    threshold: uint32,
): uint32 =
  ## FAST corner detection (Features from Accelerated Segment Test)
  ##
  ## Detects corners where at least 9 contiguous pixels on a Bresenham
  ## circle of radius 3 are all brighter or all darker than the center.
  ##
  ## Parameters:
  ## - img: Input grayscale image
  ## - scoremap: Output score map (same size as img, used for NMS)
  ## - keypoints: Output array of detected keypoints
  ## - maxKeypoints: Maximum number of keypoints to return
  ## - threshold: Intensity difference threshold (typically 10-30)
  ##
  ## Returns: Number of keypoints detected
  assert img.isValid and scoremap.isValid, "Images must be valid"
  assert img.width == scoremap.width and img.height == scoremap.height,
    "Dimensions must match"
  assert maxKeypoints > 0 and keypoints.len >= int(maxKeypoints),
    "Keypoint buffer must be large enough"

  let thresh = int(threshold)
  var nKeypoints: uint32 = 0

  # Clear scoremap
  for i in 0'u32 ..< scoremap.size:
    scoremap.data[i] = 0

  # First pass: compute score map
  for y in 3'u32 ..< img.height - 3:
    for x in 3'u32 ..< img.width - 3:
      let p = int(img[x, y])
      var run = 0
      var score = 0

      # Extended loop for wraparound detection
      for i in 0 ..< 16 + 9:
        let idx = i mod 16
        let v = int(img[int(x) + FastDx[idx], int(y) + FastDy[idx]])

        if v > p + thresh:
          run =
            if run > 0:
              run + 1
            else:
              1
        elif v < p - thresh:
          run =
            if run < 0:
              run - 1
            else:
              -1
        else:
          run = 0

        # Need 9 contiguous pixels
        if run >= 9 or run <= -9:
          # Compute corner score (minimum difference)
          score = 255
          for j in 0 ..< 16:
            let d = abs(int(img[int(x) + FastDx[j], int(y) + FastDy[j]]) - p)
            if d < score:
              score = d
          break

      scoremap[x, y] = uint8(score)

  # Second pass: non-maximum suppression
  for y in 3'u32 ..< img.height - 3:
    for x in 3'u32 ..< img.width - 3:
      let s = int(scoremap[x, y])
      if s == 0:
        continue

      var isMax = true
      for dy in -1 .. 1:
        for dx in -1 .. 1:
          if dx == 0 and dy == 0:
            continue
          if int(scoremap[int(x) + dx, int(y) + dy]) > s:
            isMax = false
            break
        if not isMax:
          break

      if isMax and nKeypoints < maxKeypoints:
        keypoints[nKeypoints] = Keypoint(
          pt: Point(x: x, y: y),
          response: uint32(s),
          angle: 0.0'f32,
          descriptor: [0'u32, 0, 0, 0, 0, 0, 0, 0],
        )
        nKeypoints += 1

  nKeypoints

# ============================================================================
# ORB Feature Extraction
# ============================================================================

const
  # BRIEF pattern (256 pairs of test points)
  # Generated using Gaussian distribution with σ = 2.5 * patch_size / 5
  BriefPattern: array[256, array[4, int8]] = [
    [1'i8, 0, 1, 3],
    [0'i8, 0, 3, 2],
    [-1'i8, 1, -1, -1],
    [0'i8, -4, -3, -1],
    [-2'i8, 1, -2, -3],
    [3'i8, 0, 0, -3],
    [-1'i8, 0, -2, 1],
    [-1'i8, -1, -1, 4],
    [0'i8, -2, 2, -2],
    [0'i8, -4, -3, 0],
    [1'i8, 0, 0, -1],
    [-3'i8, -1, -1, 2],
    [1'i8, -4, 1, -1],
    [-1'i8, 1, 2, 2],
    [-2'i8, -1, 1, 2],
    [-1'i8, 0, -2, -2],
    [2'i8, 3, 0, 2],
    [1'i8, -1, 1, 3],
    [0'i8, 3, -5, 2],
    [0'i8, -1, 0, -4],
    [0'i8, 1, 3, -1],
    [-2'i8, -1, 2, 1],
    [-1'i8, 1, 0, 2],
    [-1'i8, -1, -1, -3],
    [1'i8, 1, 0, 0],
    [-3'i8, -1, -1, -2],
    [0'i8, 1, 4, 0],
    [1'i8, 0, -4, 0],
    [0'i8, 5, 0, 1],
    [0'i8, -2, 2, 2],
    [2'i8, -2, 3, -3],
    [1'i8, 4, -2, -1],
    [0'i8, -1, -3, 0],
    [-2'i8, 1, -2, 3],
    [-2'i8, -1, 2, -2],
    [0'i8, 3, -3, 0],
    [1'i8, 2, -2, -3],
    [1'i8, 1, 1, 1],
    [-1'i8, 0, 1, -1],
    [4'i8, 1, -2, 1],
    [-2'i8, 2, 2, -2],
    [2'i8, 1, 2, 4],
    [0'i8, -2, -2, -2],
    [0'i8, 1, 1, 2],
    [0'i8, 3, -1, 5],
    [1'i8, -2, -2, 1],
    [0'i8, 1, 1, 0],
    [-2'i8, -3, -1, 2],
    [0'i8, -2, 0, 1],
    [-2'i8, 0, 0, -2],
    [1'i8, 1, 2, 2],
    [-3'i8, -2, 1, 1],
    [1'i8, 8, 1, 2],
    [2'i8, 1, -1, 2],
    [-2'i8, 0, -1, 0],
    [5'i8, -4, 1, -3],
    [-1'i8, 2, 0, -2],
    [-1'i8, 1, -1, 0],
    [0'i8, -1, 4, 1],
    [-4'i8, 0, -1, 2],
    [-2'i8, 0, 1, 2],
    [-2'i8, -1, -1, -1],
    [4'i8, 1, -3, 2],
    [4'i8, 2, -3, -1],
    [3'i8, -1, 1, 2],
    [-2'i8, 0, -6, -2],
    [-1'i8, -2, 3, -3],
    [-1'i8, 0, 3, -3],
    [2'i8, 0, -2, 1],
    [0'i8, -1, 0, -1],
    [0'i8, 1, 3, -2],
    [4'i8, -4, 0, 1],
    [1'i8, -1, 0, -1],
    [-1'i8, 2, 1, -1],
    [2'i8, 1, 2, 1],
    [-2'i8, -1, 1, 1],
    [0'i8, 0, 3, -1],
    [1'i8, 0, 0, 2],
    [2'i8, 2, 3, 0],
    [1'i8, -1, 1, 0],
    [0'i8, 1, -2, 4],
    [-2'i8, -2, 2, 2],
    [1'i8, 1, 0, -2],
    [0'i8, -1, 2, 0],
    [-2'i8, -1, 1, -1],
    [-2'i8, 0, 0, -1],
    [-1'i8, 0, -3, -3],
    [-1'i8, 0, 1, 3],
    [2'i8, 0, 0, -2],
    [0'i8, -1, 1, -2],
    [1'i8, 3, 0, 1],
    [1'i8, -1, 0, 0],
    [0'i8, -2, 0, 1],
    [3'i8, 2, 4, -2],
    [2'i8, 0, 4, -2],
    [-2'i8, -1, -4, -1],
    [-2'i8, 0, 1, 4],
    [2'i8, -1, -2, 1],
    [-3'i8, 4, 2, -1],
    [-3'i8, 3, 0, 2],
    [-3'i8, -1, 0, 0],
    [-1'i8, 1, -2, 0],
    [0'i8, 1, 1, -2],
    [-3'i8, 3, 1, -1],
    [3'i8, 0, 2, 0],
    [4'i8, 4, 0, 2],
    [1'i8, 3, -2, 1],
    [2'i8, -4, -2, -4],
    [-1'i8, 1, 3, 0],
    [3'i8, -3, -3, 0],
    [1'i8, 0, -4, 0],
    [-3'i8, 1, 1, -2],
    [-1'i8, -2, 0, 2],
    [-2'i8, 1, -1, -2],
    [0'i8, -2, -1, -2],
    [4'i8, 0, -1, 0],
    [0'i8, 0, 1, 2],
    [-1'i8, -1, -1, -5],
    [-3'i8, 3, 3, 0],
    [1'i8, 1, 6, 2],
    [0'i8, -2, -3, 0],
    [-2'i8, -3, -1, -2],
    [3'i8, 2, 0, 3],
    [0'i8, -2, 3, 1],
    [-2'i8, 0, -2, -3],
    [2'i8, 4, -3, 1],
    [-1'i8, -1, -1, -2],
    [0'i8, -2, 1, 0],
    [15'i8, -10, -14, 4],
    [12'i8, -5, -12, -1],
    [-10'i8, 6, 1, 14],
    [8'i8, -10, 3, 14],
    [9'i8, -14, -1, -5],
    [-8'i8, 10, 3, -3],
    [-4'i8, -11, -10, 10],
    [6'i8, -12, 3, 4],
    [-15'i8, 4, 1, -4],
    [-1'i8, -15, 10, -2],
    [-10'i8, -11, 14, -5],
    [15'i8, -12, -3, -5],
    [-13'i8, -15, -10, 2],
    [8'i8, -6, -11, 7],
    [-6'i8, -4, -14, -3],
    [-8'i8, -14, 4, -15],
    [15'i8, -11, -7, 1],
    [-7'i8, -5, -1, 8],
    [-10'i8, 7, -13, 14],
    [15'i8, 1, -11, 14],
    [12'i8, -4, 2, -2],
    [5'i8, 8, -5, -7],
    [-14'i8, -4, -13, -13],
    [-15'i8, -8, 6, 12],
    [13'i8, -8, -5, -7],
    [-11'i8, -2, 12, 14],
    [-13'i8, 5, -11, -11],
    [3'i8, 11, -2, 10],
    [14'i8, -12, 9, -3],
    [-6'i8, 9, 2, -8],
    [-8'i8, -9, -8, -2],
    [3'i8, 13, -10, -15],
    [7'i8, 15, -1, -15],
    [9'i8, 1, -15, -1],
    [7'i8, -14, -2, 5],
    [-8'i8, -8, 3, -9],
    [3'i8, -10, -10, -13],
    [-9'i8, 3, -8, -6],
    [4'i8, -1, -1, 13],
    [-15'i8, 4, 14, -9],
    [11'i8, -12, 13, -10],
    [9'i8, -15, 13, -11],
    [11'i8, 7, -15, 14],
    [-12'i8, 6, -14, -6],
    [-11'i8, 11, -6, -15],
    [6'i8, -10, -3, 15],
    [-1'i8, -12, -3, 8],
    [4'i8, 8, -1, 13],
    [-8'i8, -11, 13, -1],
    [-12'i8, -4, -3, -14],
    [11'i8, 15, 3, 3],
    [-12'i8, -12, 10, -5],
    [11'i8, -11, 4, -5],
    [14'i8, -6, -8, -10],
    [-10'i8, -8, 7, -1],
    [10'i8, -2, -5, -4],
    [10'i8, -3, -8, 14],
    [2'i8, 9, -15, -1],
    [-8'i8, 12, -5, -4],
    [-4'i8, -12, 0, -12],
    [-11'i8, 8, -11, -8],
    [15'i8, -6, 1, 12],
    [15'i8, 10, -7, 6],
    [3'i8, 13, -2, -8],
    [11'i8, -7, 0, 3],
    [1'i8, 3, -6, 11],
    [1'i8, 5, -7, 7],
    [3'i8, 11, -10, -7],
    [-2'i8, 1, 12, -6],
    [-7'i8, 1, -12, -7],
    [1'i8, -1, -4, -2],
    [3'i8, 1, 1, -5],
    [1'i8, 5, -4, 0],
    [-14'i8, 4, 6, -7],
    [3'i8, 8, -2, 5],
    [-6'i8, 3, -7, 10],
    [-5'i8, -5, 3, -5],
    [-3'i8, 9, -11, -2],
    [-8'i8, 1, 1, -8],
    [-1'i8, 2, 0, -2],
    [4'i8, -3, 3, -8],
    [8'i8, -12, -11, 7],
    [0'i8, 9, -4, 0],
    [-5'i8, 8, 7, -6],
    [-2'i8, -9, 12, -1],
    [3'i8, -9, 14, -5],
    [-2'i8, 2, 5, 3],
    [-1'i8, -10, 9, 9],
    [-8'i8, -10, 9, -6],
    [-5'i8, 8, -8, 10],
    [1'i8, -1, 1, -6],
    [4'i8, -5, 4, -1],
    [9'i8, 8, 9, -1],
    [3'i8, 7, -8, -1],
    [-4'i8, -11, 1, 7],
    [-9'i8, 5, 2, -2],
    [-4'i8, -10, -12, -2],
    [-12'i8, 0, -2, 1],
    [-1'i8, -8, 2, 2],
    [0'i8, 5, 0, 11],
    [-10'i8, 0, 5, -8],
    [1'i8, -7, -4, 5],
    [6'i8, 13, 0, -2],
    [1'i8, -2, 6, -4],
    [-9'i8, -7, -11, 9],
    [9'i8, 11, -1, 8],
    [4'i8, 7, 7, -11],
    [8'i8, 12, -10, 2],
    [-3'i8, 5, -2, -7],
    [-9'i8, 2, 2, 1],
    [1'i8, 0, 1, 1],
    [2'i8, -5, 4, -14],
    [-11'i8, -1, 2, -1],
    [-7'i8, -9, -2, -11],
    [10'i8, -1, -8, -11],
    [10'i8, 3, 10, 3],
    [9'i8, 0, -9, 1],
    [4'i8, 4, 4, 11],
    [-2'i8, 1, 0, -12],
    [-2'i8, 0, -5, -7],
    [-7'i8, 8, -9, 1],
    [-13'i8, -3, -6, 4],
    [3'i8, -9, -4, -7],
    [-11'i8, -1, 5, -5],
    [-7'i8, 2, 15, 0],
    [-3'i8, 2, 13, 6],
    [1'i8, 0, 2, 1],
    [-7'i8, -4, -4, 3],
  ]

proc computeOrientation*(
    img: ImageView | GrayImage, x, y: uint32, radius: uint32 = 15
): float32 =
  ## Compute patch orientation using intensity centroid method
  ## Returns angle in radians
  assert img.isValid, "Image must be valid"

  var m01: float32 = 0.0
  var m10: float32 = 0.0
  let radiusInt = int(radius)
  let radiusSq = int(radius * radius)

  for dy in -radiusInt .. radiusInt:
    for dx in -radiusInt .. radiusInt:
      # Circular mask
      if dx * dx + dy * dy <= radiusSq:
        let intensity = float32(img[int(x) + dx, int(y) + dy])
        m01 += float32(dy) * intensity
        m10 += float32(dx) * intensity

  atan2Approx(m01, m10)

proc computeBriefDescriptor*(img: ImageView | GrayImage, kp: var Keypoint) =
  ## Compute rotated BRIEF descriptor for a keypoint
  ## Assumes kp.angle has been computed
  assert img.isValid, "Image must be valid"

  let x = int(kp.pt.x)
  let y = int(kp.pt.y)
  let angle = kp.angle
  let sinA = sinApprox(angle)
  let cosA = cosApprox(angle)

  # Clear descriptor
  for i in 0 ..< 8:
    kp.descriptor[i] = 0

  # Compute 256-bit descriptor
  for i in 0 ..< 256:
    # Rotate pattern points by keypoint angle
    let dx1 = float32(BriefPattern[i][0]) * cosA - float32(BriefPattern[i][1]) * sinA
    let dy1 = float32(BriefPattern[i][0]) * sinA + float32(BriefPattern[i][1]) * cosA
    let dx2 = float32(BriefPattern[i][2]) * cosA - float32(BriefPattern[i][3]) * sinA
    let dy2 = float32(BriefPattern[i][2]) * sinA + float32(BriefPattern[i][3]) * cosA

    let x1 = x + int(dx1)
    let y1 = y + int(dy1)
    let x2 = x + int(dx2)
    let y2 = y + int(dy2)

    let intensity1 = img[x1, y1]
    let intensity2 = img[x2, y2]

    if intensity1 > intensity2:
      kp.descriptor[i div 32] = kp.descriptor[i div 32] or (1'u32 shl uint32(i mod 32))

proc sortKeypointsByResponse(kps: var openArray[Keypoint], n: uint32) =
  ## Sort keypoints by response (descending) using bubble sort
  ## Simple but sufficient for small arrays
  for i in 0'u32 ..< n - 1:
    for j in 0'u32 ..< n - 1 - i:
      if kps[j].response < kps[j + 1].response:
        swap(kps[j], kps[j + 1])

proc extractOrb*(
    img: ImageView | GrayImage,
    keypoints: var openArray[Keypoint],
    maxKeypoints: uint32,
    threshold: uint32,
    scoremapBuffer: var openArray[Pixel],
): uint32 =
  ## Extract ORB features (FAST + rotated BRIEF)
  ##
  ## Parameters:
  ## - img: Input grayscale image
  ## - keypoints: Output keypoint array
  ## - maxKeypoints: Maximum number of keypoints
  ## - threshold: FAST threshold
  ## - scoremapBuffer: Temporary buffer (same size as image)
  ##
  ## Returns: Number of keypoints extracted
