// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use crate::byte_array_box::ByteArrayBox;
use crate::error::Result;
use crate::kv_box::KVBox;
use crate::typed_box::{StoreData, TypedBox};
use serde::{de::DeserializeOwned, Serialize};
use std::fs::create_dir_all;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Clone)]
pub struct GuiXu {
    inner: Arc<GuiXuInner>,
}

struct GuiXuInner {
    path: PathBuf,
}

impl GuiXu {
    pub fn new(path: impl Into<PathBuf>) -> Result<Self> {
        let path = path.into();
        create_dir_all(&path)?;
        Ok(Self {
            inner: Arc::new(GuiXuInner { path }),
        })
    }

    pub fn path(&self) -> &Path {
        &self.inner.path
    }

    pub fn box_for<T>(&self) -> Result<TypedBox<T>>
    where
        T: StoreData + Serialize + DeserializeOwned,
    {
        self.named_box_for(sanitize_type_name(std::any::type_name::<T>()))
    }

    pub fn named_box_for<T>(&self, name: impl Into<String>) -> Result<TypedBox<T>>
    where
        T: StoreData + Serialize + DeserializeOwned,
    {
        TypedBox::open(self.inner.path.clone(), name.into())
    }

    pub fn byte_array_box_for(&self, name: impl Into<String>) -> Result<ByteArrayBox> {
        ByteArrayBox::open(self.inner.path.clone(), name.into())
    }

    pub fn kv_box_for(&self, name: impl Into<String>) -> Result<KVBox> {
        KVBox::open(self.inner.path.clone(), name.into())
    }
}

fn sanitize_type_name(name: &str) -> String {
    name.chars()
        .map(|ch| match ch {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '_' | '-' | '.' => ch,
            _ => '_',
        })
        .collect()
}
