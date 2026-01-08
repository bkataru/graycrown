## graycrown/filters - Image filtering operations
##
## This module provides filtering and thresholding operations:
## - Histogram computation
## - Global thresholding (manual and Otsu's method)
## - Adaptive thresholding
## - Box blur
## - Sobel edge detection
## - Generic convolution

{.push raises: [].}

import ./core

# ============================================================================
# Histogram Operations
# ============================================================================

type
  Histogram* = array[256, uint32]
    ## Histogram with 256 bins (one per intensity level)

proc computeHistogram*(img: ImageView | GrayImage; hist: var Histogram) =
  ## Compute intensity histogram of image
  assert img.isValid, "Image must be valid"

  # Clear histogram
  for i in 0 ..< 256:
    hist[i] = 0

  # Count pixels
  for i in 0'u32 ..< img.size:
    hist[img.data[i]] += 1

proc computeHistogram*(img: ImageView | GrayImage): Histogram =
  ## Compute and return histogram
  img.computeHistogram(result)

proc minValue*(hist: Histogram): uint8 =
  ## Find minimum non-zero intensity in histogram
  for i in 0 ..< 256:
    if hist[i] > 0:
      return uint8(i)
  return 0

proc maxValue*(hist: Histogram): uint8 =
  ## Find maximum non-zero intensity in histogram
  for i in countdown(255, 0):
    if hist[i] > 0:
      return uint8(i)
  return 255

proc mean*(hist: Histogram): float32 =
  ## Compute mean intensity from histogram
  var sum: uint64 = 0
  var count: uint64 = 0
  for i in 0 ..< 256:
    sum += uint64(i) * uint64(hist[i])
    count += uint64(hist[i])
  if count == 0: 0.0'f32
  else: float32(sum) / float32(count)

# ============================================================================
# Thresholding
# ============================================================================

proc threshold*(img: var ImageView | var GrayImage; thresh: uint8) =
  ## Apply global threshold in-place
  ## Pixels > thresh become 255, others become 0
  assert img.isValid, "Image must be valid"

  for i in 0'u32 ..< img.size:
    img.data[i] = if img.data[i] > thresh: MaxPixel else: MinPixel

proc threshold*(dst: var ImageView | var GrayImage;
                src: ImageView | GrayImage;
                thresh: uint8) =
  ## Apply global threshold from source to destination
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for i in 0'u32 ..< dst.size:
    dst.data[i] = if src.data[i] > thresh: MaxPixel else: MinPixel

proc otsuThreshold*(img: ImageView | GrayImage): uint8 =
  ## Compute optimal threshold using Otsu's method
  ## Returns the threshold value that maximizes inter-class variance
  assert img.isValid, "Image must be valid"

  var hist: Histogram
  img.computeHistogram(hist)

  let totalPixels = img.size
  if totalPixels == 0:
    return 0

  # Compute cumulative sum for mean calculation
  var sum: float32 = 0.0'f32
  for i in 0 ..< 256:
    sum += float32(i) * float32(hist[i])

  var sumB: float32 = 0.0'f32
  var wB: uint32 = 0  # Weight background
  var wF: uint32 = 0  # Weight foreground
  var varMax: float32 = -1.0'f32
  var threshold: uint8 = 0

  for t in 0 ..< 256:
    wB += hist[t]  # Background weight
    if wB == 0:
      continue

    wF = totalPixels - wB  # Foreground weight
    if wF == 0:
      break

    sumB += float32(t) * float32(hist[t])

    let mB = sumB / float32(wB)  # Background mean
    let mF = (sum - sumB) / float32(wF)  # Foreground mean

    # Inter-class variance
    let varBetween = float32(wB) * float32(wF) * (mB - mF) * (mB - mF)

    if varBetween > varMax:
      varMax = varBetween
      threshold = uint8(t)

  threshold

proc applyOtsuThreshold*(img: var ImageView | var GrayImage) =
  ## Apply Otsu's method to compute and apply threshold in-place
  let thresh = otsuThreshold(img)
  threshold(img, thresh)

# ============================================================================
# Adaptive Thresholding
# ============================================================================

proc adaptiveThreshold*(dst: var ImageView | var GrayImage;
                        src: ImageView | GrayImage;
                        radius: uint32;
                        c: int = 0) =
  ## Apply adaptive (local) thresholding
  ##
  ## For each pixel, computes mean in neighborhood of given radius,
  ## then thresholds: pixel > (local_mean - c) becomes 255, else 0
  ##
  ## Parameters:
  ## - radius: neighborhood size (e.g., 1 means 3x3 window)
  ## - c: constant subtracted from local mean
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert dst.isValid and src.isValid, "Images must be valid"

  let radiusInt = int(radius)

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var sum: uint32 = 0
      var count: uint32 = 0

      # Compute local mean
      for dy in -radiusInt .. radiusInt:
        for dx in -radiusInt .. radiusInt:
          let sy = int(y) + dy
          let sx = int(x) + dx

          if src.contains(sx, sy):
            sum += uint32(src[sx, sy])
            count += 1

      let localMean = int(sum div count)
      let thresh = localMean - c

      dst[x, y] = if int(src[x, y]) > thresh: MaxPixel else: MinPixel

# ============================================================================
# Blur Operations
# ============================================================================

proc boxBlur*(dst: var ImageView | var GrayImage;
              src: ImageView | GrayImage;
              radius: uint32) =
  ## Apply box blur (mean filter) with given radius
  ## Window size is (2*radius + 1) x (2*radius + 1)
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert dst.isValid and src.isValid, "Images must be valid"

  let radiusInt = int(radius)

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var sum: uint32 = 0
      var count: uint32 = 0

      for dy in -radiusInt .. radiusInt:
        for dx in -radiusInt .. radiusInt:
          let sy = int(y) + dy
          let sx = int(x) + dx

          if src.contains(sx, sy):
            sum += uint32(src[sx, sy])
            count += 1

      dst[x, y] = uint8(sum div count)

proc blur*(dst: var ImageView | var GrayImage;
           src: ImageView | GrayImage;
           radius: uint32) {.inline.} =
  ## Alias for boxBlur
  boxBlur(dst, src, radius)

# Optimized separable box blur for large radii
proc boxBlurSeparable*(dst: var ImageView | var GrayImage;
                       src: ImageView | GrayImage;
                       temp: var ImageView | var GrayImage;
                       radius: uint32) =
  ## Separable box blur using temporary buffer
  ## More efficient for larger radii (O(n) vs O(n²))
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert temp.width == src.width and temp.height == src.height,
    "Temp buffer dimensions must match"

  let radiusInt = int(radius)
  let windowSize = 2 * radius + 1

  # Horizontal pass (src -> temp)
  for y in 0'u32 ..< src.height:
    var sum: uint32 = 0
    var count: uint32 = 0

    # Initialize window
    for dx in -radiusInt .. radiusInt:
      if src.contains(dx, int(y)):
        sum += uint32(src[dx, int(y)])
        count += 1

    for x in 0'u32 ..< src.width:
      temp[x, y] = uint8(sum div count)

      # Slide window
      let leftX = int(x) - radiusInt
      let rightX = int(x) + radiusInt + 1

      if src.contains(leftX, int(y)):
        sum -= uint32(src[leftX, int(y)])
        count -= 1

      if src.contains(rightX, int(y)):
        sum += uint32(src[rightX, int(y)])
        count += 1

  # Vertical pass (temp -> dst)
  for x in 0'u32 ..< src.width:
    var sum: uint32 = 0
    var count: uint32 = 0

    # Initialize window
    for dy in -radiusInt .. radiusInt:
      if temp.contains(int(x), dy):
        sum += uint32(temp[int(x), dy])
        count += 1

    for y in 0'u32 ..< src.height:
      dst[x, y] = uint8(sum div count)

      # Slide window
      let topY = int(y) - radiusInt
      let bottomY = int(y) + radiusInt + 1

      if temp.contains(int(x), topY):
        sum -= uint32(temp[int(x), topY])
        count -= 1

      if temp.contains(int(x), bottomY):
        sum += uint32(temp[int(x), bottomY])
        count += 1

# ============================================================================
# Convolution
# ============================================================================

type
  Kernel3x3* = array[9, int8]
    ## 3x3 convolution kernel (row-major order)

  Kernel5x5* = array[25, int8]
    ## 5x5 convolution kernel

const
  KernelSharpen*: Kernel3x3 = [0'i8, -1, 0, -1, 5, -1, 0, -1, 0]
  KernelEmboss*: Kernel3x3 = [-2'i8, -1, 0, -1, 1, 1, 0, 1, 2]
  KernelBlurBox*: Kernel3x3 = [1'i8, 1, 1, 1, 1, 1, 1, 1, 1]
  KernelBlurGaussian*: Kernel3x3 = [1'i8, 2, 1, 2, 4, 2, 1, 2, 1]
  KernelEdgeDetect*: Kernel3x3 = [-1'i8, -1, -1, -1, 8, -1, -1, -1, -1]

proc convolve3x3*(dst: var ImageView | var GrayImage;
                  src: ImageView | GrayImage;
                  kernel: Kernel3x3;
                  normFactor: uint32 = 1) =
  ## Apply 3x3 convolution kernel
  ## Result is divided by normFactor (e.g., 9 for box blur, 16 for Gaussian)
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert normFactor > 0, "Norm factor must be positive"

  for y in 0'u32 ..< src.height:
    for x in 0'u32 ..< src.width:
      var sum: int32 = 0
      var idx = 0

      for ky in -1 .. 1:
        for kx in -1 .. 1:
          sum += int32(src[int(x) + kx, int(y) + ky]) * int32(kernel[idx])
          idx += 1

      sum = sum div int32(normFactor)
      dst[x, y] = uint8(clamp(sum, 0'i32, 255'i32))

# ============================================================================
# Sobel Edge Detection
# ============================================================================

proc sobel*(dst: var ImageView | var GrayImage;
            src: ImageView | GrayImage) =
  ## Apply Sobel edge detection
  ## Computes gradient magnitude at each pixel
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"
  assert dst.isValid and src.isValid, "Images must be valid"

  # Clear borders (Sobel needs 1-pixel margin)
  for x in 0'u32 ..< dst.width:
    dst[x, 0] = 0
    dst[x, dst.height - 1] = 0
  for y in 0'u32 ..< dst.height:
    dst[0, y] = 0
    dst[dst.width - 1, y] = 0

  # Process interior pixels
  for y in 1'u32 ..< src.height - 1:
    for x in 1'u32 ..< src.width - 1:
      # Sobel X kernel: [-1 0 1; -2 0 2; -1 0 1]
      let gx = -int32(src[x - 1, y - 1]) + int32(src[x + 1, y - 1]) -
               2 * int32(src[x - 1, y]) + 2 * int32(src[x + 1, y]) -
               int32(src[x - 1, y + 1]) + int32(src[x + 1, y + 1])

      # Sobel Y kernel: [-1 -2 -1; 0 0 0; 1 2 1]
      let gy = -int32(src[x - 1, y - 1]) - 2 * int32(src[x, y - 1]) -
               int32(src[x + 1, y - 1]) +
               int32(src[x - 1, y + 1]) + 2 * int32(src[x, y + 1]) +
               int32(src[x + 1, y + 1])

      # Approximate magnitude using L1 norm (faster than sqrt)
      let magnitude = (abs(gx) + abs(gy)) div 2

      dst[x, y] = uint8(clamp(magnitude, 0'i32, 255'i32))

proc sobelGradient*(dst: var ImageView | var GrayImage;
                    gradX: var ImageView | var GrayImage;
                    gradY: var ImageView | var GrayImage;
                    src: ImageView | GrayImage) =
  ## Compute Sobel gradients with separate X and Y components
  ## Useful when gradient direction is needed
  assert dst.width == src.width and dst.height == src.height,
    "Dimensions must match"

  for y in 1'u32 ..< src.height - 1:
    for x in 1'u32 ..< src.width - 1:
      let gx = -int32(src[x - 1, y - 1]) + int32(src[x + 1, y - 1]) -
               2 * int32(src[x - 1, y]) + 2 * int32(src[x + 1, y]) -
               int32(src[x - 1, y + 1]) + int32(src[x + 1, y + 1])

      let gy = -int32(src[x - 1, y - 1]) - 2 * int32(src[x, y - 1]) -
               int32(src[x + 1, y - 1]) +
               int32(src[x - 1, y + 1]) + 2 * int32(src[x, y + 1]) +
               int32(src[x + 1, y + 1])

      gradX[x, y] = uint8(clamp(gx div 4 + 128, 0'i32, 255'i32))
      gradY[x, y] = uint8(clamp(gy div 4 + 128, 0'i32, 255'i32))

      let magnitude = (abs(gx) + abs(gy)) div 2
      dst[x, y] = uint8(clamp(magnitude, 0'i32, 255'i32))

# ============================================================================
# Contrast Operations
# ============================================================================

proc stretchContrast*(img: var ImageView | var GrayImage) =
  ## Stretch contrast to use full [0, 255] range
  assert img.isValid, "Image must be valid"

  # Find min and max
  var minVal: uint8 = 255
  var maxVal: uint8 = 0

  for i in 0'u32 ..< img.size:
    if img.data[i] < minVal: minVal = img.data[i]
    if img.data[i] > maxVal: maxVal = img.data[i]

  if maxVal <= minVal:
    return  # No contrast to stretch

  let range = float32(maxVal - minVal)

  for i in 0'u32 ..< img.size:
    let normalized = float32(img.data[i] - minVal) / range * 255.0'f32
    img.data[i] = uint8(clamp(normalized, 0.0'f32, 255.0'f32))

proc adjustBrightness*(img: var ImageView | var GrayImage; delta: int) =
  ## Adjust brightness by adding delta to all pixels
  for i in 0'u32 ..< img.size:
    let newVal = int(img.data[i]) + delta
    img.data[i] = uint8(clamp(newVal, 0, 255))

proc adjustContrast*(img: var ImageView | var GrayImage; factor: float32) =
  ## Adjust contrast by scaling around midpoint (128)
  for i in 0'u32 ..< img.size:
    let val = float32(img.data[i])
    let newVal = (val - 128.0'f32) * factor + 128.0'f32
    img.data[i] = uint8(clamp(newVal, 0.0'f32, 255.0'f32))

{.pop.} # raises: []
