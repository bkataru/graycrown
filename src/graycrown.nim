## graycrown - Zero-dependency grayscale image processing for embedded systems
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
## Compile with -d:graycrownNoStdlib for zero-dependency embedded operation.
## In this mode:
## - No dynamic memory allocation
## - No file I/O
## - Custom math approximations
## - User must provide all buffers
##
## Example:
## ```nim
## import graycrown
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
import graycrown/core
export core

# Re-export image operations
import graycrown/image
export image

# Re-export filtering operations
import graycrown/filters
export filters

# Re-export morphological operations
import graycrown/morph
export morph

# Re-export blob/contour analysis
import graycrown/blobs
export blobs

# Re-export integral image operations
import graycrown/integral
export integral

# Re-export feature detection
import graycrown/features
export features

# Re-export template matching
import graycrown/template_match
export template_match

# Re-export LBP cascade detection
import graycrown/lbp
export lbp

# Re-export I/O (only when stdlib available)
when not defined(graycrownNoStdlib):
  import graycrown/io
  export io

# ============================================================================
# Version Information
# ============================================================================

const
  GraycrownVersion* = "0.1.0"
  GraycrownMajor* = 0
  GraycrownMinor* = 1
  GraycrownPatch* = 0

# ============================================================================
# Convenience High-Level Functions
# ============================================================================

when not defined(graycrownNoStdlib):
  proc loadAndProcess*(path: string;
                       processor: proc(img: var GrayImage)): GrayImage =
    ## Load image, apply processor, return result
    result = readPgm(path)
    processor(result)

  proc processAndSave*(img: GrayImage;
                       path: string;
                       processor: proc(src: ImageView; dst: var ImageView)) =
    ## Process image and save to file
    var output = newGrayImage(img.width, img.height)
    var dstView = output.toView
    processor(img.toView, dstView)
    writePgm(dstView, path)
