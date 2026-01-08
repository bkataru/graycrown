## graycrown - Document Scanner Example
##
## This example demonstrates a complete document scanning pipeline:
## 1. Preprocess image (blur, threshold)
## 2. Find document blob
## 3. Detect corners
## 4. Perspective correction
##
## Run with: nim c -r examples/document_scanner.nim input.pgm output.pgm

import ../src/graycrown

const
  OutputWidth = 800
  OutputHeight = 1000

proc scanDocument*(input: GrayImage): GrayImage =
  ## Complete document scanning pipeline
  ##
  ## Takes a photo of a document and returns a perspective-corrected,
  ## cleaned-up version.

  let w = input.width
  let h = input.height

  echo "Input image: ", w, "x", h

  # Step 1: Preprocess - blur to reduce noise
  echo "Step 1: Applying blur..."
  var blurred = newGrayImage(w, h)
  blur(blurred, input.toView, 1)

  # Step 2: Find optimal threshold using Otsu's method
  echo "Step 2: Computing threshold..."
  let baseThresh = otsuThreshold(blurred.toView)
  # Add small offset to favor white (document) over shadows
  let thresh = min(uint8(int(baseThresh) + 10), 255'u8)
  echo "   Threshold: ", thresh

  # Apply threshold
  var binary = newGrayImage(w, h)
  copy(binary, blurred.toView)
  threshold(binary, thresh)

  # Step 3: Find blobs (connected components)
  echo "Step 3: Finding blobs..."
  let maxBlobs = 1000'u32
  var labels = newSeq[Label](w * h)
  var labelArr = initLabelArray(labels, w, h)
  var blobs = newSeq[Blob](maxBlobs)

  let nBlobs = findBlobs(binary.toView, labelArr, blobs, maxBlobs)
  echo "   Found ", nBlobs, " blobs"

  if nBlobs == 0:
    echo "Error: No blobs found"
    return input

  # Step 4: Find largest blob (assumed to be the document)
  echo "Step 4: Finding document..."
  let largestIdx = findLargestBlob(blobs, nBlobs)
  let documentBlob = blobs[largestIdx]
  echo "   Largest blob area: ", documentBlob.area
  echo "   Bounding box: (", documentBlob.box.x, ",", documentBlob.box.y,
       ") ", documentBlob.box.w, "x", documentBlob.box.h

  # Step 5: Find corners of the document
  echo "Step 5: Finding corners..."
  var corners: array[4, Point]
  findBlobCorners(binary.toView, labelArr, documentBlob, corners)

  echo "   Top-left: (", corners[0].x, ", ", corners[0].y, ")"
  echo "   Top-right: (", corners[1].x, ", ", corners[1].y, ")"
  echo "   Bottom-right: (", corners[2].x, ", ", corners[2].y, ")"
  echo "   Bottom-left: (", corners[3].x, ", ", corners[3].y, ")"

  # Step 6: Perspective correction
  echo "Step 6: Applying perspective correction..."
  result = newGrayImage(OutputWidth, OutputHeight)

  # Use original (non-binary) image for better quality
  perspectiveCorrect(result, input.toView, corners)

  echo "Output image: ", result.width, "x", result.height
  echo "Done!"

proc enhanceDocument*(img: var GrayImage) =
  ## Apply enhancements to scanned document
  ##
  ## - Contrast stretching
  ## - Optional sharpening

  echo "Enhancing document..."

  # Stretch contrast
  stretchContrast(img)
  echo "   Applied contrast stretching"

  # Apply slight sharpening using unsharp mask approximation
  var blurred = newGrayImage(img.width, img.height)
  blur(blurred, img.toView, 1)

  for i in 0'u32 ..< img.size:
    let original = int(img.data[i])
    let blur = int(blurred.data[i])
    let sharpened = original + (original - blur) div 2
    img.data[i] = uint8(clamp(sharpened, 0, 255))

  echo "   Applied sharpening"

proc cleanupDocument*(img: var GrayImage; threshold: uint8 = 200) =
  ## Clean up document by converting to high-contrast binary
  ##
  ## Good for text documents where you want black text on white background.

  echo "Cleaning up document..."

  # Use adaptive thresholding for better text extraction
  var temp = newGrayImage(img.width, img.height)
  adaptiveThreshold(temp, img.toView, 15, 10)

  copy(img, temp.toView)

  # Invert if background is black
  # (detect by checking corners)
  let cornerSum = int(img[0, 0]) + int(img[img.width-1, 0]) +
                  int(img[0, img.height-1]) + int(img[img.width-1, img.height-1])

  if cornerSum < 512:  # Background is dark
    invert(img)
    echo "   Inverted (background was dark)"

  echo "   Applied adaptive thresholding"

# ============================================================================
# Command Line Interface
# ============================================================================

proc printUsage() =
  echo "Document Scanner - graycrown example"
  echo ""
  echo "Usage: document_scanner [options] input.pgm output.pgm"
  echo ""
  echo "Options:"
  echo "  --enhance    Apply contrast and sharpening"
  echo "  --cleanup    Convert to clean binary (for text)"
  echo "  --width N    Output width (default: 800)"
  echo "  --height N   Output height (default: 1000)"
  echo "  --help       Show this help"

proc main() =
  when defined(nimscript):
    echo "This example must be compiled, not run with nimscript"
    return

  import std/[os, strutils]

  var args = commandLineParams()

  if args.len == 0 or "--help" in args:
    printUsage()
    return

  var enhance = false
  var cleanup = false
  var inputPath = ""
  var outputPath = ""
  var i = 0

  while i < args.len:
    case args[i]
    of "--enhance":
      enhance = true
    of "--cleanup":
      cleanup = true
    of "--help":
      printUsage()
      return
    else:
      if inputPath == "":
        inputPath = args[i]
      else:
        outputPath = args[i]
    i += 1

  if inputPath == "" or outputPath == "":
    echo "Error: Input and output paths required"
    printUsage()
    return

  # Load image
  echo "Loading ", inputPath, "..."
  var input: GrayImage
  try:
    input = readPgm(inputPath)
  except:
    echo "Error: Could not read input file"
    return

  # Scan document
  var output = scanDocument(input)

  # Optional enhancements
  if enhance:
    enhanceDocument(output)

  if cleanup:
    cleanupDocument(output)

  # Save output
  echo "Saving ", outputPath, "..."
  try:
    writePgm(output.toView, outputPath)
    echo "Complete!"
  except:
    echo "Error: Could not write output file"

when isMainModule:
  main()
