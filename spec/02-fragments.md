# 02 — Fragments and stacking {#documents-fragments}

Every configurable thing in Macaw is a document of the **fragment shape** (macaw_compose spec/07 §1): pages, surfaces and cells, component settings, templates, layers, themes and styles, and visualize's designs. They combine, mask, bind and explain the same way, through the machinery this file specifies. It is visualize's (spec/14 §1.4–§1.5, §7, §8, §17.1–§17.2, §19; D-58, D-65, D-81–D-84, D-87, D-92, D-98–D-104, D-182, D-187, D-195), made generic over document types (macaw_compose#94):

- **the rules are the type's.** Which keys append, unite, deepen or override, which elements a layer replaces in place, where a fragment of each kind lands: visualize read these from its chart schema. Here a document type declares them through one behavior (§1), so the machinery holds no type's vocabulary and every type combines the same way;
- **names are strings, matched by spelling;** the library's own vocabularies (rules, kinds) stay atoms (spec/01 §1);
- **the store and its ids are 03's;** this file says what an id is in a fragment and how a fragment is relocated.

| Module | What it is |
|---|---|
| `Macaw.Layers.Fragment` | the fragment-type behavior, and the operations over fragments of a type: kind, ids, `compose/3`, `stack/2`, `explain/2` (§1–§4, §6), and the forms of this file's terms and where a type's name maps are (§9) |
| `Macaw.Layers.Var` | a variable, binding and the variables still open (§5) |
| `Macaw.Layers.Use` | a use site: `ref → local → mask → bind` (§7) |
| `Macaw.Layers.Composite` | composites: flattening and decomposing (§8) |

## 1. Fragment types {#fragments-types}

A **fragment** is a document of a type, or any part of one: a map with the type's keys, not necessarily all of them and not validated. A **document type** that stacks implements `@behaviour Macaw.Layers.Fragment` beside `Macaw.Layers.Document` and `Macaw.Layers.Version` (spec/01 §4, §5):

| Callback | Contract |
|---|---|
| `root() :: kind` | the node kind of a whole document of the type (visualize's `:design`) |
| `key(kind, key) :: spec \| nil` | how a key of a node of `kind` combines: `%{merge: rule, node: kind \| nil, element: kind \| nil}`, or `nil` for a key the type does not know |
| `identity(kind, element) :: term()` *(optional)* | the identity of an element of a `:concat` list whose elements are of `kind`, or `nil` for none (§3.2) |
| `kinds() :: [atom()]` | every kind a fragment of the type can be, and so every kind an id can carry (§6) |
| `wrapper(key) :: kind \| nil` | the kind a **singular wrapper** key names (`style:` → `:style`), or `nil` (§6.1) |
| `place(kind, body, key) :: {:ok, layer} \| :keyless` | where a composite's site of `kind` lands in a whole document (§8.2) |
| `holes(kind, key, value) :: [Var.t()]` *(optional)* | the variables a value of the type's own syntax holds, a text template's holes (§5.2) |
| `bind_holes(kind, key, value, bindings) :: term()` *(optional)* | that value with its holes substituted, written back in the type's syntax (§5.1) |
| `merge(rule_name, lower, higher) :: term()` *(optional)* | the type's own merge of a key whose rule is `{:type, rule_name}` (§2) |
| `normalize(kind, key, lower, higher) :: {lower, higher}` *(optional)* | the two values of a key both fragments hold, as they merge: a shorthand on one side expanded to the part the other gives (§3.3) |
| `under(kind, lower, higher) :: lower` *(optional)* | what of a lower node of `kind` the higher one, merging over it, keeps (§3.3) |
| `scope(composite, contribution, key) :: contribution` *(optional)* | one resolved site's contribution as the composite node holding it shapes it, before it is placed (§8.1) |
| `place_whole(contribution, key) :: {:ok, layer}` *(optional)* | a keyed site's contribution of no kind, placed under the site's key (§8.2) |
| `inline(document, fetch) :: {document, [{id, path}]}` *(optional)* | every id left at a reference site of a flattened document resolved through `fetch`, and the ids that were missing (§8.1) |
| `decompose(document) :: [Use.t()]` *(optional)* | a whole document as inline sites, one kind each (§8.2) |

A `spec`'s `merge` is a rule of §2; `node` and `element` may be left out, and are then `nil`. `node` is the node kind of a key whose value is a node, so a node given as a map by both fragments combines key by key under that kind's specs; `element` is the node kind of a `:concat` list's elements, which `identity/2` reads. A key the type does not know is `:override` with no node: it is taken as it is.

**A struct is a leaf of every walk** (visualize D-92). A variable stands *for* a value rather than being one, so no walk — composition, the cascade, binding, explanation, the forms, the free-variable walk — descends into a struct or merges one as a map, whatever the type says of the key it sits at. That a struct is a map in Elixir is an implementation fact and never a license to walk it: a walk excludes it explicitly. The two walks for **ids** (`refs/2`, `relocate/3`, §6.2) read a use site's parts by name (§7.1); every other walk keeps the rule.

```test:fragments-type-callbacks
a test fragment type declares its root, keys, identities, kinds, wrappers and placement; an unknown key is override with no node; a struct is a leaf of every walk, a use site's ids read by name only by refs and relocate
```

## 2. Merge rules {#fragments-rules}

Every key declares how two fragments combine under it. The **Effect** column is the union's (`compose/3`, §3.1); the cascade's difference where two fragments collide is §3.2.

| Rule | Keys (visualize's) | Effect |
|---|---|---|
| `:concat` | every list of elements: `marks`, `labels`, `axes`, `transforms` | the later fragment's elements follow the earlier's; elements are never merged with each other |
| `:union` | every name-keyed declaration: `sources`, `vars`, `styles`, `scales` | the union of the two maps; a name declared with equal values in both is taken once, and differently in both is `:conflict` at the name's path |
| `:deep` | a name map whose entries are assembled from fragments: `frames` | the union of the two maps, and a name both declare merges as a node of the key's `node` kind, key by key, rather than conflicting |
| `:override` | every scalar and every other node | the later fragment's value replaces the earlier's; a node given as a map by both combines key by key under its `node` kind |
| `{:type, name}` | a key whose combination is the type's own (visualize's style parts) | the type's `merge(name, lower, higher)`, in both operations; the value is a leaf of `explain/2` |

**A key either fragment gives as a struct** — a whole-node variable — is not a map of names, a list or a node, whatever its rule: equal in both it is taken once, and different it is the later's, which `compose/3` reports as `:conflict` at the *key's* path and `stack/2` takes silently (§3). A variable at a `:concat` key is the later's value with no conflict, since a collection has no names for two fragments to claim.

```test:fragments-rules-each
each of the five rules combines as its row says under compose and under stack; a struct at a mergeable key is one value, a conflict for compose at the key's path and the higher layer's for stack
```

## 3. Composition and the stack {#fragments-stack}

Two operations close over fragments, and both are total in the sense that matters: their result is a fragment, so a stored composition is a part of another and a stored stack a layer of another. **`compose/3` is the union:** it assembles one document from parts meant to be disjoint, and a name two of them declare differently is a fault. **`stack/2` is the cascade:** it layers documents meant to overlap — a house look, a shared frame, a cell's own overrides — and a name two layers declare differently is the higher layer's word. Neither validates nor fills defaults: the result becomes a document through the type's reader (spec/01 §5), which is where it validates.

| Function | Contract |
|---|---|
| `Fragment.compose(type, a, b)` | `b` over `a` by every key's rule: `{:ok, fragment}` or `{:error, faults}`, every `:conflict` at its path, ordered by path |
| `Fragment.compose(type, list)` | the left fold: `compose([a, b, c])` is `compose(compose(a, b), c)`; `compose([])` is `{:ok, %{}}` |
| `Fragment.stack(type, lower, higher)` | the cascade of two layers: the fragment itself, never a tuple, since a cascade cannot fail |
| `Fragment.stack(type, layers)` | the left fold, the later layer the higher; `stack([])` is `%{}`, `stack([a])` is `a`; a layer may be a `{name, fragment}` pair, whose name `stack` ignores and `explain/2` reports |

### 3.1 `compose/3`: the union {#fragments-compose}

For each key present in either fragment, by the key's spec in the node kind being merged, starting at the type's `root()`:

- **`:concat`** — the later fragment's elements after the earlier's.
- **`:union`** — the union of the two name-keyed maps. A name in both with equal values is taken once; with different values it is `:conflict` at the name's path, every conflict reported. A house sheet composed with a document's own entries disagrees loudly, never silently.
- **`:deep`** — the union, and a name both declare merges as a node of the key's `node` kind. Two fragments naming the same entry are parts of one entry, not a disagreement.
- **`:override`** — the later value, except that a key whose `node` is a kind, given as a map by both, composes key by key under that kind.
- **`{:type, name}`** — the type's merge.

A key present in one fragment alone is taken as it is. Over a list, `:concat` and `:union` keys compose associatively and `:override` keys last-wins, so the order of the fragments is the order of their elements and the precedence of their scalars.

```test:fragments-compose-union
compose appends concat keys, unites union keys reporting every conflict at its name's path, deepens deep keys, overrides scalars and recurses into nodes; the list form folds left and compose of nothing is the empty fragment
```

### 3.2 `stack/2`: the cascade {#fragments-cascade}

For each key present in either layer, by the key's spec in the node kind being merged:

- **`:concat`** — a higher element whose **identity** equals a lower element's replaces it in place, keeping the lower's position; every other higher element follows the lower's. An element with no identity appends, so a stack of layers that name nothing behaves exactly as the union's append, and identity costs a type that declares none nothing. Identity matches only within one key, and the type declares it (`identity/2`; visualize's: a mark's or a label's `id` when it has one, an axis's `{scale, side}` always, a transform none). Because a fragment is not a whole document, an identity need not be unique within one: where the cascade merges two lists it reads the lower's elements and the higher's as one sequence and collapses duplicates in both, **each identity keeping its first position and its last value**, so the result is the same however the layers are grouped. A matched element is replaced **whole**, never merged key by key: an element's meaning is its whole node, and a higher element merged over a lower one would draw something no layer wrote.
- **`:union`** — the union, and a name both declare is the **higher layer's entry, whole**. Derivation within an entry is the type's business (visualize's `extends`), not the cascade's.
- **`:deep`** — the union, and a name both declare cascades as a node.
- **`:override`** — the higher value, except that a node both give as a map cascades key by key.
- **`{:type, name}`** — the type's merge, the lower first.

A key one layer alone carries is passed through untouched, so a fragment that is never stacked is never rewritten. Every rule cascades **associatively where every layer gives a mergeable key as a map** (a `:union` key as a name map, a node key as a node), so a stack built in parts is the stack of the whole, unless the type trims a node whose type changes (`under/3`, §3.3). The other exception is a layer that gives a mergeable key as a **struct**: it *replaces* the declaration, and a replacement in the middle of a stack is not recoverable by regrouping, so `stack/2` of a list is defined as the left fold, which is what `explain/2` reports. This is the second reason `compose/3` reports the pair as a conflict (visualize D-92).

**The two agree where the fragments are disjoint.** Over two fragments that declare no `:union` or `:deep` name and no `:override` key in common, `stack` is the map `compose` answers: the property that holds the two definitions together as a type's rules grow.

```test:fragments-cascade-identity
a higher element with the lower's identity replaces it whole in place, every other appends; duplicates in either layer collapse to first position and last value; a union name is the higher entry whole; a key one layer carries passes through untouched
```

```test:fragments-stack-algebra
stack is the left fold and associative wherever no layer gives a mergeable key as a struct; stack of one layer is that layer; over disjoint fragments stack equals the map compose answers
```

### 3.3 The type's hooks {#fragments-hooks}

**Two optional callbacks let a type say how its own nodes merge,** in `compose/3`, `stack/2` and `explain/2` alike, so the three never disagree. A type without them merges exactly as §3.1 and §3.2 say.

- **`normalize(kind, key, lower, higher)`** runs for a key **both** fragments hold, before its rule, and answers the two values the rule then merges. A type expands a shorthand written on one side to the part the other side gives (visualize's style parts: `stroke: "red"` against `stroke: %{width: 2}` is a solid part of color red), so the two merge key by key and `explain/2` reports one leaf per part. A key one fragment alone holds is never normalized: a fragment that is not merged is not rewritten.
- **`under(kind, lower, higher)`** runs where two nodes of `kind` merge, and answers what of the lower node the higher keeps, before the merge. A node whose type changes keeps of the lower only what no type decides (visualize D-172: a dashed paint under a gradient keeps its width, not its dash); a node of the same type, or a lower node of none, keeps all.

**A trim is a replacement,** as a struct at a mergeable key is (§3.2): what an intermediate layer's type change drops, a later layer can't bring back, so how the layers are grouped matters. A dashed paint, then an untyped paint naming red, then a gradient: folded left, red is dropped with the dashed type; grouped the other way, red meets the gradient untrimmed. So `stack/2` of a list is its left fold, which is what `explain/2` reports, and it is associative wherever no layer's type change trims. No rule that drops keys on a type change can be associative, whichever node it reads: an intermediate layer can drop a key a later one would keep.

A theme's style nodes are a fragment type, `Macaw.Layers.Theme.Style`, with no hooks; an adopter's hooks reach a theme's palette through an extension's style type (spec/04 §2.4, §3.4).

**Provenance follows the normalized parts.** A leaf that came from a value a layer set whole and the type expanded is reported as that layer's: `explain/2` gives a leaf the layer of its own path, else of the nearest path above it a layer set.

```test:fragments-hooks-normalize
a shorthand against a part merges as the part key by key, in stack and compose alike, either way round; two shorthands are the higher's word; explain reports each normalized part's leaf with the layer that set it
```

```test:fragments-hooks-under
a node whose type changes keeps of the lower only what no type decides, a node of the same type keeps all, a lower node of no type keeps all under a typed one, and a deep entry and compose are trimmed the same way
```

```test:fragments-hooks-left-fold
a stack where a type change trims is its left fold, and grouped otherwise differs; over generated layers that never change a node's type, stack with the hooks is associative
```

```test:fragments-hooks-without
a type without normalize/4 and under/3 merges exactly as before
```

## 4. Masks {#fragments-masks}

**A mask drops keys from a fragment before it is stacked**, so a lower layer's value shows through. It is the dual of a site's local node, which adds: without it the only way to let a lower key through is to copy the lower value up, which drifts, or to fork the fragment, which bloats the library. A mask is a list of **paths**, each a list of keys from the fragment's root, or `:all`:

- a path removes the value at it, and an emptied node above it is kept as an empty map, so the key is genuinely absent when the cascade runs;
- **`:all` removes everything**: disabling a layer is a mask of everything (visualize D-87), and the document is what it would be without that layer;
- a path that names nothing is ignored: a mask says what this site does not want, and a fragment that does not carry it already agrees.

`Macaw.Layers.Use.mask(fragment, mask)` applies one (§7). Because the key is absent by the time the cascade runs, `explain/2` attributes the value to the layer it now comes from, which is simply true.

```test:fragments-mask-paths
a mask removes each path, keeps emptied nodes as empty maps and ignores a path that names nothing; all removes everything; a masked key shows the lower layer's value through the cascade
```

## 5. Variables {#fragments-vars}

`%Macaw.Layers.Var{name: name}`, built by `Var.new/1`, is a term allowed wherever a value can appear — a scalar, an element, a whole node — and it carries **only its name**, a string (an atom given in Elixir is read as its string). Its default, where it has one, is declared once by the document that uses it (visualize's `vars`), so two fragments cannot disagree about it. A variable is a struct, so it is a leaf of every walk (§1).

```test:fragments-var-name
new reads an atom as its string, and a variable stands as one value at a scalar, an element or a whole node, never merged or descended
```

### 5.1 Binding {#fragments-bind}

`Var.bind(fragment, bindings)` is a **pure substitution**: every `%Var{name: k}` in the fragment becomes the value `bindings` gives `k` (a map keyed by name, by either spelling), and a variable `bindings` does not name stays. A binding to a literal **sets** the variable; a binding to another `%Var{}` **renames** it. The result is a fragment with fewer, or differently named, variables. Binding runs at a use site before the cascade (§7), so a fragment placed at several sites can mean something different at each:

| Case | The site's `vars` | The variables still open |
|---|---|---|
| shared — one value for every site | nothing | the fragment's name |
| set — a literal at this site | `%{"color" => "blue"}` | nothing from this site |
| renamed — this site's variable is the composite's own | `%{"color" => %Var{name: "color_1"}}` | `color_1` |

A composite placed inside a larger composite is bound again, so bindings nest like function application. Binding is **single level**: the value a variable is bound to is not itself searched for variables, so a binding settles in one pass and a stored document cannot bind a variable to a chain that never ends. A variable a type's own syntax holds (a text template's hole, §5.2) is found by the type's `holes/3` and substituted by its `bind_holes/4`, which writes the value back in the type's syntax.

```test:fragments-bind-substitution
bind sets a variable to a literal, renames it to another variable, leaves an unnamed one, reads names by either spelling, does not search a bound value, and reaches a type's holes
```

### 5.2 The variables still open {#fragments-free-vars}

`Var.free(type, layers)` takes a fragment or the layers of a stack — stacked first by `stack/2` — and answers one entry per variable still in the result, ordered by name:

| Key | What |
|---|---|
| `name` | the variable's name |
| `uses` | one entry per path the variable stands at, ordered by path: `path`, and `layer`, the layer that set the leaf it stands in, named as `explain/2` names it (§6.3) |

A fragment is a one-layer stack, its uses reported at layer `0`. The walk descends into nodes, name maps, lists and, through the type's `holes/3`, into a value of the type's own syntax (a text's holes stand at the text's key, each named once however many holes name it), and stops at every other leaf. A variable inside a value another variable is bound to is not reached, because binding does not reach it either. The document type adds what it knows of a variable — its declared default, and whether it is still required — from its own declarations (visualize's `free_vars/1` adds `default`, `required` and `expects`, the type at the path).

A variable and a literal override each other in a stack like any other value: a higher literal over a lower variable leaves one use fewer, and a higher variable over a lower literal one more. That is the whole of the interaction between variables and the cascade.

```test:fragments-free-uses
free lists each variable of the stacked result by name with every use by path and the layer that set it; a literal over a variable removes a use and a variable over a literal adds one; holes are reported at their text's key once
```

## 6. Kinds, ids and provenance {#fragments-kinds}

### 6.1 The kind of a fragment {#fragments-kind}

**A kind is derived, never stored.** `Fragment.kind(type, fragment)` walks down while the fragment sets exactly one key, and the kind is the last thing reached: a **singular wrapper** (`%{style: %{…}}`, the type's `wrapper/1`) is the kind it names, a name map holding one entry (`%{frames: %{main: …}}`) is the kind of that entry (`:frame`), a list holding one or several elements the elements' kind, and `%{composite: %{uses: …}}` is `:composite`. **A fragment about more than one thing is no kind of fragment** — a map that branches at the top, or whose one key stops at the root (`%{version: 2}`), derives to `nil`, and a store refuses to hold it (spec/03 §1); the thing that is many kinds is a composite, whose sites are each one kind (§8). A whole document is therefore stored under its type's wrapper (`%{theme: …}`, §5 of spec/04), never bare. The wrapper is what keeps a bare body's kind readable without a store having to say it: inside a fragment's body there is no name at all, only values (`%{style: %{stroke_width: 5}}`).

```test:fragments-kind-derived
kind walks single keys to the wrapper's kind, a one-entry name map to its entry's kind, a composite to composite and a whole document to the root; a map that branches at the top has no kind
```

### 6.2 Ids in a fragment {#fragments-ids}

An **id** is `{kind, n}`: a kind of the type's `kinds/0` and a positive integer a store issued (spec/03 §2). It stands at a reference site — where the type takes a reference — and inside a use site's parts (§7).

| Function | Contract |
|---|---|
| `Fragment.refs(type, fragment)` | every id the fragment refers to, once each, sorted: the order a map is walked is the runtime's, not a promise; a use site's `ref`, `origin`, `local` and `vars` included |
| `Fragment.relocate(type, fragment, table)` | `{fragment, missed}`: every id rewritten through `table`, `%{old => new}`, and the ids the table did not carry, sorted; a use site's ids rewritten in place, the site still a `%Use{}` |

Without reading a use site's parts by name, a composite would export without its dependencies and import still pointing at its source store's entries (visualize#470); every other walk keeps the struct rule.

```test:fragments-refs-relocate
refs lists every id once, sorted, those inside use sites included; relocate rewrites every id through the table, use sites in place, and answers the ids it did not carry
```

### 6.3 `explain/2`: provenance {#fragments-explain}

`Fragment.explain(type, layers)` takes the layers of a stack — the list `stack/2` takes — and answers one entry per **leaf path** of the stacked result, ordered by path:

| Key | What |
|---|---|
| `path` | the keys and list indexes from the root to the value |
| `value` | the value at that path in `stack/2` of the same layers |
| `layer` | the layer that set it: its name, or its zero-based position when given without one |
| `overrode` | the layers that set a value at the same path and were overridden, lowest first; `[]` where none did |

A **leaf** is a value the cascade does not descend into: the walk descends through nodes, name maps and the elements of lists, and stops at a scalar, a name, a struct, a `{:type, name}` key's value and a whole node given as anything but a map. Every leaf of the result has exactly one entry, and every entry's layer is a layer of the list.

**Why the layers and not the result.** A stack's result is a fragment, and a fragment carrying provenance tags would not be one: the tags are keys no node declares, so the tagged map would not validate, would not survive the forms and could not be a layer of another stack. `explain/2` therefore recomputes the stack from the layers, **sharing `stack/2`'s merge exactly** — the same recursion into nodes, the same whole-entry rule for a `:union` name, the same identity rule for a `:concat` element — so what it reports and what `stack/2` produces cannot drift.

Two limits follow from the cascade's shape and are not defects. A value a higher layer discarded by replacing a whole `:union` entry or a whole identified element has no path in the result, so no entry; the layer that discarded it is named on the sibling leaves it did write. And `overrode` names layers that set a value **at the same path**: a higher element that adds a key the lower did not carry overrode nothing at that key.

```test:fragments-explain-leaves
explain answers one entry per leaf of the stacked result with its value, the layer that set it by name or position and the layers it overrode at that path; its values are exactly the stacked result's
```

## 7. Use sites {#fragments-use}

A layer in a composite and an entry in a stack at a site are the same thing: a fragment **used at a position**. The site is a struct, so it is a leaf of every walk but the two id walks (§6.2).

```elixir
%Macaw.Layers.Use{
  id:     {:use, 7},          # the site's own identity, the same site wherever it sits
  ref:    {:style, 11},       # which fragment: an id, a local key, or nil for an inline-only site
  mask:   ["stroke"],         # paths removed here, so a lower layer shows through; or :all
  vars:   %{"color" => %Var{name: "color_1"}},  # what the fragment's variables mean here
  local:  %{opacity: 0.8},    # what is added or overridden here
  key:    "series",           # the name a name-keyed kind is declared under, here
  origin: nil                 # the entry an unlocked site was copied from, so it can be linked again
}
```

**Order of operations, stated once: `ref → local → mask → bind → stack`.** The referenced fragment is fetched; the local node cascades over it; masked paths are removed; variables are substituted (§5.1); and the result cascades with the sites around it (§3.2). Mask and bind run after local, so both speak for everything the site contributes, whichever part said it: a site that is nothing but its local is masked and bound like any other. A mask of `:all` removes the whole site, its local included.

**A missing reference is transparent.** A `ref` the fetch cannot find masks what the ref would have given: the site's local still stands, and lower layers show through (spec/03 §2, visualize D-100). Rendering never fails because of it; the miss is reported.

**`key` is the composite's word, never the fragment's.** A kind a document declares under a name lands under the site's `key`, so one fragment is `series` in one composite and `line` in another, and no fragment hard-codes the name a reference will use. A name-keyed site with no key is reported, not placed (§8.2). **The four states of a site toward its library entry** fall out of the parts: *linked* (`ref`, no local), *unlocked* (no `ref`, `origin` the entry, the entry's body copied into `local`), *edited* (`ref` and a kept `local`, the library's changes flowing under the local overrides) and *inline* (neither). `origin` is ignored by the cascade and by flattening, and carried by save.

| Function | Contract |
|---|---|
| `Use.new(ref)` | a use of `ref` with id `{:use, 1}` and the empty parts |
| `Use.new(ref, siblings)` | a use with a fresh id, one more than the highest among `siblings` |
| `Use.mask(fragment, mask)` | §4 |
| `Use.bind(fragment, vars)` | `Var.bind/2` |
| `Use.over(type, use, body)` | everything after the fetch, over a body in hand: `local`, `mask`, `bind` |
| `Use.resolve(type, use, fetch)` | one site through `fetch`, a function from an id to `{:ok, fragment}` or `:error`: `{:ok, contribution}`, or `{:missing, id, contribution}` where the ref was not found, the contribution then the local alone, masked and bound |

```test:fragments-use-order
a site resolves ref then local then mask then bind, mask and bind reaching the local too; mask all removes the site; a missing ref is its local alone and is reported; new issues the next id among siblings
```

## 8. Composites {#fragments-composites}

A **composite** is a fragment whose content is a list of use sites and its own variable declarations:

```elixir
%{composite: %{
  uses: [
    %Use{id: {:use, 1}, ref: {:theme, 32}},
    %Use{id: {:use, 2}, ref: {:frame, 2}, mask: [["margin"]]},
    %Use{id: {:use, 3}, ref: {:style, 11}, vars: %{"color" => %Var{name: "color_1"}}, local: %{opacity: 0.8}}
  ],
  vars: %{"color_1" => %{default: {:color, :series_1}}}
}}
```

**The composite node holds `uses`, `vars`, and the keys the type declares for its `:composite` kind** (`key(:composite, k)`; visualize's `defaults`), which the type's reader validates like any node's. The kernel reads only `uses` and `vars`; the type's own keys reach the sites through `scope/3` (§8.1).

```test:fragments-composite-shape
a composite is exactly one key, composite, holding a list of uses; anything else is not one and flattens to itself, and a composite of no sites flattens to the empty map
```

### 8.1 Stored as structure, flattened at deployment {#fragments-flatten}

**Save writes structure.** A store holds a composite's uses, never its flattened result, so a composite reopens as what was built — references intact, masks and bindings where they were left — and references keep their point: edit `{:style, 11}` and every composite using it follows. **Flatten is a deployment verb.** `Composite.flatten(type, composite, fetch)` resolves every site recursively — `ref → local → mask → bind` — through `fetch`, places each by its kind (§8.2), and stacks the placed layers in order: a whole document of the type, with no ids and no uses, which the type's reader validates.

It answers `{:ok, document, %{missing: [{id, at}], keyless: [use_id]}}` — every reference that showed through, `at` the use id of the site that named it or, for a reference inside the document, its path there, and every name-keyed site with no key — or `{:error, {:cycle, chain}}`. **Composites nest**: a site may reference a composite, which is flattened first, and then each of *its* sites placed. A composite that reaches itself through any chain of uses is refused at the site that closed the loop, `chain` the ids from the outer composite to it. The composite's own `vars` declarations are stacked into the result's variable declarations, the composite's under the document's.

**A composite's own keys reach its sites through the type.** Each resolved site's contribution passes through the type's `scope(composite, contribution, key)`, where it has one, before it is placed: visualize puts a composite's `defaults` under what each site places, so a gauge's needle and arc inherit the gauge's look. A type without it places the contributions as they resolved.

```test:fragments-composite-scope
a composite's own keys reach each site through scope/3 before placing, a site that says its own keeps them, and a type without scope/3 places the sites as they resolved
```

**Resolution is one rule.** Once the sites are placed, every id left at a reference site *inside* the document is resolved through the same `fetch` by the type's `inline/2` callback, where the type has one (visualize inlines a style body and declares a referenced scale or source under a synthesized key, `"scale:4"`), so what leaves `flatten` carries no ids and nothing below it needs a store. An id the store no longer holds is a mask at its site and is reported in `missing`.

```test:fragments-flatten-nested
flatten resolves every site in order, places each by its kind under its key, stacks them, nests composites, reports missing references by path and keyless sites, and refuses a cycle at the site that closed it
```

### 8.2 Placing a site by its kind {#fragments-place}

A site's contribution — its body after `ref → local → mask → bind` — is placed by the kind it derives to (§6.1), through the type's `place(kind, body, key)`: `{:ok, layer}`, the fragment that declares the body where a whole document keeps its kind, or `:keyless` for a name-keyed kind whose site has no key. A contribution of no kind (a whole document, a fragment of several keys) is placed under a site's key by the type's `place_whole(contribution, key)`, where the type has one (visualize lands a composite's one frame as the site's key, so a gauge placed under `"gauge"` draws in the frame `"gauge"`); without a key, or without the callback, it is its own layer (a host-seeded layer, an imported document). **Within a kind, the same operation:** a composite whose sites are all one wrapped kind and all `:keyless` — a stack of styles, none named — is a composer of that kind: it stacks its bodies as bodies, and its result is a fragment of that kind for the site that holds it to place under that site's key. A name-keyed kind is exactly one whose `place/3` answers `:keyless` without a key, so the rule needs nothing more from the type. visualize's placements are its own (a style under `styles[key]`, a mark appended under `marks`, a frame cascading into `frames`, a composite under a key landing its frames as that key), and a Macaw type declares its own the same way.

`Composite.decompose(type, document)` is the inverse: a whole document as inline sites, one kind each, keyed where the document keyed them, through the type's optional `decompose/1`; `flatten` of the result is the document again.

| Function | Contract |
|---|---|
| `Composite.composite?(fragment)` | whether a fragment is one key, `composite`, holding uses |
| `Composite.flatten(type, fragment, fetch)` | §8.1; a fragment that is not a composite flattens to itself |
| `Composite.place(type, contribution, key)` | one site's contribution as its layer, or `:keyless` |
| `Composite.decompose(type, document)` | a document as sites; flattening them is the document |

```test:fragments-place-kind
place puts a contribution where its kind lands through the type, under the site's key; a name-keyed kind without a key is keyless; a contribution of no kind is its own layer
```

```test:fragments-place-whole
a keyed site's contribution of no kind is placed by place_whole/2 under the site's key; without a key, or for a type without it, the contribution is its own layer
```

```test:fragments-decompose-inverse
decompose gives one inline site per kind keyed as the document keyed it, and flattening those sites is the document again
```

## 9. The forms {#fragments-forms}

A fragment's map and JSON forms are its type's (spec/01 §6), with three terms of this file tagged in the kernel's way, each read without an atom made:

| Value | Map form |
|---|---|
| `%Var{name: n}` | `{"$var": n}` |
| an id `{kind, n}` | `{"$id": [kind, n]}`, `kind` its string; a kind the type's `kinds/0` does not hold is refused at its path, never made an atom |
| `%Use{}` | `{"$use": {"id": n, "ref": …, "mask": [...] \| "all", "vars": {...}, "local": {...}, "key": …, "origin": …}}`, `origin` absent or `null` where there is none |

A type that stacks lists `$var`, `$id` and `$use` among its live tags (`Macaw.Layers.Tags`) and reads and writes them through `Fragment.encode_value/2` and `decode_value/3`, so `from_map(to_map(f))` is `{:ok, f}` for every fragment, a composite holding uses and ids included. A fragment is not validated as a whole document, since a fragment may be partial.

**Name maps.** A `:union` or `:deep` key holds a map of names (§2), so its keys are names, strings whatever their spelling, never the type's keys: a style may be named `"fill"`, a scale `"x"`. `Fragment.name_map?(type, path)` says whether the map at `path` (atom keys, string names and list indexes from the root) is one, derived from the type's specs by walking the path from `root/0`:
- a key whose spec is `:union` or `:deep` holds a name map, and each of its entries is a node of the spec's `element` kind;
- a key with a `node` kind leads to a node of that kind, and so does a singular wrapper key at the root (`wrapper/1`);
- a `:concat` key holds a list, each of whose elements is a node of its `element` kind;
- anything else is a leaf, below which nothing is a name map: a key the kind does not know, an `:override` key with no node, a `{:type, name}` key, an entry or element of no kind.

Below a tag (spec/01 §6) a path starts `{:tag, tag}`. A use site's `local` is a fragment of the type, so `[{:tag, "$use"}, "local" | path]` is `path` from the root, and `Fragment.encode_value/2` writes each part of a `$use` payload at its place (`encode_term/3`); every other payload's maps are nodes.

A fragment type implements the JSON adapter's `name_map?/1` (spec/01 §6) with it, in one line: `def name_map?(path), do: Fragment.name_map?(__MODULE__, path)`.

```test:fragments-name-map-positions
over the test type, a :union and a :deep key and a :union key inside a :deep entry hold name maps, and their entries, a :concat list's elements, a node, a root wrapper's node, a key the type does not know and the root do not; a wrapper leads to its kind's name maps at the root only; below a $use tag the local is at the root's positions and every other part is a node, and a use site whose local holds a style named "fill" round-trips through the map and JSON forms
```

```test:fragments-forms-round-trip
a fragment holding variables, ids and use sites round-trips through the map and JSON forms; an id of a kind the type does not hold is refused at its path and makes no atom
```
