# 03 — Stores and references {#stores}

<!-- surfex: deferred #131: the store behavior, the memory store and typed references -->

Documents live in **stores**: the host's database, files in git, or an object store (exio). Macaw reaches them through one behavior (visualize.md C8; metresis.md C8). This file is visualize's store and bundle (spec/14 §18.3, §19.2, §19.7, §19.8; spec/15 §11; D-99, D-100, D-103, D-137, D-147, D-217, D-219) without the builder and without boards, its callbacks answering as every Macaw contract does, `{:ok, …}` or `{:error, …}` (macaw_compose#94).

Each section's tests are written as **`planned-test:` blocks** until its work item is built (macaw_compose#131, #132).

| Module | What it is |
|---|---|
| `Macaw.Layers.Store` | the store behavior, the assign's form, ids encoded and decoded, and import as a relocation through a store's own `put/2` (§1, §2, §3.3) |
| `Macaw.Layers.Store.Memory` | the default store, held in memory (§1.2) |
| `Macaw.Layers.Bundle` | a portable set of documents: the closure, provenance, the forms, import (§3) |

## 1. The store behavior {#stores-behavior}

<!-- surfex: deferred #131: the store behavior, the memory store and typed references -->

```elixir
@callback types(context)           :: [module]
@callback list(context)            :: {:ok, [summary]} | {:error, reason}
@callback get(ref, context)        :: {:ok, entry} | {:error, :not_found | reason}   # ref = {kind, n}
@callback put(entry, context)      :: {:ok, id} | {:error, reason}
@callback delete(ref, context)     :: :ok | {:error, reason}
@callback import(bundle, context)  :: {:ok, %{ids: %{old_id => new_id}, outside: [{id, path}]}} | {:error, [fault]}
```

- **The types** are the fragment types the store holds (spec/02 §1), given explicitly when the store is configured: default closed, a type not listed is not storable. **Kinds are unique across them**, so an id's kind names one type: two types declaring one kind raise `ArgumentError` naming both when the store is configured. `Store.kinds/1` is every kind of the store's types; `Store.type_of/2` the type a kind belongs to.
- **An entry** is `%{id: {kind, n} | nil, name: String.t(), fragment: map}`: the fragment, its id, and its **name**, an attribute (§2). Its **kind is derived** from the fragment (spec/02 §6.1) by the first of the store's types that derives one, never stored, so an entry cannot claim a kind its body is not; a fragment that derives to no kind is refused by `put/2` as `{:error, :no_kind}`.
- **A summary** is `%{id, name, kind}`, what a picker lists. The name may carry the person's own filing as `<group>:<sub-group>:<name>`, read by `Store.group/1`; nothing references it.
- **`put/2`** issues an id to an entry without one and answers it, and replaces the entry of an id it holds. **`delete/2`** removes an entry; a later reference to its id is a mask (§2). **`import/2`** relocates a bundle (§3.3), committed whole or not at all.
- **The context** says who is acting and from where, so entries are traceable: a store assign is `{module, context}`, and a bare module is `{module, nil}` (`Store.split/1`). A library entry nobody can trace is an entry nobody trusts, and the process dictionary is not a signature (visualize#148).
- **Nothing in the behavior validates** beyond deriving a kind: a fragment is a fragment (spec/02 §1), and a stored map a document cannot use fails where every bad fragment fails, at the reader, by path.

| Function | Contract |
|---|---|
| `Store.split(assign)` | `{module, context}`; a bare module has a `nil` context |
| `Store.types(assign)`, `list(assign)`, `get(assign, ref)`, `put(assign, entry)`, `delete(assign, ref)`, `import(assign, bundle)` | the callback of the assign's module with its context |
| `Store.kinds(assign)` | every kind of the store's types, sorted |
| `Store.kind(assign, fragment)` | `{type, kind}` of the first of the store's types that derives the fragment a kind, or `nil` |
| `Store.group(name)` | a name's filing as `{[group, sub-group], name}`, the last `:` segment the name |

```planned-test:stores-behavior-calls
the store functions call the assign's module with its context, a bare module with nil; put issues an id to a new entry and replaces a held one; get of an unknown id is not found; delete makes a later get not found; a fragment of no kind is refused
```

### 1.2 The memory store {#stores-memory}

<!-- surfex: deferred #131: the store behavior, the memory store and typed references -->

`Macaw.Layers.Store.Memory` is the default store (macaw_compose spec/00 goal 3): an `Agent` the host starts under its own supervisor, `Memory.start_link(types: [type, …])`, its context the agent, its types the list it was started with. Ids are issued from **one sequence per kind that never repeats**, a deleted id never reissued, so a stale id cannot resolve to something new and ids sort by creation. `list/1` answers the summaries ordered by id. Its `import/2` is `Store.relocate/3` (§3.3).

```planned-test:stores-memory-sequences
the memory store issues ids per kind from one, never reusing a deleted id, lists summaries by id, and imports through relocate
```

## 2. References {#stores-references}

<!-- surfex: deferred #131: the store behavior, the memory store and typed references -->

- **References are typed ids:** `{kind, n}`, the kind a fragment kind of the document's type (spec/02 §6.2) and `n` a positive integer the store issued. A reference of the wrong kind is refused **before resolution**: a type's reader holds a site that takes a `kind` to an id of that kind, `{:ref_kind, wanted, given}` at the site's path, the cheapest moment to find it.
- **An id is tagged with its kind** so it is readable in the raw data and in an export (`{"$id": ["style", 11]}`), and **encodes as one string** for the DOM and the wire: `Store.encode_id({:style, 11})` is `"style:11"`, and `Store.decode_id(kinds, "style:11")` is `{:ok, {:style, 11}}` or `:error`, matching the kind against the type's `kinds/0` by its string, so **no atom is made from a client's string**.
- **Names are attributes, never identities:** a route path, a slug, a title. macaw_server's route path becomes an attribute of a page id. Renaming an entry changes nothing that references it.
- **Versions are digests** (spec/01 §7), or the store's own object versions.
- **A missing reference is a validation fault** when a document is loaded, at its path (macaw_compose spec/07 §2). If an entry disappears **after** validation — deleted while pages run — the site that referenced it is **masked** and reported: lower layers show through, or the site's default applies, and rendering never fails because of it (spec/02 §7, visualize D-100).

```planned-test:stores-ids-encoded
an id encodes as kind colon n and decodes against the type's kinds by spelling, refusing an unknown kind, a non-positive number and a malformed string without making an atom; a reference of the wrong kind is refused before it is resolved
```

## 3. Portability: bundles and state snapshots {#stores-portable}

<!-- surfex: deferred #132: bundles, the closure, the forms and import as a relocation -->

Goal 9: save configuration, and state where possible, and restore it on another machine, right where you were.

### 3.1 The bundle {#stores-bundle}

<!-- surfex: deferred #132: bundles, the closure, the forms and import as a relocation -->

**A bundle** is the transitive closure of the documents a page (or a set of pages) needs: pages, surfaces, component settings and presets, templates, layers, themes and styles. `%Macaw.Layers.Bundle{provenance, entries, snapshot}`:

- **`provenance`** — `store`, the source store's identity (a string, or a term the kernel's tag table writes); `exported_at`, a UTC time; `version`, the version line's current version the bundle was exported at (spec/01 §4);
- **`entries`** — `%{id, name, fragment}` in **dependency order**, each with its original id, its kind derived from its fragment as a store derives it;
- **`snapshot`** — a state snapshot, or `nil` (macaw_compose spec/03 §4).

`Bundle.export(store, ids)` takes the closure: every id `Fragment.refs/2` finds in each entry, through the entry's type, followed through the store, dependencies first, each once. A reference to an id the store no longer holds is skipped, so the bundle carries what exists. **Re-importing the same collection is detectable** from the provenance and the original ids, rather than minting a second copy silently.

**What never travels:**
- **credentials and source configuration:** the importing host maps source names to its own configured sources;
- **data:** sources re-read;
- **identity:** the host's records stay with the host.

A bundle carries definitions and the bindings inside them, never a host's binding of a slot to its data.

```planned-test:stores-bundle-closure
export follows every reference transitively, use sites included, dependencies first and each once, skipping an id the store no longer holds, with provenance of store, time and version
```

### 3.2 The forms {#stores-bundle-forms}

<!-- surfex: deferred #132: bundles, the closure, the forms and import as a relocation -->

A bundle has a map form and a JSON form (visualize#818, D-217), so it can leave the node it was made on:

```json
{"$version": 1,
 "provenance": {"store": "metresis", "exported_at": "2026-10-20T09:30:00.000000Z", "version": 1},
 "entries": [{"id": "style:11", "name": "Styles::thick", "fragment": {"style": {"stroke": {"width": 3}}}}],
 "snapshot": null}
```

- **Each part is in the form its own document has:** an entry's `id` as `Store.encode_id/1` writes it, its `fragment` in the type's map form (spec/02 §9), and `snapshot` in a snapshot's form. `exported_at` is ISO 8601 in UTC. A `provenance.store` named by a string or an atom is that name's string, and any other term is its tagged term; a term the tag table has no form for is `{:type, :term}` at `[:provenance, :store]` rather than a document that cannot be read.
- **`Bundle.from_map(map, types, opts)` and `from_json(json, types, opts)` read in the order every reader keeps** (spec/01 §5), the fragment types the reader may meet given as a store's are:
  - first the stamp (`{:newer_version, needs, this}` at `["$version"]`) and the provenance's `version`, before a key is decoded;
  - then the `depth` and `items` limits over the whole document;
  - then every key, each fault at its path.
- **The faults:**
  - a key the bundle does not have is `:unknown_key`;
  - `provenance`, `entries` and each entry's `id`, `name` and `fragment` are `:required`;
  - an `exported_at` that is not a UTC time is `{:type, :utc_datetime}`;
  - an `id` that is not of a kind the type has is `{:type, :id}`, since no atom is made from a document's kind;
  - an id carried twice is `{:duplicate, id}`;
  - a fragment that does not read is its faults under `[:entries, i, :fragment]`;
  - a fragment that derives to no kind is `:no_kind` there.
- **A fragment is not validated as a whole document,** since a fragment may be partial.

`from_map(to_map(b))` is `{:ok, b}`, and `from_json(to_json(b))` is `{:ok, b}` with a store named by an atom read as its string.

```planned-test:stores-bundle-forms
a bundle round-trips through its map and JSON forms; a newer stamp is refused before any key is read, the limits apply, and every fault is at its path: unknown keys, required parts, a bad time, an id of no kind, a duplicate id, a fragment that does not read
```

### 3.3 Import is a relocation {#stores-import}

<!-- surfex: deferred #132: bundles, the closure, the forms and import as a relocation -->

Import has every property that ruled out renaming by name: it is bounded to a known set, it happens once at the boundary between stores rather than during editing, and it is one call with one outcome. `Store.relocate(assign, bundle)` is the import every store may use as its own, each entry read through the store's type of its kind:

1. **Every check runs before anything is written:**
   - the bundle's version, through the version line (`{:newer_version, needs, this}`);
   - each fragment through the type's reader, its migrations and its validation as a fragment;
   - every name a fragment uses that the host's registry does not know (macaw_compose spec/12 §1).
2. **New ids are issued** — each entry `put/2` without its id — and one table `old → new` is built.
3. **References are rewritten through that table** (`Fragment.relocate/3`) and each entry is put again under its new id.
4. **It commits whole or not at all,** and every fault is reported, each at `[:entries, i | path]`. A store whose writes can fail midway (a database) wraps steps 2 and 3 in its own transaction; the memory store applies them to a copy and swaps it in.

A reference to an id **outside** the bundle — only possible in a hand-edited file — imports as a mask and is **reported** in `outside`, by entry and path, never a failure and never silent.

```planned-test:stores-import-relocation
import checks every entry before writing, issues new ids, rewrites every reference through one table, commits whole or reports every fault with nothing written, and reports references outside the bundle as masks
```

## 4. Ids on object storage {#stores-object}

<!-- surfex: deferred #4: open research, settled before an exio-backed store is built -->

Open (macaw_compose#4). visualize's per-type sequences, which are never reused, are awkward on S3. The options are:
- ids derived from object keys;
- a manifest object that issues ids by conditional write;
- content-addressed ids for immutable fragments.

This is deferred until an exio-backed store is built.
