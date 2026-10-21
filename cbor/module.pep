## CBOR (RFC 8949): encode Pepper values as Concise Binary Object
## Representation and decode them back, with structs driven by the
## attributes of the `serialize` module, as `json` converts them.
##
## Bring it in with `import msgpack.cbor`. It shares `msgpack`'s `Value`
## (with CBOR's tags, simple values and `undefined`) and `DecodeError`,
## which it exports too, and converts structs as `msgpack.to_value` and
## `msgpack.from_value` do. Decoding is as safe for untrusted input as
## `msgpack.decode`: errors, never panics, lengths checked against the
## input, and nesting capped.
##
## - `encode`, `decode`: CBOR bytes to and from any convertible type
## - `Value`, `DecodeError`, `UnknownKeys`: `msgpack`'s, under this
##   module's name
##
## @example
##     import msgpack.cbor;
##
##     struct Credential {
##         var id: u8[];
##         var counter: int;
##     }
##
##     main(): int {
##         var credential = Credential();
##         credential.id = [0xca as u8, 0xfe];
##         credential.counter = 7;
##         var bytes = cbor.encode(credential);
##         var back = cbor.decode<Credential>(bytes).value();
##         assert(back.counter == 7 && back.id[1] == 0xfe, "a round trip");
##
##         var any = cbor.decode<cbor.Value>(bytes).value();
##         assert(any.to_string() == "{\"id\": h'cafe', \"counter\": 7}", "diagnostic notation");
##         return 0;
##     }

# This file only gathers the module's public API from its other files.

export [Value, DecodeError, UnknownKeys] from msgpack;

import "format";

export encode;
export decode;
