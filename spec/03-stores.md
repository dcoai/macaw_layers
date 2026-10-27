# 03 — Stores and references {#stores}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

Documents live in **stores**: the host's database, files in git, or an object store (exio). Macaw reaches them through one behavior. (visualize.md C8; metresis.md C8.)

## 1. The store behavior {#stores-behavior}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

```elixir
@callback list(context)            :: {:ok, [entry]} | {:error, reason}
@callback get(ref, context)        :: {:ok, entry} | {:error, :not_found | reason}   # ref = {type, id}
@callback put(entry, context)      :: {:ok, id} | {:error, reason}
@callback delete(ref, context)     :: :ok | {:error, reason}
@callback import(bundle, context)  :: {:ok, %{old_id => new_id}} | {:error, [fault]}
```

The **context** says who is acting and from where, so entries are traceable. The default store is in memory ([macaw_compose 00](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/00-overview.md) goal 3).

## 2. References {#stores-references}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

- **References are typed ids:** `{type, id}`, the type a document type ([macaw_compose 01](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/01-vocabulary.md#vocab-documents)). A reference of the wrong type is refused before resolution.
- **Names are attributes, never identities:** a route path, a slug, a title. macaw_server's route path becomes an attribute of a page id.
- **Versions are digests,** or the store's own object versions.
- **A missing reference is a validation fault** when the document is loaded, at its path ([macaw_compose 07](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/07-documents.md#documents-validation-time)). If an entry disappears **after** validation (deleted from the store while pages run), the site that referenced it is masked at render and reported; rendering never fails because of it.
- **A bundle takes the transitive closure.**
- **A bundle carries definitions** (re-keyed on import), and the bindings inside them, **never source configuration, credentials or data.**

## 3. Portability: bundles and state snapshots {#stores-portable}

<!-- surfex: deferred #94: built in order-of-work step 7 -->

Goal 9: save configuration, and state where possible, and restore it on another machine, right where you were.
- **A bundle** is the transitive closure of the documents a page (or a set of pages) needs: pages, surfaces, component settings and presets, templates, layers, themes and styles. It carries provenance (the source store, the export time, the version stamps) and each entry's original id.
- **A bundle may carry a state snapshot** ([macaw_compose 03](https://gitlab.conet.yarina.org/dco-tek/macaw_compose/-/blob/main/spec/03-state.md#state-snapshots)).
- **What never travels:**
  - credentials and source configuration: the importing host maps source names to its own configured sources;
  - data: sources re-read;
  - identity: the host's records stay with the host.
- **Import is a relocation:**
  - every check runs before anything is written (versions, migrations, validation, unknown names in the registry);
  - new ids are issued, and references are rewritten through one table;
  - it commits whole or not at all, and every fault is reported.

## 4. Ids on object storage {#stores-object}

<!-- surfex: deferred #4: open research, settled before an exio-backed store is built -->

Open (macaw_compose#4). visualize's per-type sequences, which are never reused, are awkward on S3. The options are:
- ids derived from object keys;
- a manifest object that issues ids by conditional write;
- content-addressed ids for immutable fragments.

This is deferred until an exio-backed store is built.
