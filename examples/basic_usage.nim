## graycrown - Basic Usage Example
##
## This example demonstrates common image processing operations.
## Run with: nimble example

import ../src/graycrown

proc main() =
  echo "graycrown Basic Usage Example"
  echo "============================"
  echo ""

  # =========================================================================
  # 1. Creating Images
  # =========================================================================
  echo "1. Creating Images"

  # Create a new 100x100 grayscale image (zeroed)
  var img = newGrayImage(100, 100)
  echo "   Created ", img.width, "x", img.height, " image"

  # Fill with a value
  fill(img, 128)
  echo "   Filled with gray (128)"

  # Access pixels
  img[50, 50] = 255  # Set center pixel to white
  let pixel = img[50, 50]
  echo "   Center pixel value: ", pixel

  # =========================================================================
  # 2. Image Operations
  # =========================================================================
  echo ""
  echo "2. Image Operations"

  # Create a gradient image
  var gradient = newGrayImage(100, 100)
  for y in 0'u32 ..< 100:
    for x in 0'u32 ..< 100:
      gradient[x, y] = uint8((x + y) div 2)  # Diagonal gradient
  echo "   Created gradient image"

  # Resize
  var small = newGrayImage(50, 50)
  resize(small, gradient.toView)
  echo "   Resized to 50x50 using bilinear interpolation"

  # Crop
  var cropped = newGrayImage(30, 30)
  crop(cropped, gradient.toView, 10, 10, 30, 30)
  echo "   Cropped 30x30 region from (10,10)"

  # Flip
  var flipped = newGrayImage(100, 100)
  flipHorizontal(flipped, gradient.toView)
  echo "   Flipped horizontally"

  # =========================================================================
  # 3. Filtering
  # =========================================================================
  echo ""
  echo "3. Filtering"

  # Create test image with noise
  var noisy = newGrayImage(100, 100)
  for y in 0'u32 ..< 100:
    for x in 0'u32 ..< 100:
      noisy[x, y] = if (x + y) mod 7 == 0: 200'u8 else: 100'u8

  # Box blur
  var blurred = newGrayImage(100, 100)
  blur(blurred, noisy.toView, 2)
  echo "   Applied box blur with radius 2"

  # Create bimodal image for thresholding
  var bimodal = newGrayImage(100, 100)
  for y in 0'u32 ..< 100:
    for x in 0'u32 ..< 100:
      bimodal[x, y] = if x < 50: 50'u8 else: 200'u8

  # Otsu's threshold
  let thresh = otsuThreshold(bimodal.toView)
  echo "   Otsu threshold: ", thresh

  # Apply threshold
  var binary = newGrayImage(100, 100)
  copy(binary, bimodal.toView)
  threshold(binary, thresh)
  echo "   Applied threshold"

  # Adaptive threshold
  var adaptive = newGrayImage(100, 100)
  adaptiveThreshold(adaptive, bimodal.toView, 5, 5)
  echo "   Applied adaptive threshold (radius=5, C=5)"

  # Sobel edge detection
  var edges = newGrayImage(100, 100)
  sobel(edges, gradient.toView)
  echo "   Applied Sobel edge detection"

  # =========================================================================
  # 4. Morphological Operations
  # =========================================================================
  echo ""
  echo "4. Morphological Operations"

  # Create binary pattern
  var pattern = newGrayImage(20, 20)
  for y in 5'u32 ..< 15:
    for x in 5'u32 ..< 15:
      pattern[x, y] = 255

  # Erosion
  var eroded = newGrayImage(20, 20)
  erode(eroded, pattern.toView)
  echo "   Applied erosion"

  # Dilation
  var dilated = newGrayImage(20, 20)
  dilate(dilated, pattern.toView)
  echo "   Applied dilation"

  # Opening (erosion + dilation)
  var temp = newGrayImage(20, 20)
  var opened = newGrayImage(20, 20)
  morphOpen(opened, pattern.toView, temp)
  echo "   Applied opening"

  # Closing (dilation + erosion)
  var closed = newGrayImage(20, 20)
  morphClose(closed, pattern.toView, temp)
  echo "   Applied closing"

  # =========================================================================
  # 5. Connected Components (Blob Detection)
  # =========================================================================
  echo ""
  echo "5. Blob Detection"

  # Create image with multiple blobs
  var blobImg = newGrayImage(50, 50)
  # Blob 1
  for y in 5'u32 ..< 15:
    for x in 5'u32 ..< 15:
      blobImg[x, y] = 255
  # Blob 2
  for y in 20'u32 ..< 30:
    for x in 30'u32 ..< 45:
      blobImg[x, y] = 255

  var labels: array[2500, Label]
  var labelArr = initLabelArray(labels, 50, 50)
  var blobs: array[10, Blob]

  let nBlobs = findBlobs(blobImg.toView, labelArr, blobs, 10)
  echo "   Found ", nBlobs, " blobs"
  for i in 0 ..< int(nBlobs):
    echo "   Blob ", i, ": area=", blobs[i].area,
         " at (", blobs[i].box.x, ",", blobs[i].box.y, ")",
         " size=", blobs[i].box.w, "x", blobs[i].box.h

  # =========================================================================
  # 6. Integral Images
  # =========================================================================
  echo ""
  echo "6. Integral Images"

  var testImg = newGrayImage(10, 10)
  for i in 0'u32 ..< 100:
    testImg.data[i] = 10

  var iiData: array[100, uint32]
  var ii = initIntegralImage(iiData, 10, 10)
  computeIntegral(testImg.toView, ii)

  let regionSum = regionSum(ii, 0, 0, 5, 5)
  echo "   5x5 region sum: ", regionSum, " (expected 250)"

  let regionMean = regionMean(ii, 0, 0, 5, 5)
  echo "   5x5 region mean: ", regionMean, " (expected 10)"

  # =========================================================================
  # 7. Feature Detection
  # =========================================================================
  echo ""
  echo "7. Feature Detection (FAST corners)"

  # Create checkerboard pattern (has corners)
  var checker = newGrayImage(50, 50)
  for y in 0'u32 ..< 50:
    for x in 0'u32 ..< 50:
      checker[x, y] = if ((x div 5) + (y div 5)) mod 2 == 0: 255'u8 else: 0'u8

  var scoremap = newGrayImage(50, 50)
  var keypoints: array[100, Keypoint]

  let nKeypoints = fastCorner(checker.toView, scoremap, keypoints, 100, 30)
  echo "   Found ", nKeypoints, " FAST corners"

  # =========================================================================
  # 8. Template Matching
  # =========================================================================
  echo ""
  echo "8. Template Matching"

  # Create scene with a template
  var scene = newGrayImage(50, 50)
  fill(scene, 50)
  for y in 20'u32 ..< 30:
    for x in 20'u32 ..< 30:
      scene[x, y] = 200

  # Extract template
  var tmpl = newGrayImage(10, 10)
  crop(tmpl, scene.toView, 20, 20, 10, 10)

  # Match
  var matchResult = newGrayImage(41, 41)
  matchTemplate(scene.toView, tmpl.toView, matchResult)

  let (bestPos, score) = findBestMatchWithScore(matchResult.toView)
  echo "   Best match at (", bestPos.x, ", ", bestPos.y, ") with score ", score

  # =========================================================================
  # Summary
  # =========================================================================
  echo ""
  echo "Example complete!"
  echo "See source code for detailed usage patterns."

when isMainModule:
  main()
