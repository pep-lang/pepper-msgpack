# Helpers the tests share: hexadecimal input, and what it decodes to.

import msgpack.cbor;
import digest;
import msgpack;

# The bytes of hexadecimal `text`.
bytes_of(text: String): u8[] {
    return digest.from_hex(text).value();
}

# What MessagePack `text` (hexadecimal) decodes to, in diagnostic notation,
# or its error.
msgpack_text(text: String, max_depth: ulong = 256): String {
    var value = msgpack.decode<msgpack.Value>(bytes_of(text), max_depth = max_depth);
    if (value.is_err()) {
        return value.error().to_string();
    }
    return value.value().to_string();
}

# What CBOR `text` (hexadecimal) decodes to, in diagnostic notation, or its
# error.
cbor_text(text: String, max_depth: ulong = 256): String {
    var value = cbor.decode<cbor.Value>(bytes_of(text), max_depth = max_depth);
    if (value.is_err()) {
        return value.error().to_string();
    }
    return value.value().to_string();
}
