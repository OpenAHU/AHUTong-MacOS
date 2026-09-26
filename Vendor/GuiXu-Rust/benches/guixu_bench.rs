use criterion::{black_box, criterion_group, criterion_main, BatchSize, BenchmarkId, Criterion};
use guixu::{impl_store_data, GuiXu};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TestClass {
    id: u64,
    name: String,
    age: i32,
}

impl_store_data!(TestClass, id);

struct Fixture<T> {
    box_: T,
    #[allow(dead_code)]
    tempdir: tempfile::TempDir,
}

fn bench_kv_box(c: &mut Criterion) {
    let mut group = c.benchmark_group("kv_box");

    group.bench_function(BenchmarkId::new("put_string", "empty"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let box_ = db.kv_box_for("settings").unwrap();
                Fixture { box_, tempdir }
            },
            |mut fixture| {
                fixture
                    .box_
                    .put_string(black_box("name"), black_box("GuiXu"))
                    .unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("read_string", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.kv_box_for("settings").unwrap();
                box_.put_string("name", "GuiXu").unwrap();
                Fixture { box_, tempdir }
            },
            |fixture| {
                let _ = fixture.box_.get_string(black_box("name")).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("remove_string", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.kv_box_for("settings").unwrap();
                box_.put_string("name", "GuiXu").unwrap();
                Fixture { box_, tempdir }
            },
            |mut fixture| {
                fixture.box_.remove(black_box("name")).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.finish();
}

fn bench_byte_array_box(c: &mut Criterion) {
    let mut group = c.benchmark_group("byte_array_box");
    let payload = vec![1, 2, 3, 4, 5, 6, 7, 8];

    group.bench_function(BenchmarkId::new("put", "empty"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let box_ = db.byte_array_box_for("bytes").unwrap();
                Fixture { box_, tempdir }
            },
            |mut fixture| {
                fixture.box_.put(0, black_box(payload.clone())).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("read", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.byte_array_box_for("bytes").unwrap();
                let id = box_.put(0, payload.clone()).unwrap();
                (Fixture { box_, tempdir }, id)
            },
            |(fixture, id)| {
                let _ = fixture.box_.get(black_box(id)).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("remove", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.byte_array_box_for("bytes").unwrap();
                let id = box_.put(0, payload.clone()).unwrap();
                (Fixture { box_, tempdir }, id)
            },
            |(mut fixture, id)| {
                fixture.box_.remove(black_box(id)).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.finish();
}

fn bench_typed_box(c: &mut Criterion) {
    let mut group = c.benchmark_group("typed_box");

    group.bench_function(BenchmarkId::new("put", "empty"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let box_ = db.box_for::<TestClass>().unwrap();
                Fixture { box_, tempdir }
            },
            |mut fixture| {
                let mut data = TestClass {
                    id: 0,
                    name: black_box("GuiXu").to_string(),
                    age: black_box(18),
                };
                fixture.box_.put(&mut data).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("read", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.box_for::<TestClass>().unwrap();
                let mut data = TestClass {
                    id: 0,
                    name: "GuiXu".to_string(),
                    age: 18,
                };
                let id = box_.put(&mut data).unwrap();
                (Fixture { box_, tempdir }, id)
            },
            |(fixture, id)| {
                let _ = fixture.box_.get(black_box(id)).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.bench_function(BenchmarkId::new("remove", "preloaded"), |b| {
        b.iter_batched(
            || {
                let tempdir = tempfile::tempdir().unwrap();
                let db = GuiXu::new(tempdir.path()).unwrap();
                let mut box_ = db.box_for::<TestClass>().unwrap();
                let mut data = TestClass {
                    id: 0,
                    name: "GuiXu".to_string(),
                    age: 18,
                };
                let id = box_.put(&mut data).unwrap();
                (Fixture { box_, tempdir }, id)
            },
            |(mut fixture, id)| {
                fixture.box_.remove(black_box(id)).unwrap();
            },
            BatchSize::SmallInput,
        )
    });

    group.finish();
}

fn criterion_config() -> Criterion {
    let sample_size = std::env::var("GUIXU_BENCH_SAMPLE_SIZE")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(20);

    Criterion::default().sample_size(sample_size)
}

criterion_group! {
    name = benches;
    config = criterion_config();
    targets = bench_kv_box, bench_byte_array_box, bench_typed_box
}
criterion_main!(benches);
