// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use crate::basic_box::{BasicBox, BoxInfo};
use crate::error::{GuiXuError, Result};
use serde::{de::DeserializeOwned, Serialize};
use std::marker::PhantomData;
use std::path::PathBuf;

pub trait StoreData {
    fn id(&self) -> u64;
    fn set_id(&mut self, id: u64);
}

pub struct TypedBox<T> {
    basic: BasicBox,
    _marker: PhantomData<T>,
}

impl<T> TypedBox<T>
where
    T: StoreData + Serialize + DeserializeOwned,
{
    pub(crate) fn open(path: PathBuf, name: String) -> Result<Self> {
        Ok(Self {
            basic: BasicBox::open(path, name)?,
            _marker: PhantomData,
        })
    }

    pub fn put(&mut self, data: &mut T) -> Result<u64> {
        let id = self.basic.check_id_and_get(data.id())?;
        data.set_id(id);
        let bytes = bincode::serialize(data)
            .map_err(|error| GuiXuError::Serialization(error.to_string()))?;
        self.basic.append_store(id, &bytes)?;
        Ok(id)
    }

    pub fn get(&self, id: u64) -> Result<T> {
        let bytes = self.basic.get_byte(id)?;
        let mut data: T = bincode::deserialize(&bytes)
            .map_err(|error| GuiXuError::Serialization(error.to_string()))?;
        data.set_id(id);
        Ok(data)
    }

    pub fn all(&self) -> Result<Vec<T>> {
        self.basic
            .all_bytes()?
            .into_iter()
            .map(|bytes| {
                bincode::deserialize(&bytes)
                    .map_err(|error| GuiXuError::Serialization(error.to_string()))
            })
            .collect()
    }

    pub fn remove(&mut self, id: u64) -> Result<()> {
        self.basic.remove_entry(id)
    }

    pub fn clear(&mut self, re_init: bool) -> Result<()> {
        self.basic.clear(re_init)
    }

    pub fn compact(&mut self) -> Result<()> {
        self.basic.compact()
    }

    pub fn close(&mut self) -> Result<()> {
        self.basic.close()
    }

    pub fn get_info(&self) -> BoxInfo {
        self.basic.get_info()
    }
}
