# 03 — Stores and references {#stores}

Documents live in **stores**: the host's database, files in git, or an object store (exio). Macaw reaches them through one behavior (visualize.md C8; metresis.md C8). This file is visualize's store and bundle (spec/14 §18.3, §19.2, §19.7, §19.8; spec/15 §11; D-99, D-100, D-103, D-137, D-147, D-217, D-219) without the builder and without boards, its callbacks answering as every Macaw contract does, `{:ok, …}` or `{:error, …}` (macaw_compose#94).


| Module | What it is |
|---|---|
| `Macaw.Layers.Store` | the store behavior, the assign's form, ids encoded and decoded, and import as a relocation through a store's own `put/2` (§1, §2, §3.3) |
| `Macaw.Layers.Store.Memory` | the default store, held in memory (§1.2) |
| `Macaw.Layers.Bundle` | a portable set of documents: the closure, provenance, the forms, import (§3) |

## 1. The store behavior {#stores-behavior}

```elixir
@callback types(context)           :: [module]
@callback list(context)            :: {:ok, [summary]} | {:error, reason}
@callback get(ref, context)        :: {:ok, entry} | {:error, :not_found | reason}   # ref = {kind, n}
@callback put(entry, context)      :: {:ok, id} | {:error, reason}
@callback delete(ref, context)     :: :ok | {:error, reason}
@callback import(bundle, context)  :: {:ok, %{ids: %{old_id => new_id}, outside: [{id, path}]}} | {:error, [fault]}
```

- **The types** are the fragment types the store holds (spec/02 §1), given explicitly when the store is configured: default closed, a type not listed is not storable. **Kinds are unique across them**, so an id's kind names one type: two types declaring one kind raise `ArgumentError` naming both when the store is configured (`Store.check_types!/1`). `Store.kinds/1` is every kind of the store's types; `Store.type_of/2` the type a kind belongs to.
- **An entry** is `%{id: {kind, n} | nil, name: String.t(), fragment: map}`: the fragment, its id, and its **name**, an attribute (§2). Its **kind is derived** from the fragment (spec/02 §6.1) by the first of the store's types that derives one, never stored, so an entry cannot claim a kind its body is not: a fragment that derives to no kind is refused by `put/2` as `{:error, :no_kind}`, and one put under a held id of another kind as `{:error, {:kind, id_kind, derived}}`.
- **A summary** is `%{id, name, kind}`, what a picker lists. The name may carry the person's own filing as `<group>:<sub-group>:<name>`, read by `Store.group/1`; nothing references it.
- **`put/2`** issues an id to an entry without one and answers it, and replaces the entry of an id it holds; an id it does not hold is `{:error, :not_found}`, since only the store issues ids. **`delete/2`** removes an entry, and deleting an id it does not hold is `:ok`: the entry is gone either way. A later reference to a deleted id is a mask (§2). **`import/2`** relocates a bundle (§3.3), committed whole or not at all.
- **The context** says who is acting and from where, so entries are traceable: a store assign is `{module, context}`, and a bare module is `{module, nil}` (`Store.split/1`). A library entry nobody can trace is an entry nobody trusts, and the process dictionary is not a signature (visualize#148).
- **Nothing in the behavior validates** beyond deriving a kind: a fragment is a fragment (spec/02 §1), and a stored map a document cannot use fails where every bad fragment fails, at the reader, by path.

| Function | Contract |
|---|---|
| `Store.split(assign)` | `{module, context}`; a bare module has a `nil` context |
| `Store.types(assign)`, `list(assign)`, `get(assign, ref)`, `put(assign, entry)`, `delete(assign, ref)`, `import(assign, bundle)` | the callback of the assign's module with its context |
| `Store.check_types!(types)` | the types, or `ArgumentError` naming two that declare one kind |
| `Store.kinds(assign)` | every kind of the store's types, sorted |
| `Store.type_of(assign, kind)` | the type a kind belongs to, or `nil` |
| `Store.kind(assign, fragment)` | `{type, kind}` of the first of the store's types that derives the fragment a kind, or `nil` |
| `Store.group(name)` | a name's filing as `{[group, sub-group], name}`: the segments before the last `:`, empty ones dropped, and the last |

`kinds/1`, `type_of/2` and `kind/2` also take the list of types itself, so a store can answer them from its own state without calling itself.

```test:stores-behavior-calls
the store functions call the assign's module with its context, a bare module with nil; put issues an id to a new entry and replaces a held one; get of an unknown id is not found; delete makes a later get not found; a fragment of no kind is refused
```

### 1.2 The memory store {#stores-memory}

`Macaw.Layers.Store.Memory` is the default store (macaw_compose spec/00 goal 3): an `Agent` the host starts under its own supervisor, `Memory.start_link(types: [type, …], check: fun, name: name)`, its context the agent (or its name), its types the list it was started with, `check:` the host's check over each imported entry (§3.3). Ids are issued from **one sequence per kind that never repeats**, a deleted id never reissued, so a stale id cannot resolve to something new and ids sort by creation. `list/1` answers the summaries ordered by id. Its `import/2` is `Store.relocate/3` (§3.3) with its `check:` and a transaction that runs the writes over a copy of its state and swaps the copy in only when every write succeeded.

```test:stores-memory-sequences
the memory store issues ids per kind from one, never reusing a deleted id, and lists summaries by id with their kinds; it is a child a supervisor starts, by name, holding the types it was given
```

## 2. References {#stores-references}

- **References are typed ids:** `{kind, n}`, the kind a fragment kind of the document's type (spec/02 §6.2) and `n` a positive integer the store issued. A reference of the wrong kind is refused **before resolution**: a type's reader holds a site that takes a `kind` to an id of that kind, `{:ref_kind, wanted, given}` at the site's path, the cheapest moment to find it. `Store.ref_kind(id, wanted)` is that check, `:ok` or `{:error, {:ref_kind, wanted, given}}`, for the reader to place at its path.
- **An id is tagged with its kind** so it is readable in the raw data and in an export (`{"$id": ["style", 11]}`), and **encodes as one string** for the DOM and the wire: `Store.encode_id({:style, 11})` is `"style:11"`, and `Store.decode_id(kinds, "style:11")` is `{:ok, {:style, 11}}` or `:error`, matching the kind against the type's `kinds/0` by its string, so **no atom is made from a client's string**.
- **Names are attributes, never identities:** a route path, a slug, a title. Collpa's route path becomes an attribute of a page id. Renaming an entry changes nothing that references it.
- **Versions are digests** (spec/01 §7), or the store's own object versions.
- **A missing reference is a validation fault** when a document is loaded, at its path (macaw_compose spec/07 §2). If an entry disappears **after** validation — deleted while pages run — the site that referenced it is **masked** and reported: lower layers show through, or the site's default applies, and rendering never fails because of it (spec/02 §7, visualize D-100).

```test:stores-ids-encoded
an id encodes as kind colon n and decodes against the type's kinds by spelling, refusing an unknown kind, a non-positive number and a malformed string without making an atom; a reference of the wrong kind is refused before it is resolved
```

## 3. Portability: bundles and state snapshots {#stores-portable}

Goal 9: save configuration, and state where possible, and restore it on another machine, right where you were.

### 3.1 The bundle {#stores-bundle}

**A bundle** is the transitive closure of the documents a page (or a set of pages) needs: pages, surfaces, component settings and presets, templates, layers, themes and styles. `%Macaw.Layers.Bundle{provenance, entries, snapshot}`:

- **`provenance`** — `store`, the host's name for the source store, a string or an atom (read back as its string); `exported_at`, a UTC time; `version`, the bundle's version line's current version when it was exported (spec/01 §4), a record that the stamp, not it, gates;
- **`entries`** — `%{id, name, fragment}` in **dependency order**, each with its original id, its kind derived from its fragment as a store derives it;
- **`snapshot`** — a state snapshot in its own map form, which the bundle carries as it is, or `nil` (macaw_compose spec/03 §4).

`Bundle.export(store, ids, source)` takes the closure, `source` written as the provenance's `store`: every id `Fragment.refs/2` finds in each entry, through the entry's type, followed through the store, dependencies first, each once. A reference to an id the store no longer holds is skipped, so the bundle carries what exists. **Re-importing the same collection is detectable** from the provenance and the original ids, rather than minting a second copy silently.

**What never travels:**
- **credentials and source configuration:** the importing host maps source names to its own configured sources;
- **data:** sources re-read;
- **identity:** the host's records stay with the host.

A bundle carries definitions and the bindings inside them, never a host's binding of a slot to its data.

```test:stores-bundle-closure
export follows every reference transitively, use sites included, dependencies first and each once, skipping an id the store no longer holds, with provenance of store, time and version
```

### 3.2 The term and its forms {#stores-bundle-forms}

**A bundle is a term,** `%Macaw.Layers.Bundle{}`, judged as one however it was made (spec/01 §5). Its map form and JSON form (visualize#818, D-217) are representations made at the edge, so it can leave the node it was made on:

```json
{"$version": 1,
 "provenance": {"store": "metresis", "exported_at": "2026-10-20T09:30:00.000000Z", "version": 1},
 "entries": [
   {"id": "style:11", "name": "Styles::thick", "fragment": {"style": {"stroke": {"width": 3}}}},
   {"id": "panel:2", "name": "Panels:wide", "fragment": {"$version": 2, "panel": {"columns": 2}}}],
 "snapshot": null}
```

- **`Bundle.check(bundle, types)` judges the term,** `types` given as a store's, with no form written or read: `{:ok, bundle}`, or every fault, ordered by path. It is `Document.check/2` of the envelope, `Macaw.Layers.Bundle` being the bundle's own `Document`, whose `validate/1` judges a `%Bundle{}`, and each entry's kind against its type. This is how a bundle built in Elixir is judged, and the last step of reading one. **The faults of the term:**
  - `provenance` missing (`nil`), and a key missing from it or from an entry, is `:required`; a key neither has is `:unknown_key`;
  - `provenance` and each entry that is not a map, `entries` that is not a list, a `fragment` or `snapshot` (other than `nil`) that is not a map, are `{:type, :map}` or `{:type, :list}`;
  - a `store` that is neither a string nor an atom other than `nil`, `true` and `false` is `{:type, :string}`; an `exported_at` that is not a `DateTime` in `Etc/UTC` is `{:type, :utc_datetime}`; a `version` that is not a positive integer `{:type, :pos_integer}`; a `name` that is not a string `{:type, :string}`;
  - an `id` that is not `{kind, n}`, an atom and a positive integer, or whose kind none of `types` has, is `{:type, :id}`;
  - an id carried twice is `{:duplicate, id}` at the later entry's `[:entries, i, :id]`;
  - a fragment that derives to no kind is `:no_kind` at `[:entries, i, :fragment]`, and one that derives to another kind than its id's `{:kind, id_kind, derived}`.
- **A fragment is not validated as a whole document,** since a fragment may be partial.
- **Each part's form is the form its own document has:** an entry's `id` as `Store.encode_id/1` writes it, its `fragment` in the type's map form (spec/02 §9), **stamped with the type's version where the type has a version line**, so it migrates on reading as a document of its type does, and `snapshot` in its own map form. `exported_at` is ISO 8601 in UTC. A `provenance.store` is its name's string.
- **`Bundle.to_map(bundle, types)` and `to_json(bundle, types)`** answer `{:ok, form}`, or every value without a form by path: a store that is no name `{:type, :string}` at `[:provenance, :store]`, an entry's fragment under `[:entries, i, :fragment]`, and an id of a kind none of `types` has as `{:type, :id}` at `[:entries, i, :id]`. A value the term holds validly but no form can write (a tuple in a fragment, say) fails here, at its path, and nowhere else.
- **`Bundle.from_map(map, types, opts)` and `from_json(json, types, opts)` read a form,** in order:
  1. **the JSON adapter's gates** (spec/01 §5, `Form.gates/3` with its `limits:`), with the bundle's own version line, `Macaw.Layers.Bundle` being its `Version`: the bytes and the scan, the stamp (`{[], {:newer_schema, needs, this}}`, nothing else read), the migration, the recount. A value that is not a map is `{[], {:type, :map}}`;
  2. **the envelope's decode of the map form,** reporting what only a map form can be wrong in, all at once: a key the bundle does not have (`:unknown_key`, at its spelling); `provenance`, `entries`, each part of the provenance and each entry's `id`, `name` and `fragment` missing (`:required`); `provenance` or an entry that is not an object, `entries` that is not an array (`{:type, :map}`, `{:type, :list}`); a `store` that is not a string (`{:type, :string}`); an `exported_at` that is not an ISO 8601 time in UTC (`{:type, :utc_datetime}`); an `id` that is not a string (`{:type, :id}`);
  3. **each entry read by its type,** only once the envelope decodes: its `id` against the kinds of `types`, so no atom is made from a document's kind (an id of no kind is `{:type, :id}`), and its fragment, when a map, through the type its kind names, migrated by the type's own line (a newer stamp is `{:newer_schema, needs, this}` at `[:entries, i, :fragment]`) and read by `Form.from_map/2`, its faults under `[:entries, i, :fragment]`; every entry's faults are reported together;
  4. **the term's check,** `check/2`, of the `%Bundle{}` the form gave.

  The faults of the first step that refuses are returned; a later step does not run.

`from_map(to_map(b))` is `{:ok, b}` for a bundle `check/2` holds valid, and `from_json(to_json(b))` is `{:ok, b}` with a store named by an atom read as its string.

```test:stores-bundle-round-trip
a bundle round-trips through its map and JSON forms, a fragment stamped with its type's version and migrated on reading; a newer stamp is refused before any key is read, the limits apply, the map form's faults (unknown keys, required parts, a bad time, a store or id that is no string, an id of no kind, a fragment that does not read) come at their paths before the term's (a duplicate id, a fragment of the wrong kind or none, parts of the wrong type), and a value with no form is refused when written
```

```test:stores-bundle-check
check/2 holds a bundle built in Elixir valid with no form written or read, a fragment value no form can write included, which to_json/2 then refuses at its path; every fault of the term is at its path: required and unknown keys, a store, time, version, name, id, fragment or snapshot of the wrong type, an id of no kind, a duplicate, a fragment of no kind or another kind
```

### 3.3 Import is a relocation {#stores-import}

Import has every property that ruled out renaming by name: it is bounded to a known set, it happens once at the boundary between stores rather than during editing, and it is one call with one outcome. `Store.relocate(assign, bundle, opts)` is the import every store may use as its own, each entry read through the store's type of its kind:

1. **Every check runs before anything is written:**
   - the bundle term is checked (`Bundle.check/2`, §3.2): its envelope, and each entry's kind against the store's type of it. No form is written or read back, so a bundle judges the same whether it was built in memory or read from a file, and a bundle a host read under a raised limit (`limits: [items: {:raise, n}]`) is not read again under the defaults;
   - the host's `check:` over each entry, `(entry -> :ok | {:error, faults})`, such as every name a fragment uses that the host's registry does not know (macaw_compose spec/12 §1): the registry is the host's, and this library holds none.
2. **New ids are issued** — each entry put without its id — and one table `old → new` is built.
3. **References are rewritten through that table** (`Fragment.relocate/3`) and each entry is put again under its new id.
4. **It commits whole or not at all,** and every fault is reported, each at `[:entries, i | path]`; a write's refusal is its reason at `[:entries, i]`. A store whose writes can fail midway gives `transaction:`, a function handed `run`: it calls `run.(state, put)` inside its own transaction, `put.(entry, state)` answering `{:ok, id, state}` or `{:error, reason}`, and commits only when `run` answers `{:ok, imported, state}`. The memory store runs its writes over a copy of its state and swaps the copy in. Without `transaction:` the entries are written through the store's `put/2`, which is whole only where those writes cannot fail once the checks pass.

A reference to an id **outside** the bundle — only possible in a hand-edited file — imports as a mask and is **reported** in `outside`, `{id, [:entries, i]}` by the entry that holds it, never a failure and never silent.

```test:stores-import-relocation
import checks every entry before writing, issues new ids, rewrites every reference through one table, commits whole or reports every fault with nothing written, and reports references outside the bundle as masks
```

```test:stores-import-term
import checks the bundle term without writing or reading its form: a bundle read from JSON under a raised items limit, over the default, relocates whole
```

## 4. Ids on object storage {#stores-object}

<!-- surfex: deferred #4: open research, settled before an exio-backed store is built -->

Open (macaw_compose#4). visualize's per-type sequences, which are never reused, are awkward on S3. The options are:
- ids derived from object keys;
- a manifest object that issues ids by conditional write;
- content-addressed ids for immutable fragments.

This is deferred until an exio-backed store is built.
