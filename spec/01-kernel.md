# 01 — The document kernel {#documents-kernel}

<!-- surfex: class orientation -->

Every declarative value Macaw reads is a **document**: pages, surfaces, templates, layers, themes, visualize designs, component settings and records ([macaw_compose 01](https://github.com/dcoai/macaw/blob/main/spec/01-vocabulary.md#vocab-documents)). One kernel reads them all. It knows nothing of any document type: each type brings its own keys, schema, migration steps, tags and wording, and the kernel supplies everything they share.

The kernel generalizes what visualize built for its designs, fragments, boards, snapshots and bundles. That code is spread over `Visualize.Chart.Migration`, `Chart.Limits`, `Chart.Codec.Tags`, `Chart.Codec`, `Chart.Validator`, `Chart.Names` and `Visualize.Vocabulary`. What is generic in it moves here; what is chart-specific stays in visualize as an implementer of the kernel's behaviors ([macaw_compose 00 §5](https://github.com/dcoai/macaw/blob/main/spec/00-overview.md#overview-order), step 2).

| Module | What it is | § |
|---|---|---|
| `Macaw.Layers.Names` | names a document declares: strings, never atoms made from data | 1 |
| `Macaw.Layers.Vocabulary` | closed vocabularies looked up by spelling | 2 |
| `Macaw.Layers.Fault` | the fault `{path, reason}`, its order, and the one formatter | 3 |
| `Macaw.Layers.Version` | one version line per document type, and stepwise migration | 4 |
| `Macaw.Layers.Document` | a value judged by its type, `check/2`, with no encoding | 5 |
| `Macaw.Layers.Form`, `Macaw.Layers.Limits`, `Macaw.Layers.Scan` | the JSON adapter: the gates, in order, and reading a document to its value | 5 |
| `Macaw.Layers.Tags`, `Macaw.Layers.Form` | the map and JSON forms: the codec, `to_json/2`, and the `$` tag table | 6 |
| `Macaw.Layers.Document.digest/1` | a canonical digest | 7 |
| `Macaw.Layers.Callback` | optional callbacks, found whether or not their module is loaded | 9 |

## 1. Names {#kernel-names}

**A name a document declares is a string:** a source, a field, a variable, a frame, a style, a fragment's key. Elixir input may spell a name as an atom, which is read as the string of the same spelling with `Atom.to_string/1`, which makes no atom. Nothing in the kernel ever makes an atom from document data.

`Macaw.Layers.Names`:
- `is_name/1`, a guard: a string, or an atom other than `nil`, `true` and `false`.
- `name/1`: an atom's spelling (except `nil`, `true` and `false`), a string as it is, and any other value untouched, so a validator can name it as malformed.
- `name?/1`: `true` for a non-empty string or an atom other than `nil`, `true` and `false`; `false` for anything else, the empty string included.
- `category/1`: a category value as it is compared. An atom other than `nil`, `true` and `false` becomes its spelling; anything else stays as it is.
- `same?/2`: two category values are one when they are equal or spell the same, so `:ok` and `"ok"` are one value and `true` and `"true"` are not.
- `keys/1`: a plain map's keys as names, values untouched. A struct, or anything not a map, is returned unchanged.
- `key/2`: the key of a map that spells a name, as `{:ok, key}`: the name itself when the map has it, else a key of the other spelling (an atom key for a string name, or a string key for an atom name). `:error` when none does, and for a name that is neither a string nor an atom.
- `fetch/2`: `Map.fetch/2` by spelling, through `key/2`.

```test:names-name
name/1 reads :sales and "sales" as "sales", leaves nil, true, false, 3 and {:id, 1} untouched, and makes no atom
```

```test:names-predicate
name?/1 holds for "a" and :a and not for "", nil, true, false, 1 or a list; is_name/1 agrees in a guard for every value but ""
```

```test:names-category
category/1 turns :ok into "ok" and leaves nil, true, false, numbers and strings alone; same?/2 holds for :ok and "ok", and for 1 and 1, and not for true and "true"
```

```test:names-keys
keys/1 rewrites %{a: 1, "b" => 2} to %{"a" => 1, "b" => 2}, and returns a struct or a list unchanged
```

```test:names-key
key/2 and fetch/2 find a string name under an atom key and an atom name under a string key, prefer the exact key when both are present, and give :error for a missing name or one that is neither a string nor an atom
```

## 2. Closed vocabularies {#kernel-vocabulary}

**A closed vocabulary is read from a string by lookup.** A table maps each member's spelling to the member, built from the vocabulary's own list. A reader looks a document's string up in it and never makes an atom of one. Nor does it ask the node whether such an atom exists (`String.to_existing_atom/1`): that would let a document probe the atom table, and make a read depend on which modules happen to be loaded. A string the table lacks is the caller's to refuse at its path.

`Macaw.Layers.Vocabulary`:
- `table/1`: the table of a list of atoms, `%{"spelling" => atom}`, built once, in a module attribute wherever the list is known at compile time.
- `fetch/2`: `{:ok, member}` for a string the table (or, for a short list known only at run time, the list) has, else `:error`. Anything that is not a string is `:error`.
- `read/2`: the member a string spells, or the string itself, so a validator refuses it by type at its path.

```test:vocabulary-lookup
a table of [:title, :caption] fetches "title" as :title, gives :error for "footer", for :title and for 1, and the list form agrees with the table form
```

```test:vocabulary-no-atoms
reading 2 000 fresh strings through fetch/2 and read/2 makes none of them an atom, and read/2 returns each string as it was
```

## 3. Faults {#kernel-faults}

**A fault is `{path, reason}`.** The path is a list of keys and indexes from the document's root: atoms or strings for keys, non-negative integers for list positions. A key the document type does not know stays at its own spelling, a string, so a fault can name it without an atom made (§1).

- **Every fault is reported, never just the first.** A reader collects them all.
- **Faults are ordered by path:** `Macaw.Layers.Fault.sort/1` sorts by the path in Erlang term order, keeping the reader's order among faults at the same path.
- **One formatter words every fault,** `Macaw.Layers.Fault.format/2`, as `path: words`.
  - `format_path/2` spells a path as a person reads it: keys joined by `.`, an index as `[i]`, so `[:marks, 0, :channels]` is `marks[0].channels`. The empty path is the root, named by the option `root:` (default `"document"`; visualize's designs name it `"design"`).
  - The kernel words its own reasons, listed below. Any other reason is the document type's: `format/2` passes it to the function given as `words:`, and without one it is shown with `inspect/1`. A formatter never fails on a reason it does not know.

The kernel's reasons and their words:

| Reason | Words |
|---|---|
| `:required` | is required |
| `:unknown_key` | is not a key of this node |
| `:key_spelling` | is a name spelled like a key of this document; it would read back as the key |
| `{:type, type}` | must be *type*, for the types below; any other type is the document type's to word |
| `{:enum, allowed}` | must be one of *allowed*, each shown with `inspect/1`, joined by `, ` |
| `{:newer_schema, needs, this}` | needs schema v*needs*, this is v*this* |
| `{:limit, name, max, given}` | for `:bytes`, is *given* bytes; the limit bytes is *max*; for `:depth`, is nested *given* deep; the limit depth is *max*; for `:items`, holds at least *given* items; the limit items is *max* (a scan that stops at the limit knows only that much) |
| `{:json, message}` | JSON does not parse: *message* |
| `{:unknown_tag, tag}` | *tag* is not a tag this document reads |
| `{:retired_tag, tag, why}` | *tag* *why* |

The types the kernel words in `{:type, type}`: `:string` (a string), `:name` (a name: a non-empty string), `:integer` (an integer), `:non_neg_integer` (a non-negative integer), `:pos_integer` (a positive integer), `:number` (a number), `:positive` (a positive number), `:boolean` (true or false), `:map` (a map), `:list` (a list), `:term` (a value with a document form: no function, PID, reference, port, tuple or struct), `:time` (an ISO 8601 time in UTC), `{:enum, allowed}` (one of *allowed*), `{:list, t}` (a list of *t*), `{:map, t}` (a map from names to *t*), `{:node, kind}` (a *kind* node), and `{:one_of, types}` (each type's words joined by ` or `). A compound type whose part the kernel does not word is the document type's to word whole.

```test:faults-sort
sort/1 orders faults by path, keys and indexes mixed, and keeps the given order of faults at one path; it is total over generated paths
```

```test:faults-path
format_path/2 spells [:marks, 0, :channels] as marks[0].channels, [:frames, "main", "wdth"] as frames.main.wdth, and [] as the root option, "document" by default
```

```test:faults-words
format/2 words each of the kernel's reasons as the table says, and every type in the list inside {:type, _}
```

```test:faults-fallback
a reason the kernel does not word goes to the words: function, a {:type, t} with a type outside the kernel's list goes to it whole, and with no function the reason is shown with inspect/1; no reason makes format/2 fail
```

## 4. Version lines and migration {#kernel-versions}

**Each document type has its own version line,** a positive integer that starts at 1 and rises by one with each change that needs a migration. A document carries its version as the stamp `"$version"`: a string key at the top of the document, in the map form and the JSON form alike. Two types' lines are independent: a new step for one moves no other.

A document type implements the behavior `Macaw.Layers.Version`:
- `current/0`, the type's current version;
- `step/2`, the pure migration of a document at one version to the next, `step(document, from)`, returning `{:ok, document}` at `from + 1`, or `{:error, faults}`. A step need not write the new stamp: the kernel does.

`Macaw.Layers.Version.check/2` reads a document's version before anything else of it:
- **A document with no stamp reads as current.**
- **A stamp above the type's current version is refused by name** as `{[], {:newer_schema, needs, this}}`, where *needs* is the stamp and *this* the type's current version. Nothing else of the document is read, and its other faults are not reported: the reader can't know what they mean.
- A stamp that is not a positive integer is `{["$version"], {:type, :pos_integer}}`.

`Macaw.Layers.Version.migrate/2` brings a document to the type's current version:
- a document at the current version, or with no stamp, is returned as it is, carrying the current stamp;
- **an older one is migrated step by step,** each `step/2` in turn from the stamp to current, purely: no I/O, no clock, no process. The result carries the current stamp;
- a step's faults stop the migration and are returned, ordered by path;
- a newer or malformed stamp is refused by `check/2` before any step runs.

```test:versions-unstamped
a document with no stamp checks as the type's current version, and migrates unchanged but for the current stamp
```

```test:versions-newer
a stamp above current is {[], {:newer_schema, needs, this}} alone, before any step runs and whatever else the document holds; a stamp of 0, -1, 1.0, "2" or nil is {["$version"], {:type, :pos_integer}}
```

```test:versions-steps
a document at version 1 of a type at version 3 runs step 1 then step 2, in order, each seeing the stamp it migrates from, and ends at version 3; one at the current version runs no step
```

```test:versions-lines
two types with their own lines migrate independently: a document of one is read against its own current version, never the other's
```

```test:versions-step-faults
a step's faults stop the migration: no later step runs, and the faults come back ordered by path
```

```test:versions-pure
over generated documents and versions, migrating gives the same result twice, and migrating a migrated document changes nothing
```

## 5. The gates {#kernel-gates}

**A document's one true form is its value: BEAM terms.** An encoding (the JSON form, or any other) is a representation, made and read by an **adapter at the edge**. A representation never decides a value's validity or which values it may hold: the type judges the value, and a value an adapter can't represent fails at that adapter, never where it was built (macaw#188).

**The type judges its value.** A document type implements the behavior `Macaw.Layers.Document`, whose one callback, `validate/1`, judges the type's **value**: the terms Elixir holds (atom keys where the type has a key, string names elsewhere, atoms, times, the type's own structs), at the current version. `Macaw.Layers.Document.check/2` (`check(value, type)`) is how any value is judged, built in Elixir or read from an encoding: `{:ok, value}`, or the type's faults, ordered by path. No encoding is written or read, and no limit applies: the limits bound what reading an encoding costs.

**An encoding from elsewhere is read through the gates,** in this order, by the JSON adapter (§6): `Macaw.Layers.Form.gates/3` (`gates(input, type, opts)`), whether the document came from a file, a database or an object store. A fetched document is untrusted input: the same gates apply, and nothing in it is evaluated. The type implements `Macaw.Layers.Version` (§4).

1. **Bytes.** An encoded document (a JSON binary) longer than the `bytes` limit is refused as `{[], {:limit, :bytes, max, given}}` before anything else is done with it.
2. **Decode with `depth` and `items` limits, by a scan that stops at a limit.** `Macaw.Layers.Scan` walks the encoded bytes, tracking strings and their escapes, the nesting, and the entries of each object and array. It builds no value: it holds one frame per open container and the current key of each open object, so its fault can name a path. **It stops at the first limit it passes** and reports that one. Only a document that passes the scan is decoded, with Elixir's `JSON`.
   - Malformed JSON is `{[], {:json, words}}`. The scan never fails on malformed input: what it can't make sense of, it leaves to the decoder.
   - A document whose root is not an object is `{[], {:type, :map}}`.
   - A decoded map form given directly skips the bytes gate and is walked for the same limits instead (`Macaw.Layers.Limits.structure/2`), every fault reported.
3. **Version** (§4): a newer stamp is refused by name before anything else of the document is read.
4. **Migrate** (§4), step by step, on the map form.
5. **Recount `depth` and `items`,** since a migration can grow a document, every fault reported.

Faults from one gate stop the gates after it: a document over a limit is not decoded, one that does not decode has no version to read, and one the recount refuses is not read further. `gates/3` returns `{:ok, map}`, the map form at the type's current version, its stamp included, or `{:error, faults}`.

**`Macaw.Layers.Form.read/3`** (`read(input, type, opts)`) reads the value a document from elsewhere holds: the gates, then the value from the map form by `from_map/2` (§6), the stamp dropped, then the value judged by `Document.check/2`. It returns `{:ok, value}`, or the faults of the first step that refuses: a gate's, the map form's (a tag, a key or an atom the type does not read), or the type's. The type implements `Version`, `Form` and `Document`.

**The limits** (`Macaw.Layers.Limits`) are the adapter's:

| Limit | Default | Bounds |
|---|---|---|
| `bytes` | `8_000_000` | the encoded document's size |
| `depth` | `64` | how deeply objects and arrays nest; the document itself is depth 1 |
| `items` | `100_000` | the entries any one object or array holds |

- **A host may tighten every limit,** by `limits:` in `gates/3`'s and `read/3`'s options; a limit it does not name keeps its default. A plain value above the default, one that is not a positive integer, or a name that is not a limit raises `ArgumentError` when the limits are built (`Limits.new/1`): a host can't loosen a sanity limit by mistake.
- **A host may raise a limit only by naming the raise,** per limit: `limits: [items: {:raise, 500_000}]`. The host knows its inputs are trusted and large (a bundle import of a whole library); Macaw knows only generic sanity values. A raise not above the default raises `ArgumentError`, so a raise always says what it is, and a document over the raised value is still refused with the same `{:limit, name, max, given}` fault.
- **Depth:** a container beyond the limit is reported once, at its own path, as `{path, {:limit, :depth, max, max + 1}}`, and nothing inside it is walked.
- **Items:** a container over the limit is reported at its own path as `{path, {:limit, :items, max, given}}`. The scan stops once a container holds one entry more than the limit, so its *given* is `max + 1`; the walk of a map form counts every entry. A key that appears twice in one object is counted twice by the scan, as the document holds it twice.

**Unknown keys are refused by name,** at their own key: a key the document type does not know is `{path ++ [key], :unknown_key}`. A key a reader keeps at its own spelling, a string (§6), is named as the document wrote it. `Macaw.Layers.Document.unknown_keys/3` gives these faults for a map and the type's known keys, for a type's `validate/1` to report.

```test:gates-bytes
a document one byte over a tightened bytes limit is refused as the bytes fault alone, and one at the limit passes; a map form skips the gate
```

```test:gates-scan-stops
a document nested a million deep, and one whose array holds a million entries, are refused at their first limit with bounded work: far fewer reductions than reading the document, and no value built
```

```test:gates-scan-paths
the scan's fault names the path of the container that passes the limit, through object keys (escapes read) and array indexes, and strings holding brackets, commas and escaped quotes are not structure
```

```test:gates-scan-agrees
over generated JSON values, the scan passes exactly those the walk of the decoded value passes, and when it refuses one, its fault is one the walk reports, at the same path and limit
```

```test:gates-json
malformed JSON is one {:json, words} fault at the root, never a crash, whatever the bytes; a root that is not an object is {[], {:type, :map}}
```

```test:gates-order
a newer stamp is refused before the type's validate/1 runs; a document over a limit is not version-checked; a migrated document the recount refuses is not read or judged; past the gates, the type's faults on the value are all reported, ordered by path
```

```test:gates-value-check
check/2 judges a value built in Elixir with no encoding and no limit: a value holding a tuple the type accepts is {:ok, value}, and Form.to_json/2 refuses it at that path as {:type, :term}; an invalid value has every fault of the type's, ordered by path
```

```test:gates-recount
a migration that grows a document past the depth or items limit is refused after migration, at the grown path
```

```test:gates-limits
Limits.new/1 tightens a named limit and keeps the rest at their defaults; a loosened limit, a non-positive or non-integer value, and an unknown name each raise ArgumentError
```

```test:gates-limits-raise
{:raise, max} raises a named limit above its default, so a document over the default and under the raise is read and one over the raise is the limit fault; a raise not above the default, or not an integer, raises ArgumentError
```

```test:gates-unknown-keys
unknown_keys/3 refuses each key not among the known ones at its own key under the given path, ordered, and refuses none of the known
```

## 6. Forms and tags {#kernel-forms}

**A document has one true form, its value, and two representations made from it by the JSON adapter.**
- The **value** is the document as Elixir holds it: atom keys where the type has a key, string names elsewhere, atoms, times, the type's own structs. The type judges it (§5).
- The **map form** is JSON-ready: string keys, and a tag for every value JSON can't express.
- The **JSON form** is the map form encoded, stamped with the type's version.

`Macaw.Layers.Form` is the JSON adapter:
- **The codec,** `to_map/2` and `from_map/2`, converts between the value and the map form, exact inverses with no gates and no validation: for a value with a form, `from_map(to_map(v)) == {:ok, v}`; for a map form `to_map/2` wrote, `to_map(from_map(m)) == {:ok, m}`. `encode_term/2` writes one term's map form, `{:ok, form}` or its faults by path, for a type writing a payload of its own tag whose keys are the tag's, not data (spec/02 §9).
- **Writing,** `to_json/2`: the value's map form, encoded, with the stamp `"$version"` set to the type's current version where the type has a version line (it exports `current/0`, found as §9 says) and no stamp where it has none. A value with no form is refused here, at its path, though `Document.check/2` holds it valid: the adapter's limits on what it can write are not the value's.
- **Reading,** `gates/3` and `read/3` (§5): a JSON document, or its decoded map form, through the gates to the map form at the current version, and from it to the value, judged. `read(to_json(v))` is `{:ok, v}` for a valid value with a form.

A document type implements the behavior `Macaw.Layers.Form`:
- `tags/0`, its tag table;
- `keys/0`, the keys it reads as atoms, and `atoms/0`, the atoms a `$atom` may spell, each a closed vocabulary (§2), so no atom is ever made from a document;
- optionally, `encode_value/1` and `decode_value/2`, for values of its own (a struct, a tuple), written under its own live tags.

**The kernel's terms:**

| Value | Map form |
|---|---|
| `nil`, a boolean, a number, a string | as it is |
| another atom | `{"$atom": "spelling"}`, read back through the type's `atoms/0`; a spelling it lacks is `{path, {:enum, allowed}}` |
| a `DateTime` in `Etc/UTC` | `{"$time": "ISO 8601"}`; a payload that is not one is `{path, {:type, :time}}` |
| a list | a list |
| a map | an object, keyed as below |

- **Keys are decoded against the type's tables.** A key the type's `keys/0` has becomes the atom; any other stays a string, at its own spelling, for the type's `validate/1` to refuse (§5). In the value, an atom key must be one of the type's keys (else `:unknown_key` when written), and a string key must not be spelled like one (`:key_spelling`), since it would read back as the key. A key that is neither an atom nor a string is `{:type, :name}`.
- **Values JSON can't express use one table of `$` tags.** A tag is a one-key object whose key starts with a single `$`. Each type declares its table with `use Macaw.Layers.Tags`, listing its live, retired and renamed tags; the kernel's `$atom`, `$time` and `$version` are live in every table. `Macaw.Layers.Tags` supplies:
  - `tag/2`, a macro in the table's module that refuses at compile time a literal tag the table does not list as live, so nothing is written that a reader would refuse;
  - `read/2`, which holds a parsed document to the table: a renamed tag is read under its new name, and an unknown or retired tag is refused at the path of its object, `{:unknown_tag, tag}` or `{:retired_tag, tag, why}`, never read as data;
  - **escaping:** a data key that starts with `$` is written with one more `$` and read back with one fewer, so data may hold any key, and `$$` never names a tag. The stamp `"$version"` at a document's root is not data and is not escaped.
- A live tag the type writes is read by its `decode_value/2`; one it doesn't read is `{path, {:unknown_tag, tag}}`.
- **A form holds no functions, and no document holds credentials or source configuration.** A function, a PID, a reference, a port, a tuple or a struct the type doesn't write has no form, and is refused at its path as `{:type, :term}` when written (`to_map/2`, `to_json/2`); whether a value may hold one is the type's `validate/1` to say. Credentials and source configuration are the host's; a document names sources and state by name only ([macaw_compose 01](https://github.com/dcoai/macaw/blob/main/spec/01-vocabulary.md#vocab-data)).

```test:forms-round-trip
over generated valid values (type keys, string names, atoms of the type, UTC times, nesting, $-keys), from_map(to_map(v)) is {:ok, v} and read(to_json(v)) reads it back, the stamp dropped; to_map(from_map(m)) is {:ok, m} for the map forms written
```

```test:forms-json-stamp
to_json/2 stamps the type's current version where the type has a version line and writes no stamp for a type without one; read/3 of the JSON form and of the map form give the value, gates/3 the stamped map form, and a newer stamp or a $atom the type lacks is refused before the value is judged
```

```test:forms-terms
each kernel term has the map form the table gives, an atom spelling outside atoms/0 is the enum fault, a $time that is not an ISO 8601 UTC time is the time fault, and no atom is made reading either
```

```test:forms-keys
a type key reads as its atom and any other key stays a string; writing an atom key the type lacks is :unknown_key, a string spelled like a type key is :key_spelling, and an integer key is {:type, :name}, each at its path
```

```test:forms-no-functions
a function, a PID, a reference, a tuple and a struct the type doesn't write are each {:type, :term} at their path, all reported
```

```test:forms-own-values
a type's own value is written by encode_value/1 under its live tag and read back by decode_value/2, and a live tag decode_value/2 doesn't read is :unknown_tag; encode_term/2 writes one term's map form for a payload of the type's own, or its faults by path
```

```test:tags-read
a renamed tag reads as its new name, an unknown and a retired tag are refused at their object's path with their words, all of them ordered by path, and a $$ key is data
```

```test:tags-escape
escape/1 and unescape/1 are inverses on every string key, a $ key gains one $, and the root stamp is written and read unescaped
```

```test:tags-compile
tag/2 with a literal tag the table lacks is a compile error naming the table, a computed one is checked when called, and a table listing a tag that doesn't start with a single $ fails to compile
```

## 7. The digest {#kernel-digest}

**`Macaw.Layers.Document.digest/1` fingerprints a value: the term itself, never a representation of it.** It takes any data term and returns 64 lowercase hex characters, the SHA-256 of the term's **canonical encoding**. A value has one digest however it was built and whatever form it is later written in. Its map form or JSON form is another term with a digest of its own, so identity never depends on a representation existing (macaw#188).

The canonical encoding is one version byte, `1`, then the term, every part tagged by its type and self-delimiting. Sizes are unsigned 64-bit and every number is big-endian:

| Term | Encoding |
|---|---|
| an atom (`nil`, `true` and `false` too) | `a`, its name's byte size, its name in UTF-8 |
| a binary | `b`, its byte size, its bytes |
| a bitstring of another size | `s`, its bit size, its bits padded with zeros to a whole byte |
| an integer, of any size | `i`, the byte size of its decimal spelling, that spelling (`-` for a negative) |
| a float | `f`, its IEEE 754 64-bit form |
| a list | `l`, its length, each element |
| a tuple | `t`, its size, each element |
| a map | `m`, its size, then each key's encoding followed by its value's, ordered by the keys' encodings bytewise |

- **Key order never matters,** and different terms have different encodings: `1` and `1.0`, `0.0` and `-0.0` (as under `===`), `:a` and `"a"`, `{:a}` and `[:a]`, a map holding `nil` and one lacking the key.
- **A struct is its map,** `__struct__` and all. So a `DateTime` carries its zone, offset and precision, two `DateTime`s at one instant in different zones differ, and a struct differs from its bare map.
- **A term that is not data raises `ArgumentError`,** naming it: a function, a PID, a reference, a port, an improper list.

Records, base renders and bundles cite a value by its digest. **The canonical encoding is part of the kernel's contract.** Changing it changes every digest, so it changes only with a new major version. Its version byte is what such a change would move.

```test:digest-order
over generated data terms (atoms, strings, integers beyond 64 bits, floats, dates, times, structs, lists, tuples, and maps with atom and string keys), the digest is unchanged by reordering keys at any depth, and is 64 lowercase hex characters
```

```test:digest-differs
over generated pairs of different terms, the digests differ; 1 and 1.0, 0.0 and -0.0, :a and "a", {:a} and [:a], a held nil and a missing key, a bitstring and its padded binary, a struct and its map, and two DateTimes differing only in precision or zone each differ
```

```test:digest-golden
fixed values' digests are the recorded ones, computed independently from this section's table, so any change to the encoding fails the test
```

```test:digest-not-data
a function, a PID, a reference, an improper list and a map holding a PID each raise ArgumentError
```

## 8. Untrusted strings {#kernel-untrusted}

<!-- surfex: deferred #100: untrusted strings and the URL policy are a proposal of their own -->

**Untrusted strings are sanitized where they are read and escaped where they are written,** and **URLs are checked by a host policy** before a document may use one. Which strings and URLs a document holds is the document type's to say; the kernel supplies the checks so every type applies them the same way.

## 9. Optional callbacks {#kernel-callbacks}

**An optional callback is found whether or not its module is loaded.** A behavior's optional callbacks (a type's `encode_value/1`, `decode_value/2`, `identity/2`, `inline/2`, `current/0` and the rest) are asked for through `Macaw.Layers.Callback.exported?/3`, which loads the module before it answers. `function_exported?/3` alone answers `false` for a module the VM hasn't loaded yet, and modules load lazily in dev, test and `iex`: a bare check would take, silently, the path of a type that lacks the callback, depending on what ran first. A module that can't be loaded raises: a type that doesn't exist is a mistake, not a type without the callback.

CI refuses a bare `function_exported?/3` anywhere in `lib/` but `Macaw.Layers.Callback` (`ci/callbacks.exs`).

```test:callbacks-unloaded
with the type module unloaded first, exported?/3 finds its callback, encode_term/2 writes the type's own value, from_map/2 reads it back, and the cascade replaces an element by its identity; a module that doesn't exist raises
```
