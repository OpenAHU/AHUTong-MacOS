// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

mod basic_box;
mod byte_array_box;
mod byte_ops;
mod error;
mod file_access;
mod guixu;
mod kv_box;
mod typed_box;

pub use basic_box::{BasicBox, BoxInfo};
pub use byte_array_box::ByteArrayBox;
pub use error::{GuiXuError, Result};
pub use guixu::GuiXu;
pub use kv_box::KVBox;
pub use typed_box::{StoreData, TypedBox};

#[macro_export]
macro_rules! impl_store_data {
    ($ty:ty, $field:ident) => {
        impl $crate::StoreData for $ty {
            fn id(&self) -> u64 {
                self.$field
            }

            fn set_id(&mut self, id: u64) {
                self.$field = id;
            }
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
    struct TestClass {
        id: u64,
        name: String,
        age: i32,
    }

    impl_store_data!(TestClass, id);

    #[test]
    fn byte_array_box_round_trips() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let db = GuiXu::new(dir.path())?;
        let mut box_ = db.byte_array_box_for("bytes")?;

        let id = box_.put(0, b"hello".to_vec())?;

        assert_eq!(id, 1);
        assert_eq!(box_.get(id)?, b"hello".to_vec());
        Ok(())
    }

    #[test]
    fn kv_box_round_trips_primitives() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let db = GuiXu::new(dir.path())?;
        let mut kv = db.kv_box_for("settings")?;

        kv.put_string("name", "GuiXu")?;
        kv.put_int("age", 18)?;
        kv.put_bool("enabled", true)?;

        assert_eq!(kv.get_string("name")?, "GuiXu");
        assert_eq!(kv.get_int("age")?, 18);
        assert!(kv.get_bool("enabled")?);
        Ok(())
    }

    #[test]
    fn kv_box_preserves_numeric_key_semantics_after_reopen() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let db = GuiXu::new(dir.path())?;
        let mut kv = db.kv_box_for("numeric-settings")?;

        kv.put_string("1", "numeric")?;
        kv.put_string("01", "string")?;
        kv.close()?;

        let mut reopened = db.kv_box_for("numeric-settings")?;
        assert_eq!(reopened.get_string("1")?, "numeric");
        assert_eq!(reopened.get_string("01")?, "string");

        reopened.put_string("1", "updated")?;
        assert_eq!(reopened.get_string("1")?, "updated");
        assert_eq!(reopened.get_string("01")?, "string");
        Ok(())
    }

    #[test]
    fn kv_box_handles_sparse_numeric_keys_after_reopen() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let db = GuiXu::new(dir.path())?;
        let mut kv = db.kv_box_for("sparse-numeric-settings")?;

        kv.put_string("5000", "sparse")?;
        kv.put_string("0", "dense")?;
        kv.close()?;

        let reopened = db.kv_box_for("sparse-numeric-settings")?;
        assert_eq!(reopened.get_string("5000")?, "sparse");
        assert_eq!(reopened.get_string("0")?, "dense");
        Ok(())
    }

    #[test]
    fn typed_box_round_trips_store_data() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let db = GuiXu::new(dir.path())?;
        let mut box_ = db.box_for::<TestClass>()?;
        let mut data = TestClass {
            id: 0,
            name: "Aa".to_string(),
            age: 18,
        };

        let id = box_.put(&mut data)?;
        let loaded = box_.get(id)?;

        assert_eq!(id, 1);
        assert_eq!(data.id, id);
        assert_eq!(loaded, data);
        Ok(())
    }
}
