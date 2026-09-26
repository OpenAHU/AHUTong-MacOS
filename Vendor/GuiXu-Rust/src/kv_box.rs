// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use crate::basic_box::{BasicBox, BoxInfo};
use crate::byte_ops::{
    bytes_to_f32_vec, bytes_to_f64_vec, bytes_to_i32, bytes_to_i32_vec, bytes_to_u64,
    bytes_to_u64_vec, f32_slice_to_bytes, f64_slice_to_bytes, i32_slice_to_bytes, i32_to_bytes,
    u64_slice_to_bytes, u64_to_bytes,
};
use crate::error::{GuiXuError, Result};
use crate::file_access::AutoIncreaseFileAccess;
use rustc_hash::{FxHashMap, FxHashSet};
use std::borrow::Cow;
use std::fs::remove_file;
use std::path::PathBuf;

const KV_ITEM_FIX_LENGTH: u64 = 13;
const BOOLEAN_TRUE: u8 = 1;
const VALUE_TYPE_DELETE: u8 = 0;
const VALUE_TYPE_BOOLEAN: u8 = 1;
const VALUE_TYPE_BYTE: u8 = 2;
const VALUE_TYPE_INT: u8 = 3;
const VALUE_TYPE_LONG: u8 = 4;
const VALUE_TYPE_FLOAT: u8 = 5;
const VALUE_TYPE_DOUBLE: u8 = 6;
const VALUE_TYPE_STRING: u8 = 7;
const VALUE_TYPE_BYTE_ARRAY: u8 = 8;
const VALUE_TYPE_INT_ARRAY: u8 = 9;
const VALUE_TYPE_LONG_ARRAY: u8 = 10;
const VALUE_TYPE_FLOAT_ARRAY: u8 = 11;
const VALUE_TYPE_DOUBLE_ARRAY: u8 = 12;
const MAX_DENSE_NUMERIC_KEY: u64 = 20_000_000;
const MAX_DENSE_NUMERIC_GAP: usize = 1024;

#[derive(Debug, Clone, PartialEq)]
enum KVValue {
    Deleted,
    Bool(bool),
    Byte(u8),
    Int(i32),
    Long(u64),
    Float(f32),
    Double(f64),
    String(Cow<'static, str>),
    ByteArray(Vec<u8>),
    IntArray(Vec<i32>),
    LongArray(Vec<u64>),
    FloatArray(Vec<f32>),
    DoubleArray(Vec<f64>),
}

#[derive(Debug, Clone)]
struct KVItem {
    file_position: u64,
    id: u64,
    value_type: u8,
    value: KVValue,
}

pub struct KVBox {
    basic: BasicBox,
    string_map: FxHashMap<String, KVItem>,
    numeric_items: Vec<Option<KVItem>>,
    sparse_numeric_keys: FxHashSet<u64>,
    numeric_len: usize,
    map_file: Option<AutoIncreaseFileAccess>,
    map_file_append_position: u64,
    map_capacity_dirty: bool,
}

impl KVBox {
    pub(crate) fn open(path: PathBuf, name: String) -> Result<Self> {
        let basic = BasicBox::open(path, name)?;
        let map_file = AutoIncreaseFileAccess::open(
            basic.path().join(format!("{}-K2IdMap", basic.name())),
            4,
        )?;
        let mut box_ = Self {
            basic,
            string_map: FxHashMap::default(),
            numeric_items: Vec::new(),
            sparse_numeric_keys: FxHashSet::default(),
            numeric_len: 0,
            map_file: Some(map_file),
            map_file_append_position: 0,
            map_capacity_dirty: false,
        };
        box_.initial_map()?;
        Ok(box_)
    }

    fn map_file(&self) -> Result<&AutoIncreaseFileAccess> {
        self.map_file
            .as_ref()
            .ok_or_else(|| GuiXuError::Corrupt("kv map file is closed".to_string()))
    }

    fn map_file_mut(&mut self) -> Result<&mut AutoIncreaseFileAccess> {
        self.map_file
            .as_mut()
            .ok_or_else(|| GuiXuError::Corrupt("kv map file is closed".to_string()))
    }

    fn lookup_item(&self, key: &str) -> Option<&KVItem> {
        if let Some(numeric_key) = parse_dense_numeric_key(key) {
            self.get_numeric_item(numeric_key).or_else(|| {
                self.sparse_numeric_keys
                    .contains(&numeric_key)
                    .then(|| self.string_map.get(key))
                    .flatten()
            })
        } else {
            self.string_map.get(key)
        }
    }

    fn get_numeric_item(&self, numeric_key: u64) -> Option<&KVItem> {
        let index = usize::try_from(numeric_key).ok()?;
        self.numeric_items.get(index)?.as_ref()
    }

    fn get_numeric_item_mut(&mut self, numeric_key: u64) -> Option<&mut KVItem> {
        let index = usize::try_from(numeric_key).ok()?;
        self.numeric_items.get_mut(index)?.as_mut()
    }

    fn can_set_numeric_item(&self, numeric_key: u64) -> Result<bool> {
        let index =
            usize::try_from(numeric_key).map_err(|_| GuiXuError::FileTooLarge(numeric_key))?;
        Ok(should_store_dense_numeric(self.numeric_items.len(), index))
    }

    fn set_numeric_item(&mut self, numeric_key: u64, item: KVItem) -> Result<()> {
        let index =
            usize::try_from(numeric_key).map_err(|_| GuiXuError::FileTooLarge(numeric_key))?;
        if index == self.numeric_items.len() {
            self.numeric_items.push(Some(item));
            self.numeric_len += 1;
            return Ok(());
        }

        if index > self.numeric_items.len() {
            self.numeric_items.resize_with(index + 1, || None);
        }
        if self.numeric_items[index].is_none() {
            self.numeric_len += 1;
        }
        self.numeric_items[index] = Some(item);
        Ok(())
    }

    fn initial_map(&mut self) -> Result<()> {
        let map_file = self.map_file()?;
        let length = map_file.length();
        if length < 4 {
            return Err(GuiXuError::Corrupt(
                "kv map file is shorter than 4 bytes".to_string(),
            ));
        }

        let capacity = map_file.read_i32(0)?.max(0) as usize;
        let mut string_map = FxHashMap::default();
        string_map.reserve(capacity);
        let mut numeric_items = Vec::new();
        let mut sparse_numeric_keys = FxHashSet::default();
        let mut numeric_len = 0;
        let mut cursor = 4;

        while cursor < length {
            let file_position = cursor;
            let key_length = map_file.read_i32(cursor)? as usize;
            cursor += 4;
            let value_type = map_file.read_u8(cursor)?;
            cursor += 1;
            let id = map_file.read_u64(cursor)?;
            cursor += 8;

            let mut key_bytes = vec![0; key_length];
            map_file.read_exact_at(cursor, &mut key_bytes)?;
            cursor += key_length as u64;

            let value = if value_type == VALUE_TYPE_DELETE {
                KVValue::Deleted
            } else {
                let bytes = self.basic.get_byte(id)?;
                Self::byte_array_to_value(&bytes, value_type)?
            };

            let item = KVItem {
                file_position,
                id,
                value_type,
                value,
            };

            let numeric_key = parse_dense_numeric_key_bytes(&key_bytes);
            if let Some(numeric_key) = numeric_key {
                let index = usize::try_from(numeric_key)
                    .map_err(|_| GuiXuError::FileTooLarge(numeric_key))?;
                if should_store_dense_numeric(numeric_items.len(), index) {
                    if index >= numeric_items.len() {
                        numeric_items.resize_with(index + 1, || None);
                    }
                    if numeric_items[index].is_none() {
                        numeric_len += 1;
                    }
                    numeric_items[index] = Some(item);
                    continue;
                }
            }

            {
                let key = String::from_utf8(key_bytes)
                    .map_err(|error| GuiXuError::Corrupt(error.to_string()))?;
                if let Some(numeric_key) = numeric_key {
                    sparse_numeric_keys.insert(numeric_key);
                }
                string_map.insert(key, item);
            }
        }

        self.map_file_append_position = length;
        self.string_map = string_map;
        self.numeric_items = numeric_items;
        self.sparse_numeric_keys = sparse_numeric_keys;
        self.numeric_len = numeric_len;
        Ok(())
    }

    fn value_to_byte_array(value: &KVValue, value_type: u8) -> Result<Vec<u8>> {
        match (value_type, value) {
            (VALUE_TYPE_BOOLEAN, KVValue::Bool(value)) => Ok(vec![if *value { 1 } else { 0 }]),
            (VALUE_TYPE_BYTE, KVValue::Byte(value)) => Ok(vec![*value]),
            (VALUE_TYPE_INT, KVValue::Int(value)) => Ok(i32_to_bytes(*value).to_vec()),
            (VALUE_TYPE_LONG, KVValue::Long(value)) => Ok(u64_to_bytes(*value).to_vec()),
            (VALUE_TYPE_FLOAT, KVValue::Float(value)) => Ok(value.to_bits().to_be_bytes().to_vec()),
            (VALUE_TYPE_DOUBLE, KVValue::Double(value)) => {
                Ok(value.to_bits().to_be_bytes().to_vec())
            }
            (VALUE_TYPE_STRING, KVValue::String(value)) => Ok(value.as_bytes().to_vec()),
            (VALUE_TYPE_BYTE_ARRAY, KVValue::ByteArray(value)) => Ok(value.clone()),
            (VALUE_TYPE_INT_ARRAY, KVValue::IntArray(value)) => Ok(i32_slice_to_bytes(value)),
            (VALUE_TYPE_LONG_ARRAY, KVValue::LongArray(value)) => Ok(u64_slice_to_bytes(value)),
            (VALUE_TYPE_FLOAT_ARRAY, KVValue::FloatArray(value)) => Ok(f32_slice_to_bytes(value)),
            (VALUE_TYPE_DOUBLE_ARRAY, KVValue::DoubleArray(value)) => Ok(f64_slice_to_bytes(value)),
            _ => Err(GuiXuError::TypeError {
                stored: value.kind(),
                expected: value_type,
            }),
        }
    }

    fn byte_array_to_value(bytes: &[u8], value_type: u8) -> Result<KVValue> {
        match value_type {
            VALUE_TYPE_BOOLEAN => Ok(KVValue::Bool(bytes.first().copied() == Some(BOOLEAN_TRUE))),
            VALUE_TYPE_BYTE => Ok(KVValue::Byte(*bytes.first().unwrap_or(&0))),
            VALUE_TYPE_INT => Ok(KVValue::Int(bytes_to_i32(bytes))),
            VALUE_TYPE_LONG => Ok(KVValue::Long(bytes_to_u64(bytes))),
            VALUE_TYPE_FLOAT => Ok(KVValue::Float(f32::from_bits(bytes_to_i32(bytes) as u32))),
            VALUE_TYPE_DOUBLE => Ok(KVValue::Double(f64::from_bits(bytes_to_u64(bytes)))),
            VALUE_TYPE_STRING => Ok(KVValue::String(Cow::Owned(
                String::from_utf8(bytes.to_vec())
                    .map_err(|error| GuiXuError::Corrupt(error.to_string()))?,
            ))),
            VALUE_TYPE_BYTE_ARRAY => Ok(KVValue::ByteArray(bytes.to_vec())),
            VALUE_TYPE_INT_ARRAY => Ok(KVValue::IntArray(bytes_to_i32_vec(bytes))),
            VALUE_TYPE_LONG_ARRAY => Ok(KVValue::LongArray(bytes_to_u64_vec(bytes))),
            VALUE_TYPE_FLOAT_ARRAY => Ok(KVValue::FloatArray(bytes_to_f32_vec(bytes))),
            VALUE_TYPE_DOUBLE_ARRAY => Ok(KVValue::DoubleArray(bytes_to_f64_vec(bytes))),
            _ => Err(GuiXuError::TypeError {
                stored: value_type,
                expected: value_type,
            }),
        }
    }

    fn add_kv_item(
        &mut self,
        key: &str,
        id: u64,
        value_type: u8,
        value: KVValue,
    ) -> Result<KVItem> {
        let position = self.write_kv_item_record(key, id, value_type)?;
        Ok(KVItem {
            file_position: position,
            id,
            value_type,
            value,
        })
    }

    fn write_kv_item_record(&mut self, key: &str, id: u64, value_type: u8) -> Result<u64> {
        let key_bytes = key.as_bytes();
        let position = self.map_file_append_position;
        self.map_file_append_position += KV_ITEM_FIX_LENGTH + key_bytes.len() as u64;

        let mut buffer = Vec::with_capacity(KV_ITEM_FIX_LENGTH as usize + key_bytes.len());
        buffer.extend_from_slice(&i32_to_bytes(key_bytes.len() as i32));
        buffer.push(value_type);
        buffer.extend_from_slice(&u64_to_bytes(id));
        buffer.extend_from_slice(key_bytes);

        self.map_file_mut()?.write_all_at(position, &buffer)?;
        self.map_capacity_dirty = true;
        Ok(position)
    }

    fn update_kv_item(
        &mut self,
        file_position: u64,
        id: u64,
        old_value_type: u8,
        value_type: u8,
        value: KVValue,
    ) -> Result<KVItem> {
        if old_value_type != VALUE_TYPE_DELETE && old_value_type != value_type {
            return Err(GuiXuError::TypeError {
                stored: old_value_type,
                expected: value_type,
            });
        }
        self.map_file_mut()?
            .write_u8(file_position + 4, value_type)?;
        Ok(KVItem {
            file_position,
            id,
            value_type,
            value,
        })
    }

    fn put_data(&mut self, key: impl Into<String>, value_type: u8, value: KVValue) -> Result<()> {
        let key = key.into();
        let bytes = Self::value_to_byte_array(&value, value_type)?;
        if let Some(numeric_key) = parse_dense_numeric_key(&key) {
            return self.put_numeric_data(numeric_key, &key, value_type, value, &bytes);
        }
        self.put_string_key_data(key, value_type, value, &bytes)
    }

    fn put_numeric_data(
        &mut self,
        numeric_key: u64,
        key: &str,
        value_type: u8,
        value: KVValue,
        bytes: &[u8],
    ) -> Result<()> {
        if let Some(old) = self.get_numeric_item(numeric_key) {
            let file_position = old.file_position;
            let id = old.id;
            let old_value_type = old.value_type;
            let item = self.update_kv_item(file_position, id, old_value_type, value_type, value)?;
            self.basic.append_store(id, bytes)?;
            if let Some(old) = self.get_numeric_item_mut(numeric_key) {
                *old = item;
            }
            return Ok(());
        }

        if self.sparse_numeric_keys.contains(&numeric_key) {
            let Some(old) = self.string_map.get(key) else {
                self.sparse_numeric_keys.remove(&numeric_key);
                return self.put_numeric_data(numeric_key, key, value_type, value, bytes);
            };
            let file_position = old.file_position;
            let id = old.id;
            let old_value_type = old.value_type;
            let item = self.update_kv_item(file_position, id, old_value_type, value_type, value)?;
            self.basic.append_store(id, bytes)?;
            if let Some(old) = self.string_map.get_mut(key) {
                *old = item;
            }
            return Ok(());
        }

        let id = self.basic.check_id_and_get(0)?;
        let item = self.add_kv_item(key, id, value_type, value)?;
        self.basic.append_store(id, bytes)?;
        if self.can_set_numeric_item(numeric_key)? {
            self.set_numeric_item(numeric_key, item)?;
        } else {
            self.string_map.insert(key.to_string(), item);
            self.sparse_numeric_keys.insert(numeric_key);
        }
        Ok(())
    }

    fn put_string_key_data(
        &mut self,
        key: String,
        value_type: u8,
        value: KVValue,
        bytes: &[u8],
    ) -> Result<()> {
        if let Some(old) = self.string_map.get(&key) {
            let file_position = old.file_position;
            let id = old.id;
            let old_value_type = old.value_type;
            let item = self.update_kv_item(file_position, id, old_value_type, value_type, value)?;
            self.basic.append_store(id, bytes)?;
            if let Some(old) = self.string_map.get_mut(&key) {
                *old = item;
            }
            return Ok(());
        } else {
            let id = self.basic.check_id_and_get(0)?;
            let item = self.add_kv_item(&key, id, value_type, value)?;
            self.basic.append_store(id, bytes)?;
            self.string_map.insert(key, item);
            Ok(())
        }
    }

    fn get_data(&self, key: &str, expected_type: u8) -> Result<KVValue> {
        let item = self
            .lookup_item(key)
            .ok_or_else(|| GuiXuError::KeyNotFound(key.to_string()))?;
        if item.value_type == VALUE_TYPE_DELETE {
            return Err(GuiXuError::KeyNotFound(key.to_string()));
        }
        if item.value_type != expected_type {
            return Err(GuiXuError::TypeError {
                stored: item.value_type,
                expected: expected_type,
            });
        }
        Ok(item.value.clone())
    }

    pub fn remove(&mut self, key: &str) -> Result<()> {
        let numeric_key = parse_dense_numeric_key(key);
        let Some((file_position, id, is_dense_numeric)) = (if let Some(numeric_key) = numeric_key {
            if let Some(item) = self.get_numeric_item(numeric_key) {
                Some((item.file_position, item.id, true))
            } else if self.sparse_numeric_keys.contains(&numeric_key) {
                self.string_map
                    .get(key)
                    .map(|item| (item.file_position, item.id, false))
            } else {
                None
            }
        } else {
            self.string_map
                .get(key)
                .map(|item| (item.file_position, item.id, false))
        }) else {
            return Ok(());
        };

        self.basic.remove_entry(id)?;
        self.map_file_mut()?
            .write_u8(file_position + 4, VALUE_TYPE_DELETE)?;
        let item_slot = if is_dense_numeric {
            let numeric_key = numeric_key.expect("dense numeric item must have a numeric key");
            self.get_numeric_item_mut(numeric_key)
        } else {
            self.string_map.get_mut(key)
        };
        if let Some(item) = item_slot {
            *item = KVItem {
                file_position,
                id,
                value_type: VALUE_TYPE_DELETE,
                value: KVValue::Deleted,
            };
        }
        Ok(())
    }

    pub fn put_bool(&mut self, key: impl Into<String>, data: bool) -> Result<()> {
        self.put_data(key, VALUE_TYPE_BOOLEAN, KVValue::Bool(data))
    }

    pub fn put_byte(&mut self, key: impl Into<String>, data: u8) -> Result<()> {
        self.put_data(key, VALUE_TYPE_BYTE, KVValue::Byte(data))
    }

    pub fn put_int(&mut self, key: impl Into<String>, data: i32) -> Result<()> {
        self.put_data(key, VALUE_TYPE_INT, KVValue::Int(data))
    }

    pub fn put_long(&mut self, key: impl Into<String>, data: u64) -> Result<()> {
        self.put_data(key, VALUE_TYPE_LONG, KVValue::Long(data))
    }

    pub fn put_float(&mut self, key: impl Into<String>, data: f32) -> Result<()> {
        self.put_data(key, VALUE_TYPE_FLOAT, KVValue::Float(data))
    }

    pub fn put_double(&mut self, key: impl Into<String>, data: f64) -> Result<()> {
        self.put_data(key, VALUE_TYPE_DOUBLE, KVValue::Double(data))
    }

    pub fn put_string(
        &mut self,
        key: impl Into<String>,
        data: impl Into<Cow<'static, str>>,
    ) -> Result<()> {
        let key = key.into();
        let value = data.into();
        if let Some(numeric_key) = parse_dense_numeric_key(&key) {
            if let Some(old) = self.get_numeric_item(numeric_key) {
                let file_position = old.file_position;
                let id = old.id;
                let old_value_type = old.value_type;
                if old_value_type != VALUE_TYPE_DELETE && old_value_type != VALUE_TYPE_STRING {
                    return Err(GuiXuError::TypeError {
                        stored: old_value_type,
                        expected: VALUE_TYPE_STRING,
                    });
                }
                self.map_file_mut()?
                    .write_u8(file_position + 4, VALUE_TYPE_STRING)?;
                self.basic.append_store(id, value.as_bytes())?;
                if let Some(old) = self.get_numeric_item_mut(numeric_key) {
                    *old = KVItem {
                        file_position,
                        id,
                        value_type: VALUE_TYPE_STRING,
                        value: KVValue::String(value),
                    };
                }
                return Ok(());
            }

            if self.sparse_numeric_keys.contains(&numeric_key) {
                let Some(old) = self.string_map.get(&key) else {
                    self.sparse_numeric_keys.remove(&numeric_key);
                    return self.put_string(key, value);
                };
                let file_position = old.file_position;
                let id = old.id;
                let old_value_type = old.value_type;
                if old_value_type != VALUE_TYPE_DELETE && old_value_type != VALUE_TYPE_STRING {
                    return Err(GuiXuError::TypeError {
                        stored: old_value_type,
                        expected: VALUE_TYPE_STRING,
                    });
                }
                self.map_file_mut()?
                    .write_u8(file_position + 4, VALUE_TYPE_STRING)?;
                self.basic.append_store(id, value.as_bytes())?;
                if let Some(old) = self.string_map.get_mut(&key) {
                    *old = KVItem {
                        file_position,
                        id,
                        value_type: VALUE_TYPE_STRING,
                        value: KVValue::String(value),
                    };
                }
                return Ok(());
            }

            let id = self.basic.check_id_and_get(0)?;
            let file_position = self.write_kv_item_record(&key, id, VALUE_TYPE_STRING)?;
            self.basic.append_store(id, value.as_bytes())?;
            let item = KVItem {
                file_position,
                id,
                value_type: VALUE_TYPE_STRING,
                value: KVValue::String(value),
            };
            if self.can_set_numeric_item(numeric_key)? {
                self.set_numeric_item(numeric_key, item)?;
            } else {
                self.sparse_numeric_keys.insert(numeric_key);
                self.string_map.insert(key, item);
            }
            return Ok(());
        }

        if let Some(old) = self.string_map.get(&key) {
            let file_position = old.file_position;
            let id = old.id;
            let old_value_type = old.value_type;
            if old_value_type != VALUE_TYPE_DELETE && old_value_type != VALUE_TYPE_STRING {
                return Err(GuiXuError::TypeError {
                    stored: old_value_type,
                    expected: VALUE_TYPE_STRING,
                });
            }
            self.map_file_mut()?
                .write_u8(file_position + 4, VALUE_TYPE_STRING)?;
            self.basic.append_store(id, value.as_bytes())?;
            if let Some(old) = self.string_map.get_mut(&key) {
                *old = KVItem {
                    file_position,
                    id,
                    value_type: VALUE_TYPE_STRING,
                    value: KVValue::String(value),
                };
            }
            return Ok(());
        }

        let id = self.basic.check_id_and_get(0)?;
        let file_position = self.write_kv_item_record(&key, id, VALUE_TYPE_STRING)?;
        self.basic.append_store(id, value.as_bytes())?;
        self.string_map.insert(
            key,
            KVItem {
                file_position,
                id,
                value_type: VALUE_TYPE_STRING,
                value: KVValue::String(value),
            },
        );
        Ok(())
    }

    pub fn put_byte_array(&mut self, key: impl Into<String>, data: Vec<u8>) -> Result<()> {
        self.put_data(key, VALUE_TYPE_BYTE_ARRAY, KVValue::ByteArray(data))
    }

    pub fn put_int_array(&mut self, key: impl Into<String>, data: Vec<i32>) -> Result<()> {
        self.put_data(key, VALUE_TYPE_INT_ARRAY, KVValue::IntArray(data))
    }

    pub fn put_long_array(&mut self, key: impl Into<String>, data: Vec<u64>) -> Result<()> {
        self.put_data(key, VALUE_TYPE_LONG_ARRAY, KVValue::LongArray(data))
    }

    pub fn put_float_array(&mut self, key: impl Into<String>, data: Vec<f32>) -> Result<()> {
        self.put_data(key, VALUE_TYPE_FLOAT_ARRAY, KVValue::FloatArray(data))
    }

    pub fn put_double_array(&mut self, key: impl Into<String>, data: Vec<f64>) -> Result<()> {
        self.put_data(key, VALUE_TYPE_DOUBLE_ARRAY, KVValue::DoubleArray(data))
    }

    pub fn get_bool(&self, key: &str) -> Result<bool> {
        match self.get_data(key, VALUE_TYPE_BOOLEAN)? {
            KVValue::Bool(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_BOOLEAN)),
        }
    }

    pub fn get_byte(&self, key: &str) -> Result<u8> {
        match self.get_data(key, VALUE_TYPE_BYTE)? {
            KVValue::Byte(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_BYTE)),
        }
    }

    pub fn get_int(&self, key: &str) -> Result<i32> {
        match self.get_data(key, VALUE_TYPE_INT)? {
            KVValue::Int(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_INT)),
        }
    }

    pub fn get_long(&self, key: &str) -> Result<u64> {
        match self.get_data(key, VALUE_TYPE_LONG)? {
            KVValue::Long(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_LONG)),
        }
    }

    pub fn get_float(&self, key: &str) -> Result<f32> {
        match self.get_data(key, VALUE_TYPE_FLOAT)? {
            KVValue::Float(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_FLOAT)),
        }
    }

    pub fn get_double(&self, key: &str) -> Result<f64> {
        match self.get_data(key, VALUE_TYPE_DOUBLE)? {
            KVValue::Double(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_DOUBLE)),
        }
    }

    pub fn get_string(&self, key: &str) -> Result<&str> {
        let item = self
            .lookup_item(key)
            .ok_or_else(|| GuiXuError::KeyNotFound(key.to_string()))?;
        if item.value_type == VALUE_TYPE_DELETE {
            return Err(GuiXuError::KeyNotFound(key.to_string()));
        }
        if item.value_type != VALUE_TYPE_STRING {
            return Err(GuiXuError::TypeError {
                stored: item.value_type,
                expected: VALUE_TYPE_STRING,
            });
        }
        match &item.value {
            KVValue::String(value) => Ok(value.as_ref()),
            value => Err(type_error(value.clone(), VALUE_TYPE_STRING)),
        }
    }

    pub fn get_byte_array(&self, key: &str) -> Result<Vec<u8>> {
        match self.get_data(key, VALUE_TYPE_BYTE_ARRAY)? {
            KVValue::ByteArray(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_BYTE_ARRAY)),
        }
    }

    pub fn get_int_array(&self, key: &str) -> Result<Vec<i32>> {
        match self.get_data(key, VALUE_TYPE_INT_ARRAY)? {
            KVValue::IntArray(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_INT_ARRAY)),
        }
    }

    pub fn get_long_array(&self, key: &str) -> Result<Vec<u64>> {
        match self.get_data(key, VALUE_TYPE_LONG_ARRAY)? {
            KVValue::LongArray(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_LONG_ARRAY)),
        }
    }

    pub fn get_float_array(&self, key: &str) -> Result<Vec<f32>> {
        match self.get_data(key, VALUE_TYPE_FLOAT_ARRAY)? {
            KVValue::FloatArray(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_FLOAT_ARRAY)),
        }
    }

    pub fn get_double_array(&self, key: &str) -> Result<Vec<f64>> {
        match self.get_data(key, VALUE_TYPE_DOUBLE_ARRAY)? {
            KVValue::DoubleArray(value) => Ok(value),
            value => Err(type_error(value, VALUE_TYPE_DOUBLE_ARRAY)),
        }
    }

    pub fn clear(&mut self, re_init: bool) -> Result<()> {
        let map_file = self.map_file.take();
        let map_path = map_file.as_ref().map(|file| file.path().to_path_buf());
        if let Some(map_file) = map_file {
            map_file.flush()?;
        }
        self.basic.clear(re_init)?;
        if let Some(map_path) = map_path {
            let _ = remove_file(map_path);
        }
        self.string_map.clear();
        self.numeric_items.clear();
        self.sparse_numeric_keys.clear();
        self.numeric_len = 0;
        self.map_file_append_position = 0;
        self.map_capacity_dirty = false;

        if re_init {
            let map_file = AutoIncreaseFileAccess::open(
                self.basic
                    .path()
                    .join(format!("{}-K2IdMap", self.basic.name())),
                4,
            )?;
            self.map_file = Some(map_file);
            self.initial_map()?;
        }
        Ok(())
    }

    pub fn compact(&mut self) -> Result<()> {
        self.basic.compact()
    }

    pub fn close(&mut self) -> Result<()> {
        if self.map_capacity_dirty {
            let len = self.string_map.len() + self.numeric_len;
            if let Some(map_file) = self.map_file.as_mut() {
                map_file.write_i32(0, (len as i32) << 1)?;
            }
            self.map_capacity_dirty = false;
        }
        if let Some(map_file) = self.map_file.as_mut() {
            map_file.flush()?;
        }
        self.basic.close()
    }

    pub fn get_info(&self) -> BoxInfo {
        let mut info = self.basic.get_info();
        if let Some(map_file) = self.map_file.as_ref() {
            info.index_size += map_file.file_size();
        }
        info
    }
}

impl KVValue {
    fn kind(&self) -> u8 {
        match self {
            KVValue::Deleted => VALUE_TYPE_DELETE,
            KVValue::Bool(_) => VALUE_TYPE_BOOLEAN,
            KVValue::Byte(_) => VALUE_TYPE_BYTE,
            KVValue::Int(_) => VALUE_TYPE_INT,
            KVValue::Long(_) => VALUE_TYPE_LONG,
            KVValue::Float(_) => VALUE_TYPE_FLOAT,
            KVValue::Double(_) => VALUE_TYPE_DOUBLE,
            KVValue::String(_) => VALUE_TYPE_STRING,
            KVValue::ByteArray(_) => VALUE_TYPE_BYTE_ARRAY,
            KVValue::IntArray(_) => VALUE_TYPE_INT_ARRAY,
            KVValue::LongArray(_) => VALUE_TYPE_LONG_ARRAY,
            KVValue::FloatArray(_) => VALUE_TYPE_FLOAT_ARRAY,
            KVValue::DoubleArray(_) => VALUE_TYPE_DOUBLE_ARRAY,
        }
    }
}

fn type_error(value: KVValue, expected: u8) -> GuiXuError {
    GuiXuError::TypeError {
        stored: value.kind(),
        expected,
    }
}

fn parse_dense_numeric_key(key: &str) -> Option<u64> {
    parse_dense_numeric_key_bytes(key.as_bytes())
}

fn parse_dense_numeric_key_bytes(bytes: &[u8]) -> Option<u64> {
    if bytes.is_empty() || (bytes.len() > 1 && bytes[0] == b'0') {
        return None;
    }

    let mut value = 0_u64;
    for byte in bytes {
        if !byte.is_ascii_digit() {
            return None;
        }
        value = value.checked_mul(10)?.checked_add(u64::from(byte - b'0'))?;
    }
    if value <= MAX_DENSE_NUMERIC_KEY {
        Some(value)
    } else {
        None
    }
}

fn should_store_dense_numeric(current_len: usize, index: usize) -> bool {
    index <= current_len || index.saturating_sub(current_len) <= MAX_DENSE_NUMERIC_GAP
}
