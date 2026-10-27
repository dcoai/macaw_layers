# 01 — The document kernel {#documents-kernel}

<!-- surfex: class orientation -->

Every declarative value Macaw reads is a **document**: pages, surfaces, templates, layers, themes, visualize designs, component settings and records ([macaw_compose 01](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/01-vocabulary.md#vocab-documents)). One kernel reads them all. It knows nothing of any document type: each type brings its own keys, schema, migration steps, tags and wording, and the kernel supplies everything they share.

The kernel generalizes what visualize built for its designs, fragments, boards, snapshots and bundles. That code is spread over `Visualize.Chart.Migration`, `Chart.Limits`, `Chart.Codec.Tags`, `Chart.Codec`, `Chart.Validator`, `Chart.Names` and `Visualize.Vocabulary`. What is generic in it moves here; what is chart-specific stays in visualize as an implementer of the kernel's behaviors ([macaw_compose 00 §5](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/00-overview.md#overview-order), step 2).

| Module | What it is | § |
|---|---|---|
| `Macaw.Layers.Names` | names a document declares: strings, never atoms made from data | 1 |
| `Macaw.Layers.Vocabulary` | closed vocabularies looked up by spelling | 2 |
| `Macaw.Layers.Fault` | the fault `{path, reason}`, its order, and the one formatter | 3 |
| `Macaw.Layers.Version` | one version line per document type, and stepwise migration | 4 |
| `Macaw.Layers.Document`, `Macaw.Layers.Limits`, `Macaw.Layers.Scan` | the gates, in order | 5 |
| `Macaw.Layers.Tags`, `Macaw.Layers.Form` | the map and JSON forms, and the `$` tag table | 6 |
| `Macaw.Layers.Document.digest/1` | a canonical digest | 7 |

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
reading 2 000 fresh strings through fetch/2 and read/2 leaves the node's atom count unchanged, and read/2 returns each string as it was
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
| `{:type, type}` | must be *type*, for the types below; any other type is the document type's to word |
| `{:enum, allowed}` | must be one of *allowed*, each shown with `inspect/1`, joined by `, ` |
| `{:newer_schema, needs, this}` | needs schema v*needs*, this is v*this* |
| `{:limit, name, max, given}` | for `:bytes`, is *given* bytes; the limit bytes is *max*; for `:depth`, is nested *given* deep; the limit depth is *max*; for `:items`, holds *given* items; the limit items is *max* |
| `{:json, message}` | JSON does not parse: *message* |
| `{:unknown_tag, tag}` | *tag* is not a tag this document reads |
| `{:retired_tag, tag, why}` | *tag* *why* |

The types the kernel words in `{:type, type}`: `:string` (a string), `:name` (a name: a non-empty string), `:integer` (an integer), `:non_neg_integer` (a non-negative integer), `:pos_integer` (a positive integer), `:number` (a number), `:positive` (a positive number), `:boolean` (true or false), `:map` (a map), `:list` (a list), `{:enum, allowed}` (one of *allowed*), `{:list, t}` (a list of *t*), `{:map, t}` (a map from names to *t*), `{:node, kind}` (a *kind* node), and `{:one_of, types}` (each type's words joined by ` or `). A compound type whose part the kernel does not word is the document type's to word whole.

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

<!-- surfex: deferred #96: the version line and migration are built in their own work item -->

**Each document type has its own version line,** a positive integer that starts at 1 and rises by one with each change that needs a migration. A document carries its version as the stamp `"$version"`, at the top of its map or JSON form. Two types' lines are independent: a new step for one moves no other.

A document type implements the behavior `Macaw.Layers.Version`:
- `current/0`, the type's current version;
- `step/2`, the pure migration of a document at one version to the next, `step(document, from)`, returning the document at `from + 1`. It may report faults, as `{:error, faults}`.

The kernel reads a document's version before anything else of it:
- **A document with no stamp reads as current.**
- **A stamp above the type's current version is refused by name** as `{[], {:newer_schema, needs, this}}`, where *needs* is the stamp and *this* the reader's current version, before any other part of the value is read. A newer document's other faults are not reported: the reader can't know what they mean.
- A stamp that is not a positive integer is `{["$version"], {:type, :pos_integer}}`.
- **A stamp below current is migrated step by step,** each `step/2` in turn from the stamp to current, purely: no I/O, no clock, no process. The result carries the current stamp.

## 5. The gates {#kernel-gates}

<!-- surfex: deferred #97: the gates are built in their own work item -->

**Every document is read through the same gates, in this order,** by `Macaw.Layers.Document.read/3` (`read(input, type, opts)`), whether it came from a file, a database or an object store. A fetched document is untrusted input: the same gates apply, and nothing in it is evaluated.

1. **Bytes.** An encoded document (a JSON binary) longer than the `bytes` limit is refused as `{[], {:limit, :bytes, max, given}}` before anything else is done with it.
2. **Decode with `depth` and `items` limits,** by a scan that stops at a limit. `Macaw.Layers.Scan` walks the encoded bytes, tracking strings and their escapes, nesting and the elements of each object and array, and stops at the first limit it passes: it builds no value. Only a document that passes the scan is decoded, with Elixir's `JSON`. Malformed JSON is `{[], {:json, message}}`. A map given directly (the map form) is walked for the same limits instead.
3. **Version** (§4): a newer stamp is refused by name before anything else of the value is read.
4. **Migrate** (§4), step by step.
5. **Validate**, by the document type, and **count `depth` and `items` again**, since a migration can grow a document.

Faults from one gate stop the gates after it: a document over a limit is not decoded, and one that does not decode has no version to read. Within a gate, every fault is reported, ordered by path (§3).

**The limits** (`Macaw.Layers.Limits`):

| Limit | Default | Bounds |
|---|---|---|
| `bytes` | `8_000_000` | the encoded document's size |
| `depth` | `64` | how deeply objects and arrays nest; the document itself is depth 1 |
| `items` | `100_000` | the entries any one object or array holds |

- **A host may tighten every limit,** by `limits:` in `read/3`'s options; a limit it does not name keeps its default. A value above the default, or one that is not a positive integer, or a name that is not a limit, raises `ArgumentError` when the limits are built: a host can't loosen a sanity limit by mistake.
- Past the depth limit, a branch is reported once, at the first object or array beyond it, as `{path, {:limit, :depth, max, given}}`, and not walked further. An object or array over the items limit is reported at its own path as `{path, {:limit, :items, max, given}}`.

**Unknown keys are refused by name,** at their own spelling: a key the document type does not know is `{path ++ [key], :unknown_key}`, with *key* the string the document wrote.

## 6. Forms and tags {#kernel-forms}

<!-- surfex: deferred #98: the forms and the tag table are built in their own work item -->

**A document has two forms: a map form and a JSON form, exact inverses for valid values.** `from_json(to_json(v)) == v`, and `to_map(from_map(m)) == m`. A document type implements the behavior `Macaw.Layers.Form`, which turns its value into the JSON-ready map and back. The kernel supplies the walk, the key tables and the tags.

- **Keys are decoded against the type's tables.** A key the table has becomes the type's key; a key it lacks stays a string at its own spelling, for the validator to refuse (§5). No atom is made from a key.
- **Values JSON can't express use one table of `$` tags.** A tag is a one-key object whose key starts with a single `$`, such as `{"$atom": "ok"}`. The table belongs to the document type; `Macaw.Layers.Tags` supplies:
  - `tag/2`, a macro that refuses at compile time a literal tag the table does not list as live, so nothing is written that a reader would refuse;
  - `read/2`, which holds a parsed document to the table: a renamed tag is read under its new name, and an unknown or retired tag is refused at the path of its object, `{:unknown_tag, tag}` or `{:retired_tag, tag, why}`, never read as data;
  - **escaping:** a data key that starts with `$` is written with one more `$` and read back with one fewer, so data may hold any key.
- **Documents hold no functions, credentials or source configuration.** A function, a PID, a reference or a port has no form and is refused at its path by `{:type, :term}`. Credentials and source configuration are the host's; a document names sources and state by name only ([macaw_compose 01](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/01-vocabulary.md#vocab-data)).

## 7. The digest {#kernel-digest}

<!-- surfex: deferred #99: the digest is built in its own work item -->

**`Macaw.Layers.Document.digest/1` fingerprints a document independently of key order.** It is the SHA-256 of a canonical encoding of the document's JSON form: objects with their keys sorted, numbers and strings in one fixed spelling, no insignificant whitespace. The digest is 64 lowercase hex characters. Records, base renders and bundles cite a document by it.

- Reordering keys, at any depth, does not change the digest.
- A document and its JSON round trip have the same digest.
- Two documents that differ in any value have different digests.
- The canonical encoding is part of the kernel's contract: changing it changes every digest, so it changes only with a new major version.

## 8. Untrusted strings {#kernel-untrusted}

<!-- surfex: deferred #100: untrusted strings and the URL policy are a proposal of their own -->

**Untrusted strings are sanitized where they are read and escaped where they are written,** and **URLs are checked by a host policy** before a document may use one. Which strings and URLs a document holds is the document type's to say; the kernel supplies the checks so every type applies them the same way.
