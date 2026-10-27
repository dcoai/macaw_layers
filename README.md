# macaw_layers

Macaw's document layer ([spec/00](spec/00-overview.md)): the document kernel every declarative value is read through; fragments and stacking, stores and themes as the order of work reaches them (dco-tek/macaw_compose#56, #94).

| Module | What it is |
|---|---|
| `Macaw.Layers.Names` | names a document declares: strings, never atoms made from data ([spec/01 §1](spec/01-kernel.md#kernel-names)) |
| `Macaw.Layers.Vocabulary` | closed vocabularies looked up by spelling ([spec/01 §2](spec/01-kernel.md#kernel-vocabulary)) |
| `Macaw.Layers.Fault` | the fault `{path, reason}`, its order, and the one formatter ([spec/01 §3](spec/01-kernel.md#kernel-faults)) |

No runtime dependencies. Released by git tag:

```elixir
{:macaw_layers, git: "git@gitlab.conet.yarina.org:dco-tek/macaw_layers.git", tag: "v0.1.0"}
```

Part of [Macaw](https://gitlab.conet.yarina.org/dco-tek/macaw_compose).
