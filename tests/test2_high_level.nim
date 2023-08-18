# High level tests.

import std/[random, sequtils, unittest]

import reed_solomon

var e: seq[byte]  # Encoded sequence of bytes.

randomize(1)  # Make sure the test is reproducible.

test "Encoding and decoding of a long sequence of bytes.":
  # Create the sequence with "random" bytes.
  let indata = newSeqWith(400, rand(255).byte)
  # Encode it using five ECC bytes.
  e = indata.encode(5)
  check e.len == indata.len + 2 * 5
  # "Corrupt" the data.
  inc e[0]
  inc e[100]
  inc e[253]   # One corrupt ECC byte.
  inc e[300]
  inc e[350]
  inc e[407]   # Another corrupt ECC byte.
  # Decode specyfing three erasures.
  let outdata = e.decode(5, [0, 100, 407])
  check outdata == indata

test "Encoding and decoding of a string.":
  var instring = "hello world"
  # Encode using six ECC bytes.
  var e = instring.encode(6)
  check e.len == instring.len + 6
  # "Corrupt" the data.
  inc e[0]
  inc e[3]
  inc e[13]   # One corrupt ECC byte.
  # Decode to a string, without erasures.
  let outstring = e.decodeToString(6)
  check instring == outstring
