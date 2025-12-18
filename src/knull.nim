## knull - Zero-dependency grayscale image processing for embedded systems
##
## A Nim port of the grayskull C library, designed for microcontrollers
## and resource-constrained devices.
##
## Features:
## - Image operations: copy, crop, resize, downsample
## - Filtering: blur, threshold (global, Otsu, adaptive), Sobel edges
## - Morphology: erosion, dilation, opening, closing
## - Analysis: connected components (blobs), contour tracing
## - Features: FAST corners, ORB descriptors, feature matching
## - Detection: LBP cascade for object detection (faces, etc.)
## - Utilities: PGM file I/O, integral images
##
## Embedded Mode:
## Compile with -d:knullNoStdlib for zero-dependency embedded operation.
## In this mode:
## - No dynamic memory allocation
## - No file I/O
## - Custom math approximations
## - User must provide all buffers
##
## Example:
## ```nim
## import knull
##
## var img = newGrayImage(640, 480)
## # ... fill with data ...
##
## # Apply blur
## var blurred = newGrayImage(640, 480)
## blur(blurred, img.toView, 2)
##
## # Find edges
## var edges = newGrayImage(640, 480)
## sobel(edges, blurred.toView)
##
## # Threshold
## let thresh = otsuThreshold(edges.toView)
## threshold(edges, thresh)
## ```

# Re-export core types and utilities
import knull/core
export core
