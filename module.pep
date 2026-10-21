## MessagePack: encode Pepper values as compact binary and decode them back,
## with structs driven by the attributes of the `serialize` module, as
## `json` converts them. The `msgpack.cbor` module does the same for CBOR
## (RFC 8949), with the same `Value` and `DecodeError`.
##
## Bring it in with `import msgpack`. Decoding is safe for untrusted input:
## a malformed value is a `DecodeError` with its byte offset, never a
## panic; a declared length is checked against the bytes that remain
## before anything is allocated; and nesting is capped.
##
## - `encode`, `decode`: MessagePack bytes to and from any convertible type
## - `Value`: a decoded value of no fixed type, or one built to encode
## - `to_value`, `from_value`: struct conversion to and from a `Value`
## - `DecodeError`: why decoding failed
## - `UnknownKeys`: `json`'s choice of what decoding does with a map key that
##   names no property
##
## @example
##     import msgpack;
##     import serialize;
##
##     struct Reading {
##         [Required]
##         var sensor: String;
##         var celsius: double;
##         [Name("raw")]
##         var samples: u8[];
##     }
##
##     main(): int {
##         var reading = Reading();
##         reading.sensor = "porch";
##         reading.celsius = 21.5;
##         reading.samples = [1 as u8, 2, 3];
##         var bytes = msgpack.encode(reading);
##         var back = msgpack.decode<Reading>(bytes).value();
##         assert(back.sensor == "porch" && back.samples.count == 3, "a round trip");
##
##         var any = msgpack.decode<msgpack.Value>(bytes).value();
##         assert(any.get("raw").value().to_string() == "h'010203'", "a byte string");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

export [UnknownKeys] from json;

import "bytes";
import "convert";
import "format";
import "value";

export Value;
export DecodeError;
export encode;
export decode;
export to_value;
export from_value;
export _Reader;
export _put_big_endian;
export _fits_float;
