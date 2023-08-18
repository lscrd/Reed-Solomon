# Low level tests.

import std/[sequtils, strutils, unittest]

import reed_solomon

var e: seq[byte]

test "Encoding of a block.":
  let indata = "hello world"
  # Encode using nine ECC bytes.
  e = indata.toOpenArrayByte(0, indata.high).rsEncode(9)
  check e == @[byte 104, 101, 108, 108, 111, 32, 119, 111, 114, 108,
                    100, 145, 124,  96, 105, 94,  31, 179, 149, 163]
test "Decoding of a corrupt block using erasures.":
  # "Corrupt" the data.
  e[0] = 0
  e[1] = 1
  e[2] = 2
  e[3] = 3
  e[4] = 4
  e[15] = 5   # One corrupt ECC byte.
  # Decode using three ECC bytes for three erasures
  # and six ECC bytes for three errors.
  let outdata = e.rsDecode(9, [0, 2, 3])
  check outdata.mapIt(it.chr).join("") == "hello world"
