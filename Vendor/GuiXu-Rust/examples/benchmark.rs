use guixu::{impl_store_data, GuiXu, Result};
use serde::{Deserialize, Serialize};
use std::time::Instant;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TestClass {
    id: u64,
    name: String,
    age: i32,
}

impl_store_data!(TestClass, id);

fn main() -> Result<()> {
    let count = std::env::args()
        .nth(1)
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(100_000);

    let path = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "./target/benchmark-db".to_string());

    println!("count: {count}");
    println!("path: {path}");

    benchmark_kv_box(count, &path)?;
    benchmark_byte_array_box(count, &path)?;
    benchmark_typed_box(count, &path)?;

    Ok(())
}

fn benchmark_kv_box(count: usize, path: &str) -> Result<()> {
    let db = GuiXu::new(path)?;
    let mut box_ = db.kv_box_for("benchmark-kv")?;
    box_.clear(true)?;

    println!("\nKVBox<String>");
    measure("create", count, |index| {
        box_.put_string(index.to_string(), "dasdas")
    })?;
    measure("update", count, |index| {
        box_.put_string(index.to_string(), "dasdasdas")
    })?;
    measure("read", count, |index| {
        let _ = box_.get_string(&index.to_string())?;
        Ok(())
    })?;
    measure("remove", count, |index| box_.remove(&index.to_string()))?;

    Ok(())
}

fn benchmark_byte_array_box(count: usize, path: &str) -> Result<()> {
    let db = GuiXu::new(path)?;
    let mut box_ = db.byte_array_box_for("benchmark-bytes")?;
    box_.clear(true)?;
    let payload = vec![1, 2, 3, 4, 5, 6, 7, 8];

    println!("\nByteArrayBox");
    measure("create", count, |index| {
        let _ = box_.put(0, payload.clone())?;
        if index == usize::MAX {
            unreachable!();
        }
        Ok(())
    })?;
    measure("update", count, |index| {
        let _ = box_.put((index + 1) as u64, payload.clone())?;
        Ok(())
    })?;
    measure("read", count, |index| {
        let _ = box_.get((index + 1) as u64)?;
        Ok(())
    })?;
    measure("remove", count, |index| box_.remove((index + 1) as u64))?;

    Ok(())
}

fn benchmark_typed_box(count: usize, path: &str) -> Result<()> {
    let db = GuiXu::new(path)?;
    let mut box_ = db.box_for::<TestClass>()?;
    box_.clear(true)?;

    println!("\nTypedBox<TestClass>");
    measure("create", count, |index| {
        let mut data = TestClass {
            id: 0,
            name: "GuiXu".to_string(),
            age: index as i32,
        };
        let _ = box_.put(&mut data)?;
        Ok(())
    })?;
    measure("update", count, |index| {
        let mut data = TestClass {
            id: (index + 1) as u64,
            name: "GuiXu-Rust".to_string(),
            age: (index * 2) as i32,
        };
        let _ = box_.put(&mut data)?;
        Ok(())
    })?;
    measure("read", count, |index| {
        let _ = box_.get((index + 1) as u64)?;
        Ok(())
    })?;
    measure("remove", count, |index| box_.remove((index + 1) as u64))?;

    Ok(())
}

fn measure<F>(name: &str, count: usize, mut action: F) -> Result<()>
where
    F: FnMut(usize) -> Result<()>,
{
    let started = Instant::now();
    for index in 0..count {
        action(index)?;
    }
    let elapsed = started.elapsed();
    let elapsed_ms = elapsed.as_secs_f64() * 1_000.0;
    let ops_per_second = count as f64 / elapsed.as_secs_f64();

    println!(
        "{name:>8}: {:>10.3} ms | {:>10.3} us/op | {:>12.0} ops/s",
        elapsed_ms,
        elapsed.as_secs_f64() * 1_000_000.0 / count as f64,
        ops_per_second
    );

    Ok(())
}
