# macaw_layers

Macaw's document layer ([spec/00](spec/00-overview.md)): the document kernel every declarative value is read through; fragments and stacking, stores and themes as the order of work reaches them (dco-tek/macaw_compose#56, #94).

| Module | What it is |
|---|---|
| `Macaw.Layers.Names` | names a document declares: strings, never atoms made from data ([spec/01 §1](spec/01-kernel.md#kernel-names)) |
| `Macaw.Layers.Vocabulary` | closed vocabularies looked up by spelling ([spec/01 §2](spec/01-kernel.md#kernel-vocabulary)) |
| `Macaw.Layers.Fault` | the fault `{path, reason}`, its order, and the one formatter ([spec/01 §3](spec/01-kernel.md#kernel-faults)) |
| `Macaw.Layers.Version` | one version line per document type, and stepwise migration ([spec/01 §4](spec/01-kernel.md#kernel-versions)) |
| `Macaw.Layers.Document`, `Macaw.Layers.Limits`, `Macaw.Layers.Scan` | the gates a document is read through, in order: bytes, a scan that stops at a limit, decode, version, migrate, validate and recount ([spec/01 §5](spec/01-kernel.md#kernel-gates)) |
| `Macaw.Layers.Form`, `Macaw.Layers.Tags` | the value, map and JSON forms, exact inverses, and each type's table of `$` tags ([spec/01 §6](spec/01-kernel.md#kernel-forms)) |

No runtime dependencies. Released by git tag:

```elixir
{:macaw_layers, git: "git@gitlab.conet.yarina.org:dco-tek/macaw_layers.git", tag: "v0.1.0"}
```

Part of [Macaw](https://gitlab.conet.yarina.org/dco-tek/macaw_compose).
