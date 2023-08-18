##[Encode and decode using Reed-Solomon correction codes.

   Low level API.

   This code is translated and adapted to Nim from the Python version provided by
   [Wikiversity](https://en.wikiversity.org/wiki/Reed%E2%80%93Solomon_codes_for_coders).

   For a detailed description of the algorithm, refer to this site and to the Python source.

   ## Description

   The module provides two functions:
    - a function to encode a block of data whose length must not exceed 255 - `nsym`, where
      `nsym` is the size of the error correction code (ECC)
    - a function to decode a block of data whose size must not exceed 255.

   The algorithm manages erasures i.e. corrupt bytes whose locations are known. Each byte of
   the ECC allows to correct one erasure. To correct an error whose position is unknown, two
   bytes are needed. Thus, for instance, to correct three erasures and three other errors,
   the ECC must at least be 9 bytes long.

   Note that unlike Python original, the primitive polynomial is set to `0b100011101` and not
   provided in an initialization procedure. This allows to precompute the tables at compile time.
]##

# Standard library imports.
import std/[algorithm, sequtils]

# Exceptions raised if an error occurred during decoding.
type
  RSDefect* = object of Defect          ## Exception raised for API call error or internal error.
  RSError* = object of CatchableError   ## Exception raised for other errors.


#---------------------------------------------------------------------------------------------------
# GF(2^8) definition and operations.

# A GF(2^8) value is a sequence of eight bits stored in a byte.
type GFint = distinct byte


func initGFexp(prim: uint16): array[512, GFint] {.compileTime.} =
  ## Initialize the Galois field exponent table.
  result[0] = GFint(1)
  var val: uint16 = 1
  for idx in 1..254:
    val = val shl 1
    if val > 255: val = val xor prim
    result[idx] = GFint(val)
  # Double the size of the exponent table to be sure to remain in the bounds
  # when multiplying two GF numbers.
  for idx in 255..511:
    result[idx] = result[idx - 255]

func initGFlog(GFexp: array[512, GFint]): array[GFint, GFint] {.compileTime.} =
  ## Initialize the Galois field logarithm table.
  for idx in 1..254:
    result[GFexp[idx]] = GFint(idx)

const GFexp = initGFexp(0b100011101)
const GFlog = initGFlog(GFexp)


# Borrowed operations on GFint.
proc `<`(x, y: GFint): bool {.borrow.}
proc `==`(x, y: GFint): bool {.borrow.}
proc `xor`(x, y: GFint): GFint {.borrow.}


func `*`(x, y: GFint): GFint =
  ## Perform a multiplication of GF(2^8) values.
  if x == GFint(0) or y == GFint(0):
    GFint(0)
  else:
    GFexp[uint16(GFlog[x]) + uint16(GFlog[y])]

func `div`(x, y: GFint): GFint =
  ## Perform a division of GF(2^8) values.
  if y == GFint(0):
    raise newException(DivByZeroDefect, "Galois division by zero.")
  if x == GFint(0):
    GFint(0)
  else:
    GFexp[uint16(GFlog[x]) + 255u16 - uint16(GFlog[y]) mod 255]


func `^`(x: GFint; n: int): GFint =
  ## Compute a power of a GF(2^8) value.
  var val = int(GFlog[x]) * n mod 255   # Note that "val" may be negative.
  if val < 0: val += 255
  GFexp[val]


func inverse(x: GFint): GFint =
  ## Compute the inverse of a GF(2^8) value.
  GFexp[255u16 - uint16(GFlog[x])]


#---------------------------------------------------------------------------------------------------
# Polynomial definition and operations.

# A polynomial is a sequence of GF8 coefficients, ordered by decreasing degree.
type Polynomial = seq[GFint]


func newPoly(len: Natural = 0): Polynomial {.inline.} =
  ## Create a polynomial.
  newSeq[GFint](len)


func `+`(a, b: Polynomial): Polynomial =
  ## Perform a polynomial addition.
  let aLen = a.len
  let bLen = b.len
  result = newPoly(max(aLen, bLen))
  var idx = result.len - aLen
  for elem in a:
    result[idx] = elem
    inc idx
  idx = result.len - bLen
  for elem in b:
    result[idx] = result[idx] xor elem
    inc idx


func `*`(a, b: Polynomial): Polynomial =
  ## Perform a polynomial multiplication.
  result = newPoly(a.len + b.len - 1)
  let logB = b.mapIt(GFlog[it])
  for idxA, elemA in a:
    if elemA != GFint(0):
      let logA = GFlog[elemA]
      for idxB, elemB in b:
        if elemB != GFint(0):
          result[idxA + idxB] = result[idxA + idxB] xor GFexp[uint16(logA) + uint16(logB[idxB])]


func scale(a: Polynomial; x: GFint): Polynomial =
  ## Perform a polynomial scaling.
  result = newPoly(a.len)
  for idx, elem in a:
    result[idx] = elem * x


func eval(a: Polynomial; x: GFint): GFint =
  ## Perform a polynomial evaluation.
  result = a[0]
  for idx in 1..a.high:
    result = result * x xor a[idx]


#---------------------------------------------------------------------------------------------------
# Reed-Solomon operations.

func rsGenerator(nsym: int): Polynomial =
  ## Build the generator polynomial. Its length is "nsym + 1".
  result = @[GFint(1)]
  for i in 0..<nsym:
    result = result * @[GFint(1), GFint(2) ^ i]


func rsEncode*(indata: openArray[byte]; nsym: int): seq[byte] =
  ## Encode a sequence of bytes using `nsym` ECC bytes.
  ##
  ## The length of input data must not exceed 255 - `nsym` bytes.
  ##
  ## The result is a sequence containing at most 255 bytes.

  if indata.len + nsym > 255:
    raise newException(RSDefect, "Data is too long. Max is " & $(255 - nsym))

  let gen = rsGenerator(nsym)

  # Copy input data into result.
  result = newSeq[byte](indata.len + nsym)
  copyMem(result[0].addr, indata[0].addr, indata.len)

  # Synthetic division.
  for dataIdx in 0..indata.high:
    let coeff = GFint(result[dataIdx])
    if coeff != GFint(0):
      var idx = dataIdx + 1
      for genidx in 1..nsym:
        result[idx] = byte(result[idx]) xor byte(gen[genidx] * coeff)
        inc idx

  # The quotient is stored in the "indata.len" first bytes, the remainder in the last "nsym" bytes.
  # To get the encoded message, we overwrite the beginning of the result with the original message.
  copyMem(result[0].addr, indata[0].addr, indata.len)


func syndromes(data: Polynomial; nsym: Natural): Polynomial =
  ## Return the syndrome polynomial.
  result = newPoly(nsym + 1)
  for i in 1..nsym:
    result[i] = data.eval(GFint(2) ^ (i - 1))


func errataLocator(epos: seq[int]): Polynomial =
  ## Compute the erasures/errors/errata locator polynomial
  ## from the erasures/errors/errata positions.
  result = @[GFint(1)]
  for pos in epos:
    result = result * (@[GFint(1)] + @[GFint(2) ^ pos, GFint(0)])


func errorEvaluator(synd, errloc: Polynomial; nsym: Natural): Polynomial =
  ## Compute the error evaluator polynomial.
  result = synd * errloc
  result = result[(result.high - nsym)..^1]


func correctedErrata(data, synd: Polynomial; errpos: seq[int]): Polynomial =
  ## Compute the values (error magnitude) to correct the input message (Forney algorithm).

  # Convert the positions to coefficient degrees.
  var coeffpos = newSeq[int](errpos.len)
  for i, pos in errpos:
    coeffpos[i] = data.high - pos

  let errloc = errataLocator(coeffpos)
  let erreval = errorEvaluator(reversed(synd), errloc, errloc.len - 1)

  # Get the error location polynomial "x" from the error positions in "errpos".
  var x = newSeq[GFint](coeffpos.len)
  for i, pos in coeffpos:
    x[i] = GFint(2) ^ (pos - 255)

  # Forney algorithm: compute the magnitudes.
  var e = newPoly(data.len)
  for i, xi in x:
    let xiInv = xi.inverse()
    # Compute the formal derivative of the error locator polynomial.
    var errLocPoly: Polynomial
    for j in 0..x.high:
      if j != i:
        errLocPoly.add GFint(1) xor (xiInv * x[j])
    # Compute the denominator of the Forney algorithm.
    var errLocPrime = GFint(1)
    for coeff in errLocPoly:
      errLocPrime = errLocPrime * coeff
    # Compute the numerator of the Forney algorithm.
    let y = xi * eval(erreval, xiInv)
    # Compute and store the magnitude.
    if errLocPrime == GFint(0):
      raise newException(RSError, "Could not find error magnitude")
    e[errpos[i]] = y div errLocPrime

  # Apply the errata magnitudes to get the corrected message.
  result = data + e


func errorLocator(synd: Polynomial; nsym: Natural; eraseCount: int): Polynomial =
  ## Find error/errata locator and evaluator polynomials with Berlekamp-Massey algorithm.

  # Initialize the polynomials.
  var errloc: Polynomial = @[GFint(1)]
  var oldloc: Polynomial = errloc

  var syndshift = if synd.len > nsym: synd.len - nsym else: 0

  for i in 0..<(nsym - eraseCount):

    # Compute the discrepancy delta.
    let k = i + syndshift
    var delta = synd[k]
    for j in 1..errloc.high:
      delta = delta xor errloc[^(j + 1)] * synd[k - j]
    # Shift polynomials to compute the next degree.
    oldloc.add GFint(0)

    # Iteratively estimate the errata locator and evaluator polynomials.
    if delta != GFint(0):
      if oldloc.len > errloc.len:
        # Computing errata locator polynomial.
        var newloc = oldloc.scale(delta)
        oldloc = errloc.scale(inverse(delta))
        errloc = move(newloc)
      # Update with the discrepancy.
      errloc = errloc + oldloc.scale(delta)

  # Check that there are not too many errors to correct.
  var shift = 0
  while errloc[shift] == GFint(0):
    inc shift
  let errs = errloc.len - shift - 1
  if 2 * errs - eraseCount > nsym:
    raise newException(RSError, "Too many errors to correct")
  result = errloc[shift..^1]


func errors(errloc: Polynomial; msglen: Natural): seq[int] =
  ## Find the roots of error polynomial by brute-force trial.
  let msghigh = msglen - 1
  for i in 0..msghigh:
    if errloc.eval(GFint(2) ^ i) == GFint(0):
      result.add msghigh - i


func forneySyndromes(synd: Polynomial; pos: openArray[int]; msglen: int): Polynomial =
  ## Compute Forney syndromes, which means a modified syndrome with erasures trimmed out.

  let msghigh = msglen - 1
  var revErasePos = newSeq[int](pos.len)
  for i, p in pos:
    revErasePos[i] = msghigh - p

  result = synd[1..^1]
  for i in 0..pos.high:
    let x = GFint(2) ^ revErasePos[i]
    for j in 0..(result.len - 2):
      result[j] = result[j] * x xor result[j + 1]


func rsDecode*(indata: openArray[byte]; nsym: int; erasePos: openArray[int] = []): seq[byte] =
  ## Decode a Reed-Solomon encoded sequence of bytes, correcting errors if needed.
  ##
  ## The length of the input data must not exceed 255 bytes.
  ##
  ## The result is a sequence of bytes with corrections applied and without ECC bytes.

  if indata.len > 255:
    raise newException(RSDefect, "Data is too long (max is 255)")

  # Copy input data into a sequence of bytes.
  var outdata = newPoly(indata.len)
  for idx, elem in indata:
    outdata[idx] = GFint(elem)

  # Set erasures to null values for easier decoding.
  for epos in erasePos:
    outdata[epos] = GFint(0)
  # Check if there are too many erasures to correct.
  if erasePos.len > nsym:
    raise newException(RSError, "Too many erasures to correct")
  # Prepare the syndrome polynomial.
  var synd = syndromes(outdata, nsym)

  # Check if there is any error or erasure in the input data.
  if max(synd) != GFint(0):

    # Compute the Forney syndromes to hide the erasures from the original syndromes.
    let fsynd = forneySyndromes(synd, erasePos, outdata.len)
    # Compute the error locator polynomial.
    let errloc = errorLocator(fsynd, nsym, eraseCount = erasePos.len)
    # Locate the message errors.
    let errpos = errors(reversed(errloc), outdata.len)
    if errpos.len == 0 and erasePos.len == 0:
      raise newException(RSError, "Could not locate error")

    # Find errors values and apply them to correct the message.
    outdata = correctedErrata(outdata, synd, (erasePos.toSeq() & errPos))

    # Check if the final message is fully repaired.
    synd = syndromes(outdata, nsym)
    if max(synd) > GFint(0):
      raise newException(RSError, "Could not correct message")

  result.setLen(outdata.len - nsym)
  copyMem(result[0].addr, outdata[0].addr, result.len)
