## knull/io - Image file I/O
##
## This module provides PGM (Portable GrayMap) file reading and writing.
## PGM is a simple, portable format ideal for grayscale images.
##
## Only available when stdlib is enabled (not embedded mode).

when defined(knullNoStdLib):
  {.error: "I/O operations require stdlib".}

import std/[streams, strutils]
import ./core

# ============================================================================
# # PGM Format Constants
# # ============================================================================

const
  PgmMagic* = "P5" # Binary PGM magic number
  PgmMagicAscii* = "P2" # ASCII PGM magic number

# ============================================================================
# Error Types
# ============================================================================

type
  ImageIOError* = object of CatchableError
  ## Error during image I/O operation

# ============================================================================
# PGM Reading
# ============================================================================

proc skipWhitespaceAndComments(s: Stream) =
  ## Skip whitespace and # comments in PGM header
  while not s.atEnd:
    let c = s.peekChar
    if c == '#':
      # Skip comment line
      discard s.readLine()
    elif c in Whitespace:
      discard s.readChar()
    else:
      break

proc readPgmHeader(s: Stream): tuple[width, height, maxval: int] =
  ## Read PGM header and return dimensions
  # Read magic number
  let magic = s.readStr(2)
  if magic != PgmMagic and magic != PgmMagicAscii:
    raise newException(ImageIOError, "Invalid PGM magic number: " & magic)

  skipWhitespaceAndComments(s)

  # Read width
  var widthStr = ""
  while not s.atEnd:
    let c = s.peekChar
    if c in Digits:
      widthStr.add(s.readChar())
    else:
      break

  if widthStr.len == 0:
    raise newException(ImageIOError, "Failed to read PGM width")

  skipWhitespaceAndComments(s)

  # Read height
  var heightStr = ""
  while not s.atEnd:
    let c = s.peekChar
    if c in Digits:
      heightStr.add(s.readChar())
    else:
      break

  if heightStr.len == 0:
    raise newException(ImageIOError, "Failed to read PGM height")

  skipWhitespaceAndComments(s)

  # Read maxval
  var maxvalStr = ""
  while not s.atEnd:
    let c = s.peekChar
    if c in Digits:
      maxvalStr.add(s.readChar())
    else:
      break

  if maxvalStr.len == 0:
    raise newException(ImageIOError, "Failed to read PGM maxval")

  # Skip single whitespace after maxval
  if not s.atEnd:
    discard s.readChar()

  let width = parseInt(widthStr)
  let height = parseInt(heightStr)
  let maxval = parseInt(maxvalStr)

  if width <= 0 or height <= 0:
    raise newException(ImageIOError, "Invalid PGM dimensions")

  if maxval != 255:
    raise newException(ImageIOError, "Only maxval=255 PGM files supported")

  (width, height, maxval)

proc readPgm*(path: string): GrayImage =
  ## Read a PGM image from file
  ##
  ## Parameters:
  ## - path: File path (use "-" for stdin)
  ##
  ## Returns: Loaded grayscale image
  ## Raises: ImageIOError on invalid format, IOError on file errors
  var s: Stream

  if path == "-":
    s = newFileStream(stdin)
  else:
    s = newFileStream(path, fmRead)

  if s == nil:
    raise newException(IOError, "Cannot open file: " & path)

  defer: s.close()

  let (width, height, _) = readPgmHeader(s)

  result = newGrayImage(uint32(width), uint32(height))

  # Read pixel data
  let bytesRead = s.readData(result.data, width * height)
  if bytesRead != width * height:
    raise newException(ImageIOError, "Incomplete PGM data: expected " & $(width * height) &
    " bytes, got " & $bytesRead)

proc readPgmInto*(path: string, dst: var ImageView | var GrayImage) =
  ## Read a PGM image into existing buffer
  ##
  ## Buffer must be pre-allocated with correct dimensions.
  var s: Stream

  if path == "-":
    s = newFileStream(stdin)
  else:
    s = newFileStream(path, fmRead)

  if s == nil:
    raise newException(IOError, "Cannot open file: " & path)

  defer: s.close()

  let (width, height, _) = readPgmHeader(s)

  if uint32(width) != dst.width or uint32(height) != dst.height:
    raise newException(ImageIOError,
      "Image dimensions mismatch: file is " & $width & "x" & $height &
    ", buffer is " & $dst.width & "x" & $dst.height)

  let bytesRead = s.readData(dst.data, width * height)
  if bytesRead != width * height:
    raise newException(ImageIOError, "Incomplete PGM data")

# ============================================================================
# PGM Writing
# ============================================================================

proc writePgm*(img: ImageView | GrayImage; path: string) =
  ## Write image to PGM file
  ##
  ## Parameters:
  ## - img: Image to write
  ## - path: Output file path (use "-" for stdout)
  if not img.isValid:
    raise newException(IOError, "Cannot write invalid image")

  var s: Stream

  if path == "-":
    s = newFileStream(stdout)
  else:
    s = newFileStream(path, fmWrite)

  if s == nil:
    raise newException(IOError, "Cannot create file: " & path)

  defer: s.close()

  # Write header
  s.writeLine(PgmMagic)
  s.writeLine($img.width & " " & $img.height)
  s.writeLine("255")

  # Write pixel data
  s.writeData(img.data, int(img.width * img.height))

proc writePgmAscii*(img: ImageView | GrayImage; path: string) =
  ## Write image to ASCII PGM file (larger but human-readable)
  if not img.isValid:
    raise newException(IOError, "Cannot write invalid image")

  var s: Stream

  if path == "-":
    s = newFileStream(stdout)
  else:
    s = newFileStream(path, fmWrite)

  if s == nil:
    raise newException(IOError, "Cannot create file: " & path)

  defer: s.close()

  # Write header
  s.writeLine(PgmMagicAscii)
  s.writeLine($img.width & " " & $img.height)
  s.writeLine("255")

  # Write pixel data (max 70 chars per line)
  var lineLen = 0
  for y in 0'u32 ..< img.height:
    for x in 0'u32 ..< img.width:
      let valStr = $img[x, y]
      if lineLen + valStr.len + 1 > 70:
        s.write("\n")
        lineLen = 0
      elif lineLen > 0:
        s.write(" ")
        lineLen += 1
      s.write(valStr)
      lineLen += valStr.len
  s.write("\n")

# ============================================================================
# Image Info
# ============================================================================

proc getPgmInfo*(path: string): tuple[width, height: int] =
  ## Get PGM image dimensions without loading pixel data
  var s: Stream

  if path == "-":
    raise newException(IOError, "Cannot get info from stdin")

  s = newFileStream(path, fmRead)
  if s == nil:
    raise newException(IOError, "Cannot open file: " & path)

  defer: s.close()

  let (width, height, _) = readPgmHeader(s)
  (width, height)
