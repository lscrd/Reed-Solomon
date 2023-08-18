# reed_solomon

Encode and decode using Reed-Solomon correction codes.

This library is translated and adapted from the Python version which is provided by [Wikiversity](https://en.wikiversity.org/wiki/Reed%E2%80%93Solomon_codes_for_coders)

For a detailed description of the algorithm, refer to this site and to the Python source.

Note that this library is not a universal Reed-Solomon encoder and decoder. So, it may be unable to detect and correct errors in data encoded by another library.

## Presentation

When encoding using Reed-Solomon error correction codes (ECC), one has to specify the number of ECC bytes which allow to detect and correct corrupt bytes.
When the position of a corrupt byte is unknown, two ECC bytes are needed to detect and correct the error.
When the position is known, we can specify it when decoding. This is called an “erasure”. As the position is known, a single ECC byte is needed to restore the right value.
For instance, if we use nine ECC bytes, we are able to detect three errors (using 6 ECC bytes) and three erasures (using 3 ECC bytes).

Encoding is done by blocks of at most 255 bytes. A block contains the input data followed by the ECC bytes. So, for instance, if we use 10 ECC bytes, we can encode
a sequence of 245 bytes. If we want to encode longer sequences, we have to split the input data into chunks, encode these chunks to blocks and concatenate these blocks to build the output data.

The library provides two low level functions: one to encode a sequence of bytes to a block and one to decode a block. Normally, these low level functions should not be used as more convenient high level functions are provided.

Two high level functions allow to encode strings or sequences of bytes of any length by splitting them in chunks. The result of the encoding process is a sequence of bytes.
Two high level functions allow to decode an encoded sequence of bytes of any length to a sequence of bytes or to a string.

If the decoding cannot be done (which occurs, for instance, if there are not enough ECC bytes to correct the corrupt bytes), an exception RsError is raised.

## Short example

Here is an example using the high level functions for strings:

```Nim
import reed_solomon

const Text = "Hello world!"

var encoded = Text.encode(6)    # Using 6 ECC bytes.

# "Corrupt" the encoded text.
inc encoded[0]
inc encoded[5]
inc encoded[8]
inc encoded[^3]     # Corrupt one ECC byte.

# If we don’t know the position of corrupt bytes, we will not be able
# to do the correction as it would required eight ECC bytes.
# But, let’s suppose that we know the position of two corrupt bytes
# i.e. we can provide two erasures.
# In this case, six ECC bytes are enough.

let correctedText = encoded.decodeToString(6, [0, 8])
assert correctedText == Text
```
