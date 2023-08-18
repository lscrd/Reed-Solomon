##[Encode and decode using Reed-Solomon correction codes.

   High level API.

   ## Description
   Reed-Solomon error correction code (ECC) are used to check and restore integrity of data.
   They are computed and concatenated to blocks of data.

   Each error need two ECC bytes to be detected and corrected. If the position of a corrupt
   byte is known (erasure), one byte is enough to restore the right value.

   In this module we provide functions to encode and decode data of any length, splitting them
   in chunks if necessary.

   When encoding, input data may be a sequence of bytes or a string. When decoding, ouput data
   may be a sequence of bytes or a string. Internally, sequence of bytes are used.

   The heart of the algorithm is provided by the module [rs](rs.html) which works on blocks of
   data.

]##

import ./reed_solomon/rs
export rsEncode, rsDecode, RSDefect, RSError


func encode*(data: openArray[byte]; nsym: Positive): seq[byte] =
  ## Encode a sequence of bytes, adding `nsym` ECC bytes.
  result = newSeqOfCap[byte](data.len)   # Start with some room.
  let chunkSize = 255 - nsym
  for startIdx in countup(0, data.high, chunkSize):
    let endIdx = min(startIdx + (chunkSize - 1), data.high)
    result.add data.toOpenArray(startIdx, endIdx).rsEncode(nsym)

func encode*(data: string; nsym: int): seq[byte] =
  ## Encode a string to a sequence of bytes using `nsym` ECC bytes.
  data.toOpenArrayByte(0, data.high).encode(nsym)

func decode*(data: openArray[byte]; nsym: int; erasePos: openArray[int] = []): seq[byte] =
  ## Decode a Reed-Solomon encoded sequence of bytes containing `nsym` ECC bytes,
  ## correcting corrupt bytes if needed.
  ##
  ## `erasePos` is the list of erasures (known positions of corrupt bytes).
  ##
  ## The result is a sequence of bytes with corrections applied.
  result = newSeqOfCap[byte](data.len)  # Some more room than actually needed.
  var errIdx = 0
  for startIdx in countup(0, data.high, 255):
    let endIdx = min(startIdx + 254, data.high)
    var errPos: seq[int]
    while errIdx < erasePos.len:  # Build the error position array for the chunk.
      let pos = erasePos[errIdx]
      if pos > endIdx: break
      errPos.add pos - startIdx
      inc errIdx
    result.add data.toOpenArray(startIdx, endIdx).rsDecode(nsym, errPos)

func decodeToString*(data: openArray[byte]; nsym: int; erasePos: openArray[int] = []): string =
  ## Decode a Reed-Solomon encoded sequence of bytes containing `nsym` ECC bytes,
  ## correcting corrupt bytes if needed.
  ##
  ## `erasePos` is the list of erasures (known positions of corrupt bytes).
  ##
  ## The result is a string with corrections applied.
  let bytes = data.decode(nsym, erasePos)
  result.setLen(bytes.len)
  copyMem(result[0].addr, bytes[0].addr, bytes.len)
