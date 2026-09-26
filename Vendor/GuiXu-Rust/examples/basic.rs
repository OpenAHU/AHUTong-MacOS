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
    let db = GuiXu::new("./target/example-db")?;
    let mut box_ = db.box_for::<TestClass>()?;
    let mut kv = db.kv_box_for("testKv")?;

    let mut data = TestClass {
        id: 0,
        name: "Aa".to_string(),
        age: 18,
    };

    let id = box_.put(&mut data)?;
    println!("typed id={id}, data={:?}", box_.get(id)?);

    kv.put_string("name", "GuiXu")?;
    kv.put_int("age", 18)?;
    println!(
        "kv name={}, age={}",
        kv.get_string("name")?,
        kv.get_int("age")?
    );

    Ok(())
}
