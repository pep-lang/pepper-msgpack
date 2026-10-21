## CBOR itself (RFC 8949): `encode` writes a value in the format and
## `decode` reads one back.

import json;
import msgpack;
import text;

## Writes `value` as CBOR, converting it as `msgpack.to_value` does.
##
## The output is in the RFC's preferred serialization: each integer and
## length in its shortest form, and each float as the narrowest of half,
## single and double precision that keeps its value exactly (NaN as the
## half `0xf97e00`). Lengths are always definite, and map entries keep
## their order. A `Tag` is written as a tag, and a MessagePack
## `Extension`, which CBOR has no form for, as a byte string of its data.
##
## @typeParam T the type of the value
## @param value the value to write
## @returns the encoded bytes
## @example
##     import digest;
##     import msgpack.cbor;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var p = Point();
##         p.x = 1;
##         p.y = -1;
##         assert(digest.to_hex(cbor.encode(p)) == "a2617801617920", "a map");
##         return 0;
##     }
export encode<T>(value: T): u8[] {
    var out = Array<u8>();
    _cbor_write(out, msgpack.to_value(value));
    return out;
}

## Reads a CBOR value from `bytes` and converts it to a `T`, as
## `msgpack.from_value` does; `decode<msgpack.Value>` gives the value
## itself.
##
## Every well-formed item reads: tags (as `Tag`, which converts as the item
## it tags), simple values, half-precision floats, and indefinite-length
## strings, arrays and maps, whose chunks a string joins into one.
##
## Decoding is safe for untrusted input: every failure is an error, never a
## panic. A declared length longer than the bytes that remain fails before
## anything is allocated, so a 4 GB length prefix in a short input costs
## nothing, and arrays, maps and tags may nest only `max_depth` deep.
## `bytes` must hold exactly one item; a text string must be UTF-8, and a
## reserved additional-information value, a `break` outside an
## indefinite-length item, or a chunk of the wrong type is an error.
##
## @typeParam T the type to convert to
## @param bytes the encoded value
## @param unknown_keys what to do with a map key that names no property
## @param max_depth how deep arrays, maps and tags may nest
## @returns the value, or the first error: one in the input's form, at its
##   byte offset, or a conversion error, at its path in the value
## @example
##     import msgpack;
##     import msgpack.cbor;
##
##     main(): int {
##         var value = cbor.decode<msgpack.Value>([0xc1 as u8, 0x1a, 0x51, 0x4b, 0x67, 0xb0]).value();
##         assert(value.to_string() == "1(1363896240)", "a tag");
##
##         var huge = cbor.decode<msgpack.Value>([0x5a as u8, 0xff, 0xff, 0xff, 0xff]);
##         assert(huge.is_err(), "a 4 GB byte string in 5 bytes");
##         return 0;
##     }
export decode<T>(
    bytes: u8[], unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore, max_depth: ulong = 256
): Result<T, msgpack.DecodeError> {
    var reader = msgpack._Reader(bytes, max_depth);
    var value = _cbor_read(reader, 0)?;
    reader.finish()?;
    return msgpack.from_value<T>(value, unknown_keys);
}

# ── Writing ────────────────────────────────────────────────────────────────

# The initial byte of major type `major` and its argument `n`, in the
# shortest form.
_cbor_head(out: u8[], major: u8, n: ulong) {
    var high = major << 5;
    if (n < 24) {
        out.append(high | n as u8);
    } else if (n < 256) {
        out.append(high | 24);
        _put(out, n, 1);
    } else if (n < 65536) {
        out.append(high | 25);
        _put(out, n, 2);
    } else if (n < 4294967296) {
        out.append(high | 26);
        _put(out, n, 4);
    } else {
        out.append(high | 27);
        _put(out, n, 8);
    }
}

_put(out: u8[], n: ulong, count: ulong) {
    msgpack._put_big_endian(out, n, count);
}

_cbor_write(out: u8[], value: msgpack.Value) {
    match (value) {
        Null => {
            out.append(0xf6);
        }
        Undefined => {
            out.append(0xf7);
        }
        Bool(flag) => {
            if (flag) {
                out.append(0xf5);
            } else {
                out.append(0xf4);
            }
        }
        Integer(n) => {
            if (n >= 0) {
                _cbor_head(out, 0, n as ulong);
            } else {
                _cbor_head(out, 1, (-1 - n) as ulong);
            }
        }
        Unsigned(n) => {
            _cbor_head(out, 0, n);
        }
        Negative(n) => {
            _cbor_head(out, 1, n);
        }
        Float(n) => {
            _cbor_float(out, n);
        }
        String(text) => {
            var bytes = text.bytes();
            _cbor_head(out, 3, bytes.count);
            out.append_all(bytes);
        }
        Binary(bytes) => {
            _cbor_head(out, 2, bytes.count);
            out.append_all(bytes);
        }
        Array(items) => {
            _cbor_head(out, 4, items.count);
            for (var item in items) {
                _cbor_write(out, item);
            }
        }
        Map(entries) => {
            _cbor_head(out, 5, entries.count);
            for (var (key, member) in entries) {
                _cbor_write(out, key);
                _cbor_write(out, member);
            }
        }
        Extension(kind, data) => {
            _cbor_head(out, 2, data.count);
            out.append_all(data);
        }
        Tag(number, content) => {
            _cbor_head(out, 6, number);
            _cbor_write(out, content);
        }
        Simple(n) => {
            if (n < 24) {
                out.append(0xe0 | n);
            } else {
                out.append(0xf8);
                out.append(n);
            }
        }
    }
}

# `n` as the narrowest float that holds it exactly.
_cbor_float(out: u8[], n: double) {
    if (n.is_nan()) {
        out.append_all([0xf9 as u8, 0x7e, 0x00]);
        return;
    }
    if (!msgpack._fits_float(n)) {
        out.append(0xfb);
        _put(out, unsafe_cast<ulong>(n), 8);
        return;
    }
    var single = unsafe_cast<uint>(n as float) as ulong;
    var half = _cbor_half_of(single);
    if (half.is_value()) {
        out.append(0xf9);
        _put(out, half.value(), 2);
        return;
    }
    out.append(0xfa);
    _put(out, single, 4);
}

# The half-precision bits of single-precision `bits`, when a half holds
# that value exactly.
_cbor_half_of(bits: ulong): ulong? {
    var sign = (bits >> 16) & 0x8000;
    var exponent = ((bits >> 23) & 0xff) as long;
    var mantissa = bits & 0x7fffff;
    if (exponent == 0xff) {
        # An infinity (NaN is handled before).
        return Optional<ulong>.Value(sign | 0x7c00);
    }
    if (exponent == 0 && mantissa == 0) {
        return Optional<ulong>.Value(sign);
    }
    if (exponent == 0) {
        # A single-precision subnormal is far below the smallest half.
        return Optional<ulong>.Empty;
    }
    var power = exponent - 127;
    if (power >= -14 && power <= 15) {
        if ((mantissa & 0x1fff) != 0) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(sign | ((power + 15) as ulong << 10) | (mantissa >> 13));
    }
    if (power >= -24 && power < -14) {
        # A half subnormal: m * 2^-24, with m = 1.mantissa * 2^(power + 24).
        var full = mantissa | 0x800000;
        var shift = (-1 - power) as ulong;
        if ((full & ((1 as ulong << shift) - 1)) != 0) {
            return Optional<ulong>.Empty;
        }
        return Optional<ulong>.Value(sign | (full >> shift));
    }
    return Optional<ulong>.Empty;
}

# ── Reading ────────────────────────────────────────────────────────────────

_cbor_read(reader: msgpack._Reader, depth: ulong): Result<msgpack.Value, msgpack.DecodeError> {
    var start = reader.at;
    reader.enter(depth, start)?;
    var initial = reader.next(start)?;
    var major = initial >> 5;
    var info = initial & 0x1f;
    if (major == 7) {
        return _cbor_simple(reader, info, start);
    }
    if (info == 31) {
        return _cbor_indefinite(reader, major, depth, start);
    }
    var n = _cbor_argument(reader, info, start)?;
    if (major == 0) {
        if (n > 9223372036854775807) {
            return _ok(msgpack.Value.Unsigned(n));
        }
        return _ok(msgpack.Value.Integer(n as long));
    }
    if (major == 1) {
        if (n > 9223372036854775807) {
            return _ok(msgpack.Value.Negative(n));
        }
        return _ok(msgpack.Value.Integer(-1 - n as long));
    }
    if (major == 2) {
        var bytes = reader.bytes(n, start)?;
        return _ok(msgpack.Value.Binary(bytes));
    }
    if (major == 3) {
        var text = reader.string(n, start)?;
        return _ok(msgpack.Value.String(text));
    }
    if (major == 4) {
        reader.fits(n, 1, start)?;
        var items = Array<msgpack.Value>(n);
        for (var index in 0..n) {
            var item = _cbor_read(reader, depth + 1)?;
            items.append(item);
        }
        return _ok(msgpack.Value.Array(items));
    }
    if (major == 5) {
        reader.fits(n, 2, start)?;
        var entries = Array<(msgpack.Value, msgpack.Value)>(n);
        for (var index in 0..n) {
            var key = _cbor_read(reader, depth + 1)?;
            var member = _cbor_read(reader, depth + 1)?;
            entries.append((key, member));
        }
        return _ok(msgpack.Value.Map(entries));
    }
    var content = _cbor_read(reader, depth + 1)?;
    return _ok(msgpack.Value.Tag(n, content));
}

_ok(value: msgpack.Value): Result<msgpack.Value, msgpack.DecodeError> {
    return Result<msgpack.Value, msgpack.DecodeError>.ok(value);
}

_fail(reader: msgpack._Reader, message: String, start: ulong): Result<msgpack.Value, msgpack.DecodeError> {
    return Result<msgpack.Value, msgpack.DecodeError>.err(reader.error(message, start));
}

# The argument additional information `info` (0 to 27) gives.
_cbor_argument(reader: msgpack._Reader, info: u8, start: ulong): Result<ulong, msgpack.DecodeError> {
    if (info < 24) {
        return Result<ulong, msgpack.DecodeError>.ok(info as ulong);
    }
    if (info <= 27) {
        return reader.big_endian(1 as ulong << (info - 24), start);
    }
    return Result<ulong, msgpack.DecodeError>.err(reader.error($"additional information {info} is reserved", start));
}

# An item of major type 7: a simple value or a float.
_cbor_simple(reader: msgpack._Reader, info: u8, start: ulong): Result<msgpack.Value, msgpack.DecodeError> {
    if (info == 20 || info == 21) {
        return _ok(msgpack.Value.Bool(info == 21));
    }
    if (info == 22) {
        return _ok(msgpack.Value.Null);
    }
    if (info == 23) {
        return _ok(msgpack.Value.Undefined);
    }
    if (info < 20) {
        return _ok(msgpack.Value.Simple(info));
    }
    if (info == 24) {
        var n = reader.next(start)?;
        if (n < 32) {
            return _fail(reader, $"simple value {n} must be written in the initial byte", start);
        }
        return _ok(msgpack.Value.Simple(n));
    }
    if (info == 25) {
        var bits = reader.big_endian(2, start)?;
        return _ok(msgpack.Value.Float(_cbor_half(bits)));
    }
    if (info == 26) {
        var bits = reader.big_endian(4, start)?;
        return _ok(msgpack.Value.Float(unsafe_cast<float>(bits as uint) as double));
    }
    if (info == 27) {
        var bits = reader.big_endian(8, start)?;
        return _ok(msgpack.Value.Float(unsafe_cast<double>(bits)));
    }
    if (info == 31) {
        return _fail(reader, "'break' outside an indefinite-length item", start);
    }
    return _fail(reader, $"additional information {info} is reserved", start);
}

# The value of half-precision `bits`.
_cbor_half(bits: ulong): double {
    var exponent = (bits >> 10) & 0x1f;
    var mantissa = bits & 0x3ff;
    var magnitude = 0.0;
    if (exponent == 0) {
        # 2^-24, exactly.
        magnitude = (mantissa as double) * 5.9604644775390625e-8;
    } else if (exponent == 31) {
        # An infinity or NaN: the double's exponent all ones, with the
        # half's mantissa at the top of its own.
        magnitude = unsafe_cast<double>(0x7ff0000000000000 | (mantissa << 42));
    } else {
        magnitude = unsafe_cast<double>(((exponent + 1008) << 52) | (mantissa << 42));
    }
    if ((bits & 0x8000) != 0) {
        return -magnitude;
    }
    return magnitude;
}

# Whether the next byte is a `break`, which it then reads.
_cbor_break(reader: msgpack._Reader, start: ulong): Result<bool, msgpack.DecodeError> {
    reader.need(1, start)?;
    if (reader.data[reader.at] == 0xff) {
        reader.at = reader.at + 1;
        return Result<bool, msgpack.DecodeError>.ok(true);
    }
    return Result<bool, msgpack.DecodeError>.ok(false);
}

# An indefinite-length item of major type `major`: chunks of a string up
# to a `break`, or the items of an array or map.
_cbor_indefinite(
    reader: msgpack._Reader, major: u8, depth: ulong, start: ulong
): Result<msgpack.Value, msgpack.DecodeError> {
    if (major == 2 || major == 3) {
        var joined = Array<u8>();
        while (!_cbor_break(reader, start)?) {
            var chunk_start = reader.at;
            var initial = reader.next(chunk_start)?;
            if (initial >> 5 != major || (initial & 0x1f) == 31) {
                return _fail(
                    reader, "a chunk of an indefinite-length string must be a definite string of its type", chunk_start
                );
            }
            var count = _cbor_argument(reader, initial & 0x1f, chunk_start)?;
            if (major == 3) {
                # Each chunk is UTF-8 on its own.
                var piece = reader.string(count, chunk_start)?;
                joined.append_all(piece.bytes());
            } else {
                var bytes = reader.bytes(count, chunk_start)?;
                joined.append_all(bytes);
            }
        }
        if (major == 3) {
            return _ok(msgpack.Value.String(text.Utf8.decode_lossy(joined)));
        }
        return _ok(msgpack.Value.Binary(joined));
    }
    if (major == 4) {
        var items = Array<msgpack.Value>();
        while (!_cbor_break(reader, start)?) {
            var item = _cbor_read(reader, depth + 1)?;
            items.append(item);
        }
        return _ok(msgpack.Value.Array(items));
    }
    if (major == 5) {
        var entries = Array<(msgpack.Value, msgpack.Value)>();
        while (!_cbor_break(reader, start)?) {
            var key = _cbor_read(reader, depth + 1)?;
            if (_cbor_break(reader, start)?) {
                return _fail(reader, "an indefinite-length map ends after a key, with no value", start);
            }
            var member = _cbor_read(reader, depth + 1)?;
            entries.append((key, member));
        }
        return _ok(msgpack.Value.Map(entries));
    }
    return _fail(reader, $"major type {major} has no indefinite length", start);
}
