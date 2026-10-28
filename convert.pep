## Struct conversion: `to_value` turns Pepper values into a `Value` and
## `from_value` turns one back, through reflection, with the attributes of
## the `serialize` module, as `json.to_json` and `json.from_json` do. Both
## formats encode and decode through these.

import json;
import serialize;
import "value";

## Converts `value` to a `Value`.
##
## `T` may be a number type (an `Integer`, `Unsigned` or `Float`), `bool`,
## `String`, `u8[]` (a `Binary`), `Optional<U>` (the value, or `Null`),
## `Array<U>`, a map with `String` keys (`HashMap`, `OrderedMap` or `Map`),
## `Value` itself, an enum, or a struct, whose public properties become a
## map's entries in declaration order, keyed by name. A property takes its
## key from `[Name("key")]` when it has one, and is left out when marked
## `[Ignore]`. A struct reference that holds no object is `Null`.
##
## An enum takes the form `json.to_json` gives it (a case that carries
## nothing as its name, one that carries values as a map, and `[Tag]` and
## `[Untagged]` as for JSON), converted from JSON, so a `u8[]` inside a case
## is an array of integers there.
##
## A type it cannot convert is a compile error.
##
## @typeParam T the type of the value
## @param value the value to convert
## @returns the value as a `Value`
## @example
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
##         p.y = 2;
##         assert(msgpack.to_value(p).to_string() == "{\"x\": 1, \"y\": 2}", "a map");
##         return 0;
##     }
export to_value<T>(value: T): Value {
    return _to_value(value);
}

## Converts a `Value` to a `T`, the reverse of `to_value`.
##
## A struct is made with its constructor that takes no arguments, then each
## entry of the map whose key names a property is read in. A missing key
## leaves its property at its default, unless the property is marked
## `[Required]`, which makes it an error; a property marked `[Ignore]` is
## never read. A key that names no property is skipped, or with
## `unknown_keys = msgpack.UnknownKeys.Reject` is an error.
##
## An integer converts to an integer type it fits, and to `float` or
## `double`; a `u8[]` reads a `Binary` or an array of integers; `Null`
## converts only to an `Optional` (as none), a struct reference, and
## `Value`. A `Tag` converts as the item it tags, so a tagged value reads
## into the type of its content.
##
## @typeParam T the type to convert to
## @param value the value
## @param unknown_keys what to do with a map key that names no property
## @returns the converted value, or the first error, whose `value_path`
##   says where in the value it is
## @example
##     import msgpack;
##
##     struct Point {
##         var x: int;
##         var y: int;
##     }
##
##     main(): int {
##         var entries = Array<(msgpack.Value, msgpack.Value)>();
##         entries.append((msgpack.Value.String("y"), msgpack.Value.Integer(2)));
##         var p = msgpack.from_value<Point>(msgpack.Value.Map(entries));
##         assert(p.value().y == 2, "a property");
##         return 0;
##     }
export from_value<T>(value: Value, unknown_keys: json.UnknownKeys = json.UnknownKeys.Ignore): Result<T, DecodeError> {
    var witness: T;
    return _from_value(value, witness, "$", unknown_keys);
}

# ── Encoding ───────────────────────────────────────────────────────────────
#
# One overload per kind of type, as in `json`: overload resolution picks
# the most specialized, and the catch-all handles numbers, enums and
# structs in a static block.

_to_value(value: String): Value {
    if (value === __null) {
        return Value.Null;
    }
    return Value.String(value);
}

_to_value(value: Value): Value {
    if (value === __null) {
        return Value.Null;
    }
    return value;
}

_to_value(value: bool): Value {
    return Value.Bool(value);
}

_to_value(value: u8[]): Value {
    if (value === __null) {
        return Value.Binary(Array<u8>());
    }
    return Value.Binary(value);
}

_to_value<T>(value: T?): Value {
    if (value.is_value()) {
        return _to_value(value.value());
    }
    return Value.Null;
}

_to_value<T>(value: Array<T>): Value {
    var items = Array<Value>(value.count);
    for (var element in value) {
        items.append(_to_value(element));
    }
    return Value.Array(items);
}

_to_value<V>(value: HashMap<String, V>): Value {
    return _value_map_of(value);
}

_to_value<V>(value: OrderedMap<String, V>): Value {
    return _value_map_of(value);
}

_to_value<V>(value: Map<String, V>): Value {
    return _value_map_of(value);
}

# A map of the entries of `map`, any map with `String` keys.
_value_map_of<TMap>(map: TMap): Value {
    if (map === __null) {
        return Value.Null;
    }
    var entries = Array<(Value, Value)>();
    for (var (key, member) in map) {
        entries.append((Value.String(key), _to_value(member)));
    }
    return Value.Map(entries);
}

_to_value<T>(value: T): Value {
    var out = Value.Null;
    # Runtime locals of the static block: whether a struct reference holds
    # an object, so its properties can be read, and its entries.
    var present = true;
    var entries = Array<(Value, Value)>();
    static (out, value, present, entries) {
        if (reflect.is_same<T, i8>()
            || reflect.is_same<T, i16>()
            || reflect.is_same<T, i32>()
            || reflect.is_same<T, i64>()
            || reflect.is_same<T, u8>()
            || reflect.is_same<T, u16>()
            || reflect.is_same<T, u32>()) {
            out = Value.Integer(value as long);
        } else if (reflect.is_same<T, u64>()) {
            out = _value_of_ulong(value);
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            out = Value.Float(value as double);
        } else if (reflect.is_enum<T>()) {
            out = _value_from_json(json.to_json(value));
        } else if (reflect.is_struct<T>()) {
            present = !_value_is_null(value);
            for (var field in reflect.properties<T>()) {
                if (field.has_attribute<serialize.Ignore>()) {
                    continue;
                }
                var key = field.name;
                if (field.has_attribute<serialize.Name>()) {
                    key = field.attribute<serialize.Name>().value;
                }
                if (present) {
                    entries.append((Value.String(key), _to_value(field.get(value))));
                }
            }
            if (present) {
                out = Value.Map(entries);
            }
        } else {
            reflect.error($"'encode' cannot convert type '{reflect.name<T>()}'");
        }
    }
    return out;
}

# Whether struct reference `value` holds no object.
_value_is_null<T>(value: T): bool {
    return value === __null;
}

_value_of_ulong(value: ulong): Value {
    if (value <= 9223372036854775807) {
        return Value.Integer(value as long);
    }
    return Value.Unsigned(value);
}

# A `Value` of JSON's, for an enum `json.to_json` converted.
_value_from_json(value: json.JsonValue): Value {
    match (value) {
        Null => { return Value.Null; }
        Bool(flag) => { return Value.Bool(flag); }
        Integer(n) => { return Value.Integer(n); }
        Number(n) => { return Value.Float(n); }
        String(text) => { return Value.String(text); }
        Array(items) => {
            var out = Array<Value>(items.count);
            for (var item in items) {
                out.append(_value_from_json(item));
            }
            return Value.Array(out);
        }
        Object(members) => {
            var entries = Array<(Value, Value)>();
            for (var (key, member) in members) {
                entries.append((Value.String(key), _value_from_json(member)));
            }
            return Value.Map(entries);
        }
    }
    return Value.Null;
}

# ── Decoding ───────────────────────────────────────────────────────────────
#
# As in `json`, the overload is picked by the type of `witness`, a value of
# the target type used only to choose it.

_from_value(value: Value, witness: Value, path: String, unknown_keys: json.UnknownKeys): Result<Value, DecodeError> {
    return Result<Value, DecodeError>.ok(value);
}

_from_value(value: Value, witness: String, path: String, unknown_keys: json.UnknownKeys): Result<String, DecodeError> {
    var item = _value_untagged(value);
    if (item is String(text)) {
        return Result<String, DecodeError>.ok(text);
    }
    return Result<String, DecodeError>.err(_value_mismatch(path, "a string", item));
}

_from_value(value: Value, witness: bool, path: String, unknown_keys: json.UnknownKeys): Result<bool, DecodeError> {
    var item = _value_untagged(value);
    if (item is Bool(flag)) {
        return Result<bool, DecodeError>.ok(flag);
    }
    return Result<bool, DecodeError>.err(_value_mismatch(path, "a boolean", item));
}

_from_value(value: Value, witness: u8[], path: String, unknown_keys: json.UnknownKeys): Result<u8[], DecodeError> {
    var item = _value_untagged(value);
    if (item is Binary(bytes)) {
        return Result<u8[], DecodeError>.ok(bytes);
    }
    if (item is Array(items)) {
        var out = Array<u8>(items.count);
        for (var index in 0..items.count) {
            var n = _value_integer(items[index], $"{path}[{index}]", 0, 255, "u8")?;
            out.append(n as u8);
        }
        return Result<u8[], DecodeError>.ok(out);
    }
    return Result<u8[], DecodeError>.err(_value_mismatch(path, "a byte string", item));
}

_from_value<T>(value: Value, witness: T?, path: String, unknown_keys: json.UnknownKeys): Result<T?, DecodeError> {
    if (_value_untagged(value) is Null) {
        return Result<T?, DecodeError>.ok(Optional<T>.Empty);
    }
    var inner: T;
    var result = _from_value(value, inner, path, unknown_keys)?;
    return Result<T?, DecodeError>.ok(Optional<T>.Value(result));
}

_from_value<T>(
    value: Value, witness: Array<T>, path: String, unknown_keys: json.UnknownKeys
): Result<Array<T>, DecodeError> {
    var item = _value_untagged(value);
    if (item is Array(items)) {
        var out = Array<T>(items.count);
        var element: T;
        for (var index in 0..items.count) {
            var converted = _from_value(items[index], element, $"{path}[{index}]", unknown_keys)?;
            out.append(converted);
        }
        return Result<Array<T>, DecodeError>.ok(out);
    }
    return Result<Array<T>, DecodeError>.err(_value_mismatch(path, "an array", item));
}

_from_value<V>(
    value: Value, witness: HashMap<String, V>, path: String, unknown_keys: json.UnknownKeys
): Result<HashMap<String, V>, DecodeError> {
    var element: V;
    return _value_read_entries(value, HashMap<String, V>(), element, path, unknown_keys);
}

_from_value<V>(
    value: Value, witness: OrderedMap<String, V>, path: String, unknown_keys: json.UnknownKeys
): Result<OrderedMap<String, V>, DecodeError> {
    var element: V;
    return _value_read_entries(value, OrderedMap<String, V>(), element, path, unknown_keys);
}

_from_value<V>(
    value: Value, witness: Map<String, V>, path: String, unknown_keys: json.UnknownKeys
): Result<Map<String, V>, DecodeError> {
    var element: V;
    return _value_read_entries(value, Map<String, V>(), element, path, unknown_keys);
}

# Reads the entries of map `value` into `map`, any map with `String` keys
# whose values are `V`s, like `element`.
_value_read_entries<TMap, V>(
    value: Value, map: TMap, element: V, path: String, unknown_keys: json.UnknownKeys
): Result<TMap, DecodeError> {
    var item = _value_untagged(value);
    if (item is Map(entries)) {
        for (var (key, member) in entries) {
            var name = _value_key(key, path)?;
            var converted = _from_value(member, element, _value_path_key(path, name), unknown_keys)?;
            map[name] = converted;
        }
        return Result<TMap, DecodeError>.ok(map);
    }
    return Result<TMap, DecodeError>.err(_value_mismatch(path, "a map", item));
}

_from_value<T>(value: Value, witness: T, path: String, unknown_keys: json.UnknownKeys): Result<T, DecodeError> {
    var item = _value_untagged(value);
    var result = Result<T, DecodeError>.ok(witness);
    # Runtime locals of the static block, which a `var` inside it would make
    # compile-time values.
    var error = Optional<DecodeError>.Empty;
    var out = witness;
    var known = Array<String>();
    var member = Optional<Value>.Empty;
    var is_map = item is Map;
    static (item, path, unknown_keys, result, error, out, known, member, is_map) {
        if (reflect.is_same<T, i8>()) {
            result = _value_read_integer(item, path, -128, 127, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, i16>()) {
            result = _value_read_integer(item, path, -32768, 32767, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, i32>()) {
            result = _value_read_integer(item, path, -2147483648, 2147483647, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, i64>()) {
            result = _value_read_integer(
                item, path, -9223372036854775807 - 1, 9223372036854775807, reflect.name<T>(), witness
            );
        } else if (reflect.is_same<T, u8>()) {
            result = _value_read_integer(item, path, 0, 255, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, u16>()) {
            result = _value_read_integer(item, path, 0, 65535, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, u32>()) {
            result = _value_read_integer(item, path, 0, 4294967295, reflect.name<T>(), witness);
        } else if (reflect.is_same<T, u64>()) {
            result = _value_read_ulong(item, path, witness);
        } else if (reflect.is_same<T, float>() || reflect.is_same<T, double>()) {
            result = _value_read_double(item, path, witness);
        } else if (reflect.is_enum<T>()) {
            result = _value_read_enum(item, path, unknown_keys, witness);
        } else if (reflect.is_struct<T>()) {
            # The checks are runtime code, so they sit inside the property
            # loop rather than around it.
            if (item is Null) {
                out = _value_null(out);
            } else if (is_map) {
                out = _value_new(out);
            } else {
                error = Optional<DecodeError>.Value(_value_mismatch(path, "a map", item));
            }
            for (var field in reflect.properties<T>()) {
                if (field.has_attribute<serialize.Ignore>()) {
                    continue;
                }
                var key = field.name;
                if (field.has_attribute<serialize.Name>()) {
                    key = field.attribute<serialize.Name>().value;
                }
                known.append(key);
                if (error.is_empty() && is_map) {
                    member = item.get(key);
                    if (member.is_value()) {
                        var converted = _from_value(
                            member.value(), field.get(out), _value_path_key(path, key), unknown_keys
                        );
                        if (converted.is_err()) {
                            error = Optional<DecodeError>.Value(converted.error());
                        } else {
                            field.set(out, converted.value());
                        }
                    } else if (field.has_attribute<serialize.Required>()) {
                        error = Optional<DecodeError>.Value(_value_error(path, $"missing required key '{key}'"));
                    }
                }
            }
            if (error.is_empty() && is_map && unknown_keys == json.UnknownKeys.Reject) {
                error = _value_unknown_key(item, known, path);
            }
            result = Result<T, DecodeError>.ok(out);
        } else {
            reflect.error($"'decode' cannot convert type '{reflect.name<T>()}'");
        }
    }
    if (error.is_value()) {
        return Result<T, DecodeError>.err(error.value());
    }
    return result;
}

# A new `T`, from its constructor that takes no arguments; `witness` only
# names the type.
_value_new<T>(witness: T): T {
    return T();
}

# A null reference of `witness`'s type, for `Null`.
_value_null<T>(witness: T): T {
    return __null;
}

# The item a chain of tags tags; `value` itself when it is not a tag.
_value_untagged(value: Value): Value {
    var item = value;
    while (item is Tag(number, content)) {
        item = content;
    }
    return item;
}

# `value` as an integer in [low, high], as the integer type of `witness`.
_value_read_integer<T>(
    value: Value, path: String, low: long, high: long, type_name: String, witness: T
): Result<T, DecodeError> {
    var n = _value_integer(value, path, low, high, type_name)?;
    return Result<T, DecodeError>.ok(n as T);
}

_value_integer(value: Value, path: String, low: long, high: long, type_name: String): Result<long, DecodeError> {
    var item = _value_untagged(value);
    if (item is Integer(n)) {
        if (n < low || n > high) {
            return Result<long, DecodeError>.err(_value_error(path, $"{n} does not fit in '{type_name}'"));
        }
        return Result<long, DecodeError>.ok(n);
    }
    if (item is Unsigned(n)) {
        return Result<long, DecodeError>.err(_value_error(path, $"{n} does not fit in '{type_name}'"));
    }
    if (item is Negative(n)) {
        return Result<long, DecodeError>.err(_value_error(path, $"{item.to_string()} does not fit in '{type_name}'"));
    }
    return Result<long, DecodeError>.err(_value_mismatch(path, "an integer", item));
}

# `value` as a `ulong`, the type of `witness`.
_value_read_ulong<T>(value: Value, path: String, witness: T): Result<T, DecodeError> {
    if (value is Unsigned(n)) {
        return Result<T, DecodeError>.ok(n as T);
    }
    var n = _value_integer(value, path, 0, 9223372036854775807, "u64")?;
    return Result<T, DecodeError>.ok(n as T);
}

# `value`, any number, as the float type of `witness`.
_value_read_double<T>(value: Value, path: String, witness: T): Result<T, DecodeError> {
    if (value is Float(n)) {
        return Result<T, DecodeError>.ok(n as T);
    }
    if (value is Integer(n)) {
        return Result<T, DecodeError>.ok(n as T);
    }
    if (value is Unsigned(n)) {
        return Result<T, DecodeError>.ok(n as T);
    }
    if (value is Negative(n)) {
        return Result<T, DecodeError>.ok((-1.0 - n as double) as T);
    }
    return Result<T, DecodeError>.err(_value_mismatch(path, "a number", value));
}

# `value` read into the enum type of `witness`, through `json.from_json`.
_value_read_enum<T>(value: Value, path: String, unknown_keys: json.UnknownKeys, witness: T): Result<T, DecodeError> {
    var converted = _value_to_json(value, path)?;
    var result = json.from_json<T>(converted, unknown_keys);
    if (result.is_err()) {
        # JSON's paths start at its own root `$`; this one starts at `path`.
        var inner = result.error();
        var at = path + inner.value_path.substr_bytes(1, inner.value_path.size - 1);
        var message = inner.message;
        var prefix = inner.value_path + ": ";
        if (message.starts_with(prefix)) {
            message = message.substr_bytes(prefix.size, message.size - prefix.size);
        }
        return Result<T, DecodeError>.err(_value_error(at, message));
    }
    return Result<T, DecodeError>.ok(result.value());
}

# `value` as JSON, for an enum that `json.from_json` reads: a byte string
# becomes an array of its bytes, and a map needs string keys.
_value_to_json(value: Value, path: String): Result<json.JsonValue, DecodeError> {
    match (value) {
        Null => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Null); }
        Undefined => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Null); }
        Bool(flag) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Bool(flag)); }
        Integer(n) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Integer(n)); }
        Float(n) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Number(n)); }
        String(text) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.String(text)); }
        Binary(bytes) => {
            var items = Array<json.JsonValue>(bytes.count);
            for (var b in bytes) {
                items.append(json.JsonValue.Integer(b as long));
            }
            return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Array(items));
        }
        Array(items) => {
            var out = Array<json.JsonValue>(items.count);
            for (var index in 0..items.count) {
                var converted = _value_to_json(items[index], $"{path}[{index}]")?;
                out.append(converted);
            }
            return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Array(out));
        }
        Map(entries) => {
            var object = json.JsonValue.object();
            for (var (key, member) in entries) {
                var name = _value_key(key, path)?;
                var converted = _value_to_json(member, _value_path_key(path, name))?;
                object[name] = converted;
            }
            return Result<json.JsonValue, DecodeError>.ok(object);
        }
        Tag(number, content) => { return _value_to_json(content, path); }
        Unsigned(n) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Number(n as double)); }
        Negative(n) => { return Result<json.JsonValue, DecodeError>.ok(json.JsonValue.Number(-1.0 - n as double)); }
        Extension(kind, data) => {}
        Simple(n) => {}
    }
    return Result<json.JsonValue, DecodeError>.err(_value_mismatch(path, "a value an enum reads", value));
}

# A map key that must be a string, to name a property or a map entry.
_value_key(key: Value, path: String): Result<String, DecodeError> {
    if (key is String(text)) {
        return Result<String, DecodeError>.ok(text);
    }
    return Result<String, DecodeError>.err(_value_error(path, $"expected a string key, found {key.to_string()}"));
}

# The first key of map `value` that is not in `known`, as an error.
_value_unknown_key(value: Value, known: Array<String>, path: String): DecodeError? {
    if (value is Map(entries)) {
        for (var (key, member) in entries) {
            if (key is String(text)) {
                if (!known.contains(text)) {
                    return Optional<DecodeError>.Value(
                        _value_error(_value_path_key(path, text), $"unknown key '{text}'")
                    );
                }
            } else {
                return Optional<DecodeError>.Value(
                    _value_error(path, $"unknown key {key.to_string()}: a struct's keys are strings")
                );
            }
        }
    }
    return Optional<DecodeError>.Empty;
}

# `path` and then `key`: `$.name`, or `$["two words"]` for a key that is not
# a plain name.
_value_path_key(path: String, key: String): String {
    var plain = !key.is_empty;
    for (var b in key.bytes()) {
        if (!((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_')) {
            plain = false;
        }
    }
    if (plain) {
        return $"{path}.{key}";
    }
    return $"{path}[{json.JsonValue.String(key).to_string()}]";
}

_value_error(path: String, message: String): DecodeError {
    return DecodeError(message, value_path = path);
}

_value_mismatch(path: String, expected: String, found: Value): DecodeError {
    return _value_error(path, $"expected {expected}, found {_value_kind(found)}");
}

# How an error names a value's kind: "a string", "null".
_value_kind(value: Value): String {
    match (value) {
        Null => { return "null"; }
        Undefined => { return "undefined"; }
        Bool(flag) => { return "a boolean"; }
        Integer(n) => { return "an integer"; }
        Unsigned(n) => { return "an integer"; }
        Negative(n) => { return "an integer"; }
        Float(n) => { return "a float"; }
        String(text) => { return "a string"; }
        Binary(bytes) => { return "a byte string"; }
        Array(items) => { return "an array"; }
        Map(entries) => { return "a map"; }
        Extension(kind, data) => { return "an extension"; }
        Tag(number, content) => { return "a tag"; }
        Simple(n) => { return "a simple value"; }
    }
    return "";
}
