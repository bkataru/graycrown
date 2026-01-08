## graycrown/template_match - Template matching
##
## This module provides template matching functionality
## for finding instances of a template image within a larger image.

{.push raises: [].}

import ./core

# ============================================================================
# Template Matching
# ============================================================================

proc matchTemplate*(img: ImageView | GrayImage;
                    tmpl: ImageView | GrayImage;
                    result: var ImageView | var GrayImage) =
  ## Template matching using Sum of Squared Differences (SSD)
  ##
  ## For each position in the image, computes similarity score between
  ## the template and the image patch. Higher scores indicate better matches.
  ##
  ## Parameters:
  ## - img: Input image to search in
  ## - tmpl: Template image to find
  ## - result: Output similarity map
  ##           Dimensions must be (img.width - tmpl.width + 1, img.height - tmpl.height + 1)
  ##
  ## Result is normalized to [0, 255] where 255 = perfect match
  assert img.isValid and tmpl.isValid and result.isValid,
    "All images must be valid"
  assert img.width >= tmpl.width and img.height >= tmpl.height,
    "Image must be at least as large as template"
  assert result.width == img.width - tmpl.width + 1 and
         result.height == img.height - tmpl.height + 1,
    "Result dimensions must be (img - tmpl + 1)"

  # Maximum possible SSD (all pixels differ by 255)
  let maxDiff = uint64(tmpl.width) * uint64(tmpl.height) * 255'u64 * 255'u64

  for ry in 0'u32 ..< result.height:
    for rx in 0'u32 ..< result.width:
      var ssd: uint64 = 0

      for ty in 0'u32 ..< tmpl.height:
        for tx in 0'u32 ..< tmpl.width:
          let imgPixel = int(img[rx + tx, ry + ty])
          let tmplPixel = int(tmpl[tx, ty])
          let diff = imgPixel - tmplPixel
          ssd += uint64(diff * diff)

      # Normalize: lower SSD = better match, so invert
      # score = 255 * (1 - ssd/maxDiff)
      let normalizedSsd = ssd * 255'u64 div maxDiff
      let score = 255'u8 - uint8(min(normalizedSsd, 255'u64))
      result[rx, ry] = score

proc matchTemplateNCC*(img: ImageView | GrayImage;
                       tmpl: ImageView | GrayImage;
                       result: var ImageView | var GrayImage) =
  ## Template matching using Normalized Cross-Correlation (NCC)
  ##
  ## More robust to brightness/contrast changes than SSD.
  ## Result is normalized to [0, 255] where 255 = perfect correlation.
  assert img.isValid and tmpl.isValid and result.isValid,
    "All images must be valid"
  assert img.width >= tmpl.width and img.height >= tmpl.height,
    "Image must be at least as large as template"
  assert result.width == img.width - tmpl.width + 1 and
         result.height == img.height - tmpl.height + 1,
    "Result dimensions must be (img - tmpl + 1)"

  let n = float32(tmpl.width * tmpl.height)

  # Compute template statistics
  var tmplMean: float32 = 0.0
  for ty in 0'u32 ..< tmpl.height:
    for tx in 0'u32 ..< tmpl.width:
      tmplMean += float32(tmpl[tx, ty])
  tmplMean /= n

  var tmplVar: float32 = 0.0
  for ty in 0'u32 ..< tmpl.height:
    for tx in 0'u32 ..< tmpl.width:
      let d = float32(tmpl[tx, ty]) - tmplMean
      tmplVar += d * d
  let tmplStd = sqrtApprox(tmplVar)

  if tmplStd < 0.0001'f32:
    # Template has no variance - fill with neutral value
    for ry in 0'u32 ..< result.height:
      for rx in 0'u32 ..< result.width:
        result[rx, ry] = 128
    return

  for ry in 0'u32 ..< result.height:
    for rx in 0'u32 ..< result.width:
      # Compute image patch statistics
      var patchMean: float32 = 0.0
      for ty in 0'u32 ..< tmpl.height:
        for tx in 0'u32 ..< tmpl.width:
          patchMean += float32(img[rx + tx, ry + ty])
      patchMean /= n

      var patchVar: float32 = 0.0
      var crossCorr: float32 = 0.0

      for ty in 0'u32 ..< tmpl.height:
        for tx in 0'u32 ..< tmpl.width:
          let patchDiff = float32(img[rx + tx, ry + ty]) - patchMean
          let tmplDiff = float32(tmpl[tx, ty]) - tmplMean
          patchVar += patchDiff * patchDiff
          crossCorr += patchDiff * tmplDiff

      let patchStd = sqrtApprox(patchVar)

      var ncc: float32
      if patchStd < 0.0001'f32:
        ncc = 0.0'f32
      else:
        ncc = crossCorr / (patchStd * tmplStd)

      # Map [-1, 1] to [0, 255]
      let score = uint8(clamp((ncc + 1.0'f32) * 127.5'f32, 0.0'f32, 255.0'f32))
      result[rx, ry] = score

# ============================================================================
# Find Best Match
# ============================================================================

proc findBestMatch*(matchResult: ImageView | GrayImage): Point =
  ## Find location of best match in template matching result
  ## Returns coordinates with highest score
  assert matchResult.isValid, "Result image must be valid"

  var bestScore: uint8 = 0
  var bestX: uint32 = 0
  var bestY: uint32 = 0

  for y in 0'u32 ..< matchResult.height:
    for x in 0'u32 ..< matchResult.width:
      let score = matchResult[x, y]
      if score > bestScore:
        bestScore = score
        bestX = x
        bestY = y

  Point(x: bestX, y: bestY)

proc findBestMatchWithScore*(matchResult: ImageView | GrayImage): tuple[pt: Point, score: uint8] =
  ## Find location and score of best match
  assert matchResult.isValid, "Result image must be valid"

  var bestScore: uint8 = 0
  var bestX: uint32 = 0
  var bestY: uint32 = 0

  for y in 0'u32 ..< matchResult.height:
    for x in 0'u32 ..< matchResult.width:
      let score = matchResult[x, y]
      if score > bestScore:
        bestScore = score
        bestX = x
        bestY = y

  (Point(x: bestX, y: bestY), bestScore)

# ============================================================================
# Find Multiple Matches
# ============================================================================

type
  TemplateMatch* = object
    ## Template match result
    position*: Point
    score*: uint8

proc findMatches*(matchResult: ImageView | GrayImage;
                  matches: var openArray[TemplateMatch];
                  maxMatches: uint32;
                  threshold: uint8;
                  minDistance: uint32 = 10): uint32 =
  ## Find multiple matches above threshold with non-maximum suppression
  ##
  ## Parameters:
  ## - matchResult: Template matching result
  ## - matches: Output array of matches
  ## - maxMatches: Maximum number of matches to return
  ## - threshold: Minimum score for a valid match
  ## - minDistance: Minimum distance between matches (for NMS)
  ##
  ## Returns: Number of matches found
  assert matchResult.isValid, "Result image must be valid"
  assert maxMatches > 0 and matches.len >= int(maxMatches),
    "Match buffer must be large enough"

  var nMatches: uint32 = 0

  # Collect candidates above threshold
  type Candidate = tuple[x, y: uint32, score: uint8]
  var candidates: seq[Candidate] = @[]

  for y in 0'u32 ..< matchResult.height:
    for x in 0'u32 ..< matchResult.width:
      let score = matchResult[x, y]
      if score >= threshold:
        candidates.add((x, y, score))

  # Sort by score (descending)
  for i in 0 ..< candidates.len - 1:
    for j in 0 ..< candidates.len - 1 - i:
      if candidates[j].score < candidates[j + 1].score:
        swap(candidates[j], candidates[j + 1])

  # Non-maximum suppression
  var suppressed = newSeq[bool](candidates.len)

  for i in 0 ..< candidates.len:
    if suppressed[i]:
      continue
    if nMatches >= maxMatches:
      break

    matches[nMatches] = TemplateMatch(
      position: Point(x: candidates[i].x, y: candidates[i].y),
      score: candidates[i].score
    )
    nMatches += 1

    # Suppress nearby candidates
    for j in i + 1 ..< candidates.len:
      if suppressed[j]:
        continue

      let dx = int(candidates[i].x) - int(candidates[j].x)
      let dy = int(candidates[i].y) - int(candidates[j].y)
      let distSq = uint32(dx * dx + dy * dy)

      if distSq < minDistance * minDistance:
        suppressed[j] = true

  nMatches

{.pop.} # raises: []
