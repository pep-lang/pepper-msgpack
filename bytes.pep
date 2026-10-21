## The byte-level helpers the MessagePack and CBOR codecs share: a bounds-
## checked reader over the input, and big-endian writes. Both formats use
## them, so `cbor` imports them from here.

import text;
import "value";

# A cursor over input bytes that fails, rather than reading past the end,
# with the offset of the item being read. Every length it is asked for is
# checked against the bytes that remain before anything is allocated, so a
# huge declared length fails at once.
export struct _Reader {
    var data: u8[];
    var at: ulong;
    var max_depth: ulong;

    construct(data: u8[], max_depth: ulong) {
        this.data = data;
        this.at = 0;
        this.max_depth = max_depth;
    }

    # The bytes not yet read.
    remaining(): ulong {
        return data.count - at;
    }

    # An error at `offset`.
    error(message: String, offset: ulong): DecodeError {
        return DecodeError(message, offset);
    }

    # Fails unless `count` more bytes remain; `start` is the item's offset.
    need(count: ulong, start: ulong): Result<void, DecodeError> {
        if (count > remaining()) {
            var message = "unexpected end of input";
            if (count > 1) {
                message = $"{message}: the item needs {count} more bytes, {remaining()} remain";
            }
            return Result<void, DecodeError>.err(error(message, start));
        }
        return Result<void, DecodeError>.ok();
    }

    # Fails unless `depth` is within the limit.
    enter(depth: ulong, start: ulong): Result<void, DecodeError> {
        if (depth > max_depth) {
            return Result<void, DecodeError>.err(error($"items nest deeper than {max_depth} levels", start));
        }
        return Result<void, DecodeError>.ok();
    }

    # The next byte.
    next(start: ulong): Result<u8, DecodeError> {
        need(1, start)?;
        var b = data[at];
        at = at + 1;
        return Result<u8, DecodeError>.ok(b);
    }

    # The next `count` bytes (1 to 8) as a big-endian unsigned integer.
    big_endian(count: ulong, start: ulong): Result<ulong, DecodeError> {
        need(count, start)?;
        ulong n = 0;
        for (var index in 0..count) {
            n = (n << 8) | data[at + index] as ulong;
        }
        at = at + count;
        return Result<ulong, DecodeError>.ok(n);
    }

    # The next `count` bytes, copied.
    bytes(count: ulong, start: ulong): Result<u8[], DecodeError> {
        need(count, start)?;
        var out = data.slice(at, at + count).to_array();
        at = at + count;
        return Result<u8[], DecodeError>.ok(out);
    }

    # The next `count` bytes as a string, which must be UTF-8.
    string(count: ulong, start: ulong): Result<String, DecodeError> {
        var raw = bytes(count, start)?;
        var decoded = text.Utf8.decode(raw);
        if (decoded.is_empty()) {
            return Result<String, DecodeError>.err(error("a string is not valid UTF-8", start));
        }
        return Result<String, DecodeError>.ok(decoded.value());
    }

    # Fails unless `count` items, each at least `size` bytes, can fit in
    # what remains, so a container's declared count cannot make it reserve
    # more than the input could fill.
    fits(count: ulong, size: ulong, start: ulong): Result<void, DecodeError> {
        if (count > remaining() / size) {
            return Result<void, DecodeError>.err(
                error($"an array or map of {count} items is longer than the input left", start)
            );
        }
        return Result<void, DecodeError>.ok();
    }

    # Fails unless every byte was read.
    finish(): Result<void, DecodeError> {
        if (at < data.count) {
            return Result<void, DecodeError>.err(error("unexpected data after the value", at));
        }
        return Result<void, DecodeError>.ok();
    }
}

# Appends the low `count` bytes of `n` to `out`, most significant first.
export _put_big_endian(out: u8[], n: ulong, count: ulong) {
    var shift = count * 8;
    while (shift > 0) {
        shift = shift - 8;
        out.append(((n >> shift) & 0xff) as u8);
    }
}

# Whether `n` converts to a `float` and back unchanged (NaN counts, its
# payload aside).
export _fits_float(n: double): bool {
    if (n.is_nan()) {
        return true;
    }
    return (n as float) as double == n;
}
