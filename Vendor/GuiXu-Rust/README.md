# GuiXu Rust

Rust rewrite of the original Kotlin GuiXu embedded database prototype.

## Current Scope

- `GuiXu::new(path)` database initialization.
- `TypedBox<T>` with `serde` + `bincode` serialization.
- `ByteArrayBox` for raw bytes.
- `KVBox` for primitive key/value data.
- Append-only store files with 12-byte index items.
- `clear`, `remove`, `compact`, `get_info`, and `close` APIs.

The Rust `TypedBox<T>` storage is not byte-compatible with Kotlin `kotlinx.serialization.protobuf` yet. It is intentionally implemented with `serde` + `bincode` for the first Rust-native version.

## Example

```rust
use guixu::{impl_store_data, GuiXu, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TestClass {
    id: u64,
    name: String,
    age: i32,
}

impl_store_data!(TestClass, id);

fn main() -> Result<()> {
    let db = GuiXu::new("./data")?;
    let mut box_ = db.box_for::<TestClass>()?;

    let mut data = TestClass {
        id: 0,
        name: "Aa".to_string(),
        age: 18,
    };

    let id = box_.put(&mut data)?;
    let loaded = box_.get(id)?;

    println!("{loaded:?}");
    Ok(())
}
```

## Test

Run :

```bash
cd "对应目录"
cargo test
```

Run the basic example:

```bash
cargo run --example basic
```

## Benchmark

Run the Criterion benchmark suite:

```bash
cargo bench --bench guixu_bench
```

You can control the sample size:

```bash
GUIXU_BENCH_SAMPLE_SIZE=10 cargo bench --bench guixu_bench
```

For a quick throughput-style smoke test, the older example benchmark still exists:

```bash
cargo run --release --example benchmark -- 1000000 /tmp/guixu-bench
```

For more stable numbers, prefer a Linux filesystem path such as `/tmp/...` inside WSL instead of `/mnt/c/...`, because Windows-mounted paths are usually slower for file I/O.

## License

GuiXu Rust is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

## Attribution

GuiXu Rust is a derivative Rust rewrite of the original
[Delsart/GuiXu](https://github.com/Delsart/GuiXu) Kotlin project. The original
project and this rewrite are distributed under the Apache License, Version 2.0.

The Rust rewrite and subsequent modifications are recorded in this branch under
the following contributors:

- 100011646-Wang Zhong Kai
- Yukon163

See [NOTICE](NOTICE) for the attribution notice shipped with the project.

### Current 10M Operation Results

Environment used for the latest comparison:

- OS: Windows
- Branch: `rust-rewrite`
- Command:

```bash
cargo run --release --example benchmark -- 10000000 D:\code\AHUTong\GuiXu-Rust\target\benchmark-db-10m-dense-numeric-sparse-set-2
```

`KVBox` uses a dense numeric-key fast path for contiguous canonical numeric string keys such as `"0"` through `"9999999"`. Sparse numeric strings and arbitrary string keys keep using the normal string hash map path.

Rust results:

| Box | Operation | Total time | Time/op | Throughput |
| --- | --- | ---: | ---: | ---: |
| `KVBox<String>` | create | 1772.012 ms | 0.177 us/op | 5,643,302 ops/s |
| `KVBox<String>` | update | 892.441 ms | 0.089 us/op | 11,205,221 ops/s |
| `KVBox<String>` | read | 397.227 ms | 0.040 us/op | 25,174,503 ops/s |
| `KVBox<String>` | remove | 474.913 ms | 0.047 us/op | 21,056,488 ops/s |
| `ByteArrayBox` | create | 583.293 ms | 0.058 us/op | 17,144,037 ops/s |
| `ByteArrayBox` | update | 499.608 ms | 0.050 us/op | 20,015,708 ops/s |
| `ByteArrayBox` | read | 352.778 ms | 0.035 us/op | 28,346,447 ops/s |
| `ByteArrayBox` | remove | 38.754 ms | 0.004 us/op | 258,035,882 ops/s |
| `TypedBox<TestClass>` | create | 1169.678 ms | 0.117 us/op | 8,549,363 ops/s |
| `TypedBox<TestClass>` | update | 1156.766 ms | 0.116 us/op | 8,644,790 ops/s |
| `TypedBox<TestClass>` | read | 854.471 ms | 0.085 us/op | 11,703,147 ops/s |
| `TypedBox<TestClass>` | remove | 38.972 ms | 0.004 us/op | 256,597,112 ops/s |

Kotlin `main` branch comparison for the currently enabled `KVBox` test with `count = 10_000_000`:

| Operation | Kotlin main | Rust rewrite |
| --- | ---: | ---: |
| create | 2229 ms | 1772.012 ms |
| update | 1374 ms | 892.441 ms |
| read | 593 ms | 397.227 ms |
| remove | 906 ms | 474.913 ms |
