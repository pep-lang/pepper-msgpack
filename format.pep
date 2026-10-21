## MessagePack itself: `encode` writes a value in the format and `decode`
## reads one back.

import json;
import "bytes";
import "convert";
import "value";

## Writes `value` as MessagePack, converting it as `to_value` does.
##
## Each item takes the shortest form that holds it: a small integer is one
## byte, a string under 32 bytes a `fixstr`, and so on. A float is written
## as `float 32` when that keeps its value exactly, else as `float 64`.
## The cases MessagePack has no form for are written as their nearest:
## `Undefined` and `Simple` as `nil`, a `Tag` as the item it tags, and a
## `Negative` as a `float 64`.
##
## @typeParam T the type of the value
## @param value the value to write
## @returns the encoded bytes
## @panics if a string, byte string, extension, array or map holds 2^32
##   items or more, which MessagePack cannot write
## @example
##     import digest;
##     import msgpack;
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
##         assert(digest.to_hex(msgpack.encode(p)) == "82a17801a179ff", "a fixmap");
##         return 0;
##     }
export encode<T>(value: T): u8[] {
    var out = Array<u8>();
    _msgpack_write(out, to_value(value));
    return out;
}

## Reads a MessagePack value from `bytes` and converts it to a `T`, as
## `from_value` does; `decode<Value>` gives the value itself.
##
## Decoding is safe for untrusted input: every failure is an error, never a
## panic. A declared length longer than the bytes that remain fails before
## anything is allocated, so a 4 GB length prefix in a short input costs
## nothing, and items may nest only `max_depth` deep. `bytes` must hold
## exactly one value; a string must be UTF-8, and the never-used byte
## `0xc1` is an error.
##
## @typeParam T the type to convert to
## @param bytes the encoded value
## @param unknown_keys what to do with a map key that names no property
## @param max_depth how deep arrays and maps may nest
## @returns the value, or the first error: one in the input's form, at its
##   byte offset, or a conversion error, at its path in the value
## @example
##     import msgpack;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var p = msgpack.decode<Point>([0x82 as u8, 0xa1, 0x78, 0x01, 0xa1, 0x79, 0xff]);
##         assert(p.value().y == -1, "a property");
##
##         var cut = msgpack.decode<Point>([0x81 as u8, 0xa1, 0x78]);
##         assert(cut.error().to_string() == "byte 3: unexpected end of input", "where");
##         return 0;
##     }
export decode<T>(
    bytes: u8[], unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore, max_depth: ulong = 256
): Result<T, DecodeError> {
    var reader = _Reader(bytes, max_depth);
    var value = _msgpack_read(reader, 0)?;
    reader.finish()?;
    return from_value<T>(value, unknown_keys);
}

# ── Writing ────────────────────────────────────────────────────────────────

_msgpack_write(out: u8[], value: Value) {
    match (value) {
        Null => {
            out.append(0xc0);
        }
        Undefined => {
            out.append(0xc0);
        }
        Simple(n) => {
            out.append(0xc0);
        }
        Bool(flag) => {
            if (flag) {
                out.append(0xc3);
            } else {
                out.append(0xc2);
            }
        }
        Integer(n) => {
            _msgpack_integer(out, n);
        }
        Unsigned(n) => {
            out.append(0xcf);
            _put_big_endian(out, n, 8);
        }
        Negative(n) => {
            _msgpack_float(out, -1.0 - n as double);
        }
        Float(n) => {
            _msgpack_float(out, n);
        }
        String(text) => {
            var bytes = text.bytes();
            if (bytes.count < 32) {
                out.append((0xa0 | bytes.count) as u8);
            } else {
                _msgpack_head(out, bytes.count, 0xd9, 0xda, 0xdb);
            }
            out.append_all(bytes);
        }
        Binary(bytes) => {
            _msgpack_head(out, bytes.count, 0xc4, 0xc5, 0xc6);
            out.append_all(bytes);
        }
        Array(items) => {
            _msgpack_count(out, items.count, 0x90, 0xdc, 0xdd);
            for (var item in items) {
                _msgpack_write(out, item);
            }
        }
        Map(entries) => {
            _msgpack_count(out, entries.count, 0x80, 0xde, 0xdf);
            for (var (key, member) in entries) {
                _msgpack_write(out, key);
                _msgpack_write(out, member);
            }
        }
        Extension(kind, data) => {
            # fixext 1, 2, 4, 8 and 16 are 0xd4 to 0xd8.
            var size = data.count;
            if (size == 1 || size == 2 || size == 4 || size == 8 || size == 16) {
                out.append((0xd4 + size.trailing_zeros()) as u8);
            } else {
                _msgpack_head(out, data.count, 0xc7, 0xc8, 0xc9);
            }
            out.append(kind as u8);
            out.append_all(data);
        }
        Tag(number, content) => {
            _msgpack_write(out, content);
        }
    }
}

_msgpack_integer(out: u8[], n: long) {
    if (n >= 0) {
        if (n < 128) {
            out.append(n as u8);
        } else if (n < 256) {
            out.append(0xcc);
            _put_big_endian(out, n as ulong, 1);
        } else if (n < 65536) {
            out.append(0xcd);
            _put_big_endian(out, n as ulong, 2);
        } else if (n < 4294967296) {
            out.append(0xce);
            _put_big_endian(out, n as ulong, 4);
        } else {
            out.append(0xcf);
            _put_big_endian(out, n as ulong, 8);
        }
    } else if (n >= -32) {
        out.append((n + 256) as u8);
    } else if (n >= -128) {
        out.append(0xd0);
        _put_big_endian(out, n as ulong, 1);
    } else if (n >= -32768) {
        out.append(0xd1);
        _put_big_endian(out, n as ulong, 2);
    } else if (n >= -2147483648) {
        out.append(0xd2);
        _put_big_endian(out, n as ulong, 4);
    } else {
        out.append(0xd3);
        _put_big_endian(out, n as ulong, 8);
    }
}

_msgpack_float(out: u8[], n: double) {
    if (_fits_float(n)) {
        out.append(0xca);
        _put_big_endian(out, unsafe_cast<uint>(n as float) as ulong, 4);
    } else {
        out.append(0xcb);
        _put_big_endian(out, unsafe_cast<ulong>(n), 8);
    }
}

# The marker and length of a string, byte string or extension: `head8`
# with a one-byte length, `head16` with two, or `head32` with four.
_msgpack_head(out: u8[], count: ulong, head8: u8, head16: u8, head32: u8) {
    if (count < 256) {
        out.append(head8);
        _put_big_endian(out, count, 1);
    } else {
        _msgpack_count(out, count, 0, head16, head32);
    }
}

# The marker and count of an array or map: `fixed | count` for a count
# under 16 (when `fixed` is not 0), else `head16` or `head32` and the count.
_msgpack_count(out: u8[], count: ulong, fixed: u8, head16: u8, head32: u8) {
    if (fixed != 0 && count < 16) {
        out.append((fixed | count) as u8);
    } else if (count < 65536) {
        out.append(head16);
        _put_big_endian(out, count, 2);
    } else {
        assert(count < 4294967296, "MessagePack cannot write an item of 2^32 or more elements");
        out.append(head32);
        _put_big_endian(out, count, 4);
    }
}

# ── Reading ────────────────────────────────────────────────────────────────

_msgpack_read(reader: _Reader, depth: ulong): Result<Value, DecodeError> {
    var start = reader.at;
    reader.enter(depth, start)?;
    var b = reader.next(start)?;
    if (b < 0x80) {
        return Result<Value, DecodeError>.ok(Value.Integer(b as long));
    }
    if (b >= 0xe0) {
        return Result<Value, DecodeError>.ok(Value.Integer(b as long - 256));
    }
    if (b < 0x90) {
        return _msgpack_map(reader, (b & 0x0f) as ulong, depth, start);
    }
    if (b < 0xa0) {
        return _msgpack_array(reader, (b & 0x0f) as ulong, depth, start);
    }
    if (b < 0xc0) {
        var text = reader.string((b & 0x1f) as ulong, start)?;
        return Result<Value, DecodeError>.ok(Value.String(text));
    }
    if (b == 0xc0) {
        return Result<Value, DecodeError>.ok(Value.Null);
    }
    if (b == 0xc2 || b == 0xc3) {
        return Result<Value, DecodeError>.ok(Value.Bool(b == 0xc3));
    }
    if (b >= 0xc4 && b <= 0xc6) {
        var count = reader.big_endian(1 as ulong << (b - 0xc4), start)?;
        var bytes = reader.bytes(count, start)?;
        return Result<Value, DecodeError>.ok(Value.Binary(bytes));
    }
    if (b >= 0xc7 && b <= 0xc9) {
        var count = reader.big_endian(1 as ulong << (b - 0xc7), start)?;
        return _msgpack_extension(reader, count, start);
    }
    if (b == 0xca) {
        var bits = reader.big_endian(4, start)?;
        return Result<Value, DecodeError>.ok(Value.Float(unsafe_cast<float>(bits as uint) as double));
    }
    if (b == 0xcb) {
        var bits = reader.big_endian(8, start)?;
        return Result<Value, DecodeError>.ok(Value.Float(unsafe_cast<double>(bits)));
    }
    if (b >= 0xcc && b <= 0xcf) {
        var n = reader.big_endian(1 as ulong << (b - 0xcc), start)?;
        if (n > 9223372036854775807) {
            return Result<Value, DecodeError>.ok(Value.Unsigned(n));
        }
        return Result<Value, DecodeError>.ok(Value.Integer(n as long));
    }
    if (b >= 0xd0 && b <= 0xd3) {
        var size = 1 as ulong << (b - 0xd0);
        var n = reader.big_endian(size, start)?;
        # Sign-extends the `size`-byte two's complement value.
        var shift = 64 - size * 8;
        return Result<Value, DecodeError>.ok(Value.Integer(((n << shift) as long) >> shift));
    }
    if (b >= 0xd4 && b <= 0xd8) {
        return _msgpack_extension(reader, 1 as ulong << (b - 0xd4), start);
    }
    if (b >= 0xd9 && b <= 0xdb) {
        var count = reader.big_endian(1 as ulong << (b - 0xd9), start)?;
        var text = reader.string(count, start)?;
        return Result<Value, DecodeError>.ok(Value.String(text));
    }
    if (b == 0xdc || b == 0xdd) {
        var count = reader.big_endian(2 as ulong << (b - 0xdc), start)?;
        return _msgpack_array(reader, count, depth, start);
    }
    if (b == 0xde || b == 0xdf) {
        var count = reader.big_endian(2 as ulong << (b - 0xde), start)?;
        return _msgpack_map(reader, count, depth, start);
    }
    return Result<Value, DecodeError>.err(reader.error("0xc1 is never used in MessagePack", start));
}

_msgpack_array(reader: _Reader, count: ulong, depth: ulong, start: ulong): Result<Value, DecodeError> {
    reader.fits(count, 1, start)?;
    var items = Array<Value>(count);
    for (var index in 0..count) {
        var item = _msgpack_read(reader, depth + 1)?;
        items.append(item);
    }
    return Result<Value, DecodeError>.ok(Value.Array(items));
}

_msgpack_map(reader: _Reader, count: ulong, depth: ulong, start: ulong): Result<Value, DecodeError> {
    reader.fits(count, 2, start)?;
    var entries = Array<(Value, Value)>(count);
    for (var index in 0..count) {
        var key = _msgpack_read(reader, depth + 1)?;
        var member = _msgpack_read(reader, depth + 1)?;
        entries.append((key, member));
    }
    return Result<Value, DecodeError>.ok(Value.Map(entries));
}

# An extension's type byte and its `count` bytes of data.
_msgpack_extension(reader: _Reader, count: ulong, start: ulong): Result<Value, DecodeError> {
    var kind = reader.next(start)?;
    var data = reader.bytes(count, start)?;
    return Result<Value, DecodeError>.ok(Value.Extension(kind as i8, data));
}
