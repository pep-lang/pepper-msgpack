## The dynamic value: `Value`, one item of MessagePack or CBOR whose shape is
## not known ahead, and `DecodeError`, what decoding reports.

import digest;
import json;

## One MessagePack or CBOR item, decoded without a type to read it into, or
## built to be encoded.
##
## One type serves both formats. A case only one of them has is written by
## the other as its nearest form (see `msgpack.encode` and `cbor.encode`).
## `to_string()` writes it in CBOR's diagnostic notation.
##
## @example
##     import msgpack;
##
##     main(): int {
##         var value = msgpack.decode<msgpack.Value>([0x82 as u8, 0xa1, 0x61, 0x01, 0xa1, 0x62, 0x02]).value();
##         assert(value.to_string() == "{\"a\": 1, \"b\": 2}", "a map");
##         assert(value.get("b").value().to_string() == "2", "a member");
##         return 0;
##     }
export enum Value {
    ## MessagePack's `nil`, CBOR's `null`.
    Null,
    ## CBOR's `undefined`.
    Undefined,
    ## A boolean.
    Bool(value: bool),
    ## An integer that fits in a `long`.
    Integer(value: long),
    ## An integer above `long`'s range, up to 2^64 - 1.
    Unsigned(value: ulong),
    ## A CBOR negative integer below `long`'s range: -1 - `value`, down to
    ## -2^64.
    Negative(value: ulong),
    ## A floating-point number, from any of the formats' widths.
    Float(value: double),
    ## A UTF-8 string.
    String(value: String),
    ## A byte string.
    Binary(bytes: u8[]),
    ## An array.
    Array(items: Array<Value>),
    ## A map: its keys and values in order. Keys may be any value, and the
    ## decoders keep duplicates as they come.
    Map(entries: Array<(Value, Value)>),
    ## A MessagePack extension: its type, from -128 to 127, and its data.
    Extension(kind: i8, data: u8[]),
    ## A CBOR tag: its number and the item it tags.
    Tag(number: ulong, content: Value),
    ## A CBOR simple value other than `false`, `true`, `null` and
    ## `undefined`: 0 to 19 or 32 to 255.
    Simple(value: u8),

    ## Returns the value of the first entry whose key is the string `key`,
    ## when this is a `Map`.
    ##
    ## @param key the key to look for
    ## @returns the entry's value, or empty when this is not a map or has no
    ##   such key
    get(key: String): Value? {
        return _value_get(this, key);
    }

    ## Returns the value in CBOR's diagnostic notation (RFC 8949, section 8):
    ## `{"a": [1, h'ff', 2(h'01')], "b": -1.5}`.
    ##
    ## Strings are quoted as JSON quotes them, a float is written as Pepper
    ## writes a `double` (`1.5`, `1e+300`, `Infinity`, `NaN`), and an
    ## extension, which the notation has no form for, as
    ## `ext(kind, h'data')`.
    ##
    ## @returns the text
    to_string(): String {
        return _value_text(this);
    }
}

# The bodies of `Value`'s methods, outside it: inside an enum its case names
# (`String`, `Array`) hide the types of the same names.

_value_get(value: Value, key: String): Value? {
    if (value is Map(entries)) {
        for (var (entry_key, entry_value) in entries) {
            if (entry_key is String(text)) {
                if (text == key) {
                    return Optional<Value>.Value(entry_value);
                }
            }
        }
    }
    return Optional<Value>.Empty;
}

_value_text(value: Value): String {
    match (value) {
        Null => { return "null"; }
        Undefined => { return "undefined"; }
        Bool(flag) => {
            if (flag) {
                return "true";
            }
            return "false";
        }
        Integer(n) => { return $"{n}"; }
        Unsigned(n) => { return $"{n}"; }
        Negative(n) => {
            if (n == 0xffffffffffffffff) {
                return "-18446744073709551616";
            }
            return $"-{n + 1}";
        }
        Float(n) => { return _value_float_text(n); }
        String(text) => { return json.JsonValue.String(text).to_string(); }
        Binary(bytes) => { return $"h'{digest.to_hex(bytes)}'"; }
        Array(items) => {
            var parts = Array<String>(items.count);
            for (var item in items) {
                parts.append(item.to_string());
            }
            return $"[{", ".join(parts)}]";
        }
        Map(entries) => {
            var parts = Array<String>(entries.count);
            for (var (key, member) in entries) {
                parts.append($"{key.to_string()}: {member.to_string()}");
            }
            return "{" + ", ".join(parts) + "}";
        }
        Extension(kind, data) => { return $"ext({kind}, h'{digest.to_hex(data)}')"; }
        Tag(number, content) => { return $"{number}({content.to_string()})"; }
        Simple(n) => { return $"simple({n})"; }
    }
    return "";
}

# A float as diagnostic notation writes it.
_value_float_text(n: double): String {
    if (n.is_nan()) {
        return "NaN";
    }
    if (n.is_infinite()) {
        if (n > 0.0) {
            return "Infinity";
        }
        return "-Infinity";
    }
    return $"{n}";
}

## Why decoding failed: input that is not well formed, or a well-formed
## value that does not convert to the type asked for.
export struct DecodeError {
    ## What is wrong, worded like a compiler error
    ## (`unexpected end of input`), without the place.
    var message: String;
    ## The byte offset, from 0, of the item the error is about; 0 for a
    ## conversion error.
    var offset: ulong;
    ## Where in the value a conversion error is, as a path from the root `$`
    ## (`$.server.port`, `$.tags[2]`); empty for an error in the input's
    ## form.
    var value_path: String;

    ## Creates an error.
    ##
    ## @param message what is wrong
    ## @param offset the byte offset of the item it is about
    ## @param value_path the path of a conversion error, or empty
    construct(message: String = "", offset: ulong = 0, value_path: String = "") {
        this.message = message;
        this.offset = offset;
        this.value_path = value_path;
    }

    ## Returns the error with its place: `byte 12: unexpected end of input`,
    ## or `$.port: expected an integer, found a string`.
    ##
    ## @returns the text
    to_string(): String {
        if (value_path.is_empty) {
            return $"byte {offset}: {message}";
        }
        return $"{value_path}: {message}";
    }
}
