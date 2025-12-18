# 🏴 knull

A zero-dependency grayscale image processing library for Nim, designed for embedded systems and microcontrollers. This is a complete Nim port/rewrite of [grayskull](https://github.com/zserge/grayskull).

## Features

- **Image Operations**: copy, crop, resize (bilinear), downsample, flip, rotate
- **Filtering**: blur, Sobel edges, histogram, thresholding (global, Otsu, adaptive)
- **Morphology**: erosion, dilation, opening, closing
- **Geometry**: connected components, perspective warp, contour tracing
- **Features**: FAST corners, ORB descriptors, feature matching
- **Detection**: LBP cascades for object detection (faces, vehicles, etc.)
- **Utilities**: PGM file I/O, integral images

**Key Properties:**
- Zero external dependencies
- No dynamic memory allocation in embedded mode
- Pure Nim (no C bindings required)
- Optimized for resource-constrained devices
- Comprehensive test suite

## Installation

### Using Nimble

```bash
nimble install knull
```

### From Source

```bash
git clone https://github.com/bkataru/knull
cd knull
nimble install
```

## Quick Start

```nim
import knull

# Create a grayscale image
var img = newGrayImage(640, 480)

# Fill with gray
fill(img, 128)

# Access pixels
img[100, 100] = 255  # Set pixel
let value = img[100, 100]  # Get pixel

# Apply blur
var blurred = newGrayImage(640, 480)
blur(blurred, img.toView, 2)  # radius=2

# Edge detection
var edges = newGrayImage(640, 480)
sobel(edges, blurred.toView)

# Threshold using Otsu's method
let thresh = otsuThreshold(edges.toView)
threshold(edges, thresh)

# Save to PGM file
writePgm(edges.toView, "output.pgm")
```

## Embedded Mode

For microcontrollers and systems without standard library, compile with `-d:knullNoStdlib`:

```bash
nim c -d:knullNoStdlib -d:release --gc:none myapp.nim
```

In embedded mode:
- No dynamic memory allocation
- No file I/O
- All buffers must be provided by the user
- Custom math approximations (sin, cos, atan2, sqrt)

Example:

```nim
import knull/core
import knull/filters

# Static buffers
var 
  imageBuffer: array[320 * 240, Pixel]
  tempBuffer: array[320 * 240, Pixel]

# Wrap as ImageView
var img = initImageView(
  cast[ptr UncheckedArray[Pixel]](addr imageBuffer[0]),
  320, 240
)

var temp = initImageView(
  cast[ptr UncheckedArray[Pixel]](addr tempBuffer[0]),
  320, 240
)

# Process
blur(temp, img, 1)
let thresh = otsuThreshold(temp)
threshold(temp, thresh)
```

## API Reference

### Core Types

```nim
type
  Pixel* = uint8                    # 8-bit grayscale
  Point* = object                   # 2D point
    x*, y*: uint32
  Rect* = object                    # Rectangle
    x*, y*, w*, h*: uint32
  ImageView* = object               # Non-owning image view
    width*, height*: uint32
    data*: ptr UncheckedArray[Pixel]
  GrayImage* = object               # Owning image (with memory management)
    width*, height*: uint32
    data*: ptr UncheckedArray[Pixel]
    owned*: bool
```

### Image Operations

```nim
# Creation
proc newGrayImage*(width, height: uint32): GrayImage
proc toView*(img: GrayImage): ImageView

# Basic ops
proc fill*(dst: var ImageView; value: Pixel)
proc copy*(dst: var ImageView; src: ImageView)
proc crop*(dst: var ImageView; src: ImageView; roi: Rect)
proc resize*(dst: var ImageView; src: ImageView)  # Bilinear
proc resizeNearestNeighbor*(dst: var ImageView; src: ImageView)
proc downsample*(dst: var ImageView; src: ImageView)  # 2x

# Transforms
proc flipHorizontal*(dst: var ImageView; src: ImageView)
proc flipVertical*(dst: var ImageView; src: ImageView)
proc rotate90CW*(dst: var ImageView; src: ImageView)
proc rotate90CCW*(dst: var ImageView; src: ImageView)
proc invert*(img: var ImageView)
```

### Filtering

```nim
# Blur
proc blur*(dst: var ImageView; src: ImageView; radius: uint32)
proc boxBlur*(dst: var ImageView; src: ImageView; radius: uint32)

# Thresholding
proc threshold*(img: var ImageView; thresh: uint8)
proc otsuThreshold*(img: ImageView): uint8
proc adaptiveThreshold*(dst: var ImageView; src: ImageView; 
                        radius: uint32; c: int = 0)

# Edge detection
proc sobel*(dst: var ImageView; src: ImageView)

# Histogram
proc computeHistogram*(img: ImageView): Histogram  # array[256, uint32]
```

### Morphology

```nim
proc erode*(dst: var ImageView; src: ImageView)
proc dilate*(dst: var ImageView; src: ImageView)
proc morphOpen*(dst: var ImageView; src: ImageView; temp: var ImageView)
proc morphClose*(dst: var ImageView; src: ImageView; temp: var ImageView)
```

### Blob Detection

```nim
proc findBlobs*(img: ImageView; labels: var LabelArray; 
                blobs: var openArray[Blob]; maxBlobs: uint32): uint32
proc findBlobCorners*(img: ImageView; labels: LabelArray; 
                      blob: Blob; corners: var array[4, Point])
proc traceContour*(img: ImageView; visited: var ImageView; 
                   contour: var Contour)
proc perspectiveCorrect*(dst: var ImageView; src: ImageView;
                         corners: array[4, Point])
```

### Feature Detection

```nim
# FAST corners
proc fastCorner*(img: ImageView; scoremap: var ImageView;
                 keypoints: var openArray[Keypoint]; 
                 maxKeypoints, threshold: uint32): uint32

# ORB features
proc extractOrb*(img: ImageView; keypoints: var openArray[Keypoint];
                 maxKeypoints, threshold: uint32;
                 scoremapBuffer: var openArray[Pixel]): uint32

# Feature matching
proc matchOrb*(kps1: openArray[Keypoint]; n1: uint32;
               kps2: openArray[Keypoint]; n2: uint32;
               matches: var openArray[Match]; 
               maxMatches: uint32; maxDistance: float32): uint32
```

### Template Matching

```nim
proc matchTemplate*(img: ImageView; tmpl: ImageView; result: var ImageView)
proc findBestMatch*(result: ImageView): Point
```

### LBP Cascade Detection

```nim
proc lbpDetect*(cascade: LbpCascade; ii: IntegralImage;
                rects: var openArray[Rect]; maxRects: uint32;
                scaleFactor, minScale, maxScale: float32;
                step: int = 1): uint32

proc groupRectangles*(rects: var openArray[Rect]; count: uint32;
                      minNeighbors: int = 3): uint32
```

### File I/O (stdlib mode only)

```nim
proc readPgm*(path: string): GrayImage
proc writePgm*(img: ImageView; path: string)
```

## Examples

### Basic Processing Pipeline

```nim
import knull

# Load image
var img = readPgm("photo.pgm")

# Denoise
var denoised = newGrayImage(img.width, img.height)
blur(denoised, img.toView, 2)

# Find edges
var edges = newGrayImage(img.width, img.height)
sobel(edges, denoised.toView)

# Binarize
let thresh = otsuThreshold(edges.toView)
threshold(edges, thresh)

# Save
writePgm(edges.toView, "edges.pgm")
```

### Document Scanning

```nim
import knull

proc scanDocument(input: GrayImage): GrayImage =
  # Preprocess
  var blurred = newGrayImage(input.width, input.height)
  blur(blurred, input.toView, 1)
  
  var binary = newGrayImage(input.width, input.height)
  copy(binary, blurred.toView)
  threshold(binary, otsuThreshold(binary.toView) + 10)
  
  # Find document blob
  var labels = newSeq[Label](input.width * input.height)
  var labelArr = initLabelArray(labels, input.width, input.height)
  var blobs: array[100, Blob]
  let n = findBlobs(binary.toView, labelArr, blobs, 100)
  
  # Get corners of largest blob
  let largest = findLargestBlob(blobs, n)
  var corners: array[4, Point]
  findBlobCorners(binary.toView, labelArr, blobs[largest], corners)
  
  # Perspective correct
  result = newGrayImage(800, 1000)
  perspectiveCorrect(result, input.toView, corners)
```

### Motion Detection

```nim
import knull

var previousFrame: GrayImage

proc detectMotion(currentFrame: GrayImage): uint32 =
  var count: uint32 = 0
  
  for i in 0'u32 ..< currentFrame.size:
    let diff = abs(int(currentFrame.data[i]) - int(previousFrame.data[i]))
    if diff > 30:
      count += 1
  
  copy(previousFrame, currentFrame.toView)
  count
```

## Testing

```bash
# Run all tests
nimble test

# Run tests in release mode
nimble testRelease

# Test embedded mode (no stdlib)
nimble testEmbedded
```

## Benchmarks

```bash
nimble bench
```

## Memory Usage

For a 320x240 image:

| Buffer | Size |
|--------|------|
| Image (grayscale) | 76,800 bytes |
| Integral image | 307,200 bytes |
| Label array | 153,600 bytes |
| **Total typical pipeline** | ~600 KB |

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE)

## Credits

- Original C library: [grayskull](https://github.com/zserge/grayskull) by Serge Zaitsev

## Publishing to Nimble

To publish this package to the Nimble package repository:

1. Create a GitHub repository for this project
2. Tag a release:
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. Submit to Nimble packages repository by creating a PR to:
   https://github.com/nim-lang/packages

   Add this entry to `packages.json`:
   ```json
   {
     "name": "knull",
     "url": "https://github.com/bkataru/knull",
     "method": "git",
     "tags": ["image", "processing", "embedded", "grayscale", "vision"],
     "description": "Zero-dependency grayscale image processing for embedded systems",
     "license": "MIT"
   }
   ```
