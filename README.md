# pepper-msgpack

[MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md) and
[CBOR](https://www.rfc-editor.org/rfc/rfc8949) for
[Pepper](https://github.com/pep-lang/pepper): compact binary encodings for
RPC and storage (CBOR is what WebAuthn and COSE speak). Structs convert
with the same `serialize` attributes `json` reads (`[Name]`, `[Ignore]`,
`[Required]`, `[Tag]`, `[Untagged]`), and a dynamic `Value` holds anything
of no fixed type. Pure Pepper, no C dependencies.

Two modules:

- **`msgpack`**: `encode(value)` and `decode<T>(bytes)`, the dynamic
  `Value`, `to_value` and `from_value` for struct conversion, and
  `DecodeError`.
- **`msgpack.cbor`**: the same `encode` and `decode<T>` for CBOR, with
  tags, simple values, half floats and indefinite lengths. It shares
  `Value` and `DecodeError` (`cbor.Value` is `msgpack.Value`).

```pepper
import msgpack;
import msgpack.cbor;
import serialize;

struct Reading {
    [Required]
    var sensor: String;
    var celsius: double;
    [Name("raw")]
    var samples: u8[];
}

main(): int {
    var reading = Reading();
    reading.sensor = "porch";
    reading.celsius = 21.5;
    reading.samples = [1 as u8, 2, 3];

    var packed = msgpack.encode(reading);           # 36 bytes
    var back = msgpack.decode<Reading>(packed);
    if (back.is_err()) {
        print(back.error().to_string());            # e.g. "$: missing required key 'sensor'"
        return 1;
    }

    var any = cbor.decode<cbor.Value>(cbor.encode(reading)).value();
    print(any.to_string());   # {"sensor": "porch", "celsius": 21.5, "raw": h'010203'}
    return 0;
}
```

## What converts

| Pepper | Value | MessagePack | CBOR |
| --- | --- | --- | --- |
| integers | `Integer`, `Unsigned` | shortest int / uint | major 0 / 1 |
| `float`, `double` | `Float` | float 32 when exact, else 64 | half, single or double, whichever is exact |
| `bool`, empty `T?` | `Bool`, `Null` | bool, nil | `true`/`false`, `null` |
| `String` | `String` | str | text string |
| `u8[]` | `Binary` | bin | byte string |
| `Array<T>` | `Array` | array | array |
| `HashMap`/`OrderedMap`/`Map<String, V>`, structs | `Map` | map | map |
| enums | as `json.to_json` writes them | | |
| | `Extension` | ext | (byte string of its data) |
| | `Tag`, `Simple`, `Undefined`, `Negative` | (the tagged item, nil, float 64) | tag, simple value, `undefined`, major 1 |

Decoding takes the other direction and is lenient where it is safe: an
integer reads into a float, a `u8[]` reads an array of integers, and a
`Tag` reads as the item it tags. `Value.to_string()` writes CBOR's
diagnostic notation.

## Untrusted input

`decode` never panics on input, and returns a `DecodeError` with the byte
offset (or, for a conversion error, the path in the value, like
`$.tags[2]`). Every declared length is checked against the bytes that
remain before anything is allocated, so a 4 GB length prefix in a short
input fails at once; items nest at most `max_depth` deep (256 by default);
strings must be UTF-8; and the input must hold exactly one value.

## Limits

- Encoding and decoding work on a whole `u8[]`; there is no streaming
  reader or writer, and no decoding of several concatenated values.
- Map keys of structs and `HashMap`s are strings; a `Value` holds any key.
- An enum converts through `json`'s form, so a `u8[]` inside an enum case
  is written as an array of integers.
- CBOR bignums (tags 2 and 3) decode as tagged byte strings, and the
  encoder writes definite lengths only.

## Using it

This repository is a package: `pep.toml` marks its root, its root
`module.pep` is the `msgpack` module, and `cbor/module.pep` is
`msgpack.cbor`. Add it to a project under the name `msgpack`:

```sh
pepper package add pep-lang/pepper-msgpack --name msgpack
```

which writes

```toml
[dependencies]
msgpack = { github = "pep-lang/pepper-msgpack" }
```

Without a project, put a folder named `msgpack` that holds (or links to)
this repository on the import path: `pepper build -I packages main.pep`.

## Tests

```sh
tests/run.sh path/to/pepper
```

runs the `[Test]` functions in `tests/` with `pepper test`: every
MessagePack format family, RFC 8949 Appendix A, struct round trips through
both formats, and truncated, oversized, deeply nested and random input.

## Releasing

CI (`.github/workflows/ci.yml`) runs the tests on Linux, macOS and
Windows for every push to `main` and every pull request. To release, set
`version` in `pep.toml`, merge, then push the matching tag
(`git tag v1.0.0 && git push origin v1.0.0`): CI tests the tag and
publishes a GitHub release for it. `pepper package add` and `pepper
package update` find versions by their tags.

## License

Apache-2.0; see [LICENSE](LICENSE).
