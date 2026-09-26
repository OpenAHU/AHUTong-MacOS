// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use crate::byte_ops::{bytes_to_i32, bytes_to_u64, i32_to_bytes, u64_to_bytes};
use crate::error::{GuiXuError, Result};
use crate::file_access::{AutoIncreaseFileAccess, FixSizeFileAccess};
use std::fs::{remove_file, rename};
use std::path::{Path, PathBuf};

pub(crate) const INDEX_ITEM_LENGTH: u64 = 12;
pub(crate) const DELETE_FLAG: i32 = -2_147_483_647;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BoxInfo {
    pub data_size: u64,
    pub index_size: u64,
}

pub(crate) struct FileItem {
    pub(crate) index_file: AutoIncreaseFileAccess,
    pub(crate) store_file: AutoIncreaseFileAccess,
    pub(crate) store_append_position: u64,
}

impl FileItem {
    fn open(index_path: PathBuf, index_initial_size: u64, store_path: PathBuf) -> Result<Self> {
        let index_file = AutoIncreaseFileAccess::open(index_path, index_initial_size)?;
        let store_file = AutoIncreaseFileAccess::open(store_path, 0)?;
        let append_position = store_file.length();
        Ok(Self {
            index_file,
            store_file,
            store_append_position: append_position,
        })
    }
}

pub struct BasicBox {
    path: PathBuf,
    name: String,
    meta_data_file: Option<FixSizeFileAccess>,
    file_array: Vec<FileItem>,
    next_id: u64,
    in_compact_replace_file: bool,
}

impl BasicBox {
    pub(crate) fn open(path: impl Into<PathBuf>, name: impl Into<String>) -> Result<Self> {
        let mut box_ = Self {
            path: path.into(),
            name: name.into(),
            meta_data_file: None,
            file_array: Vec::new(),
            next_id: 1,
            in_compact_replace_file: false,
        };
        box_.initial_meta_data()?;
        Ok(box_)
    }

    fn initial_meta_data(&mut self) -> Result<()> {
        let meta_path = self.path.join(&self.name);
        let mut meta_data_file = FixSizeFileAccess::open(meta_path, 2)?;
        let mut buffer = [0; 2];
        meta_data_file.read_exact_at(0, &mut buffer)?;

        let (working_file_num, file_count) = if buffer[1] > 0 {
            (usize::from(buffer[0]), usize::from(buffer[1]).min(2))
        } else {
            buffer = [0, 1];
            meta_data_file.write_all_at(0, &buffer)?;
            (0, 1)
        };

        let mut files = Vec::with_capacity(file_count);
        for index in 0..file_count {
            let file_num = (working_file_num + 3 - index) % 3;
            files.push(FileItem::open(
                self.path.join(format!("{}-index-{file_num}", self.name)),
                INDEX_ITEM_LENGTH,
                self.path.join(format!("{}-{file_num}", self.name)),
            )?);
        }

        let next_id = (files[0].index_file.length() / INDEX_ITEM_LENGTH).max(1);
        self.next_id = next_id;
        self.meta_data_file = Some(meta_data_file);
        self.file_array = files;
        Ok(())
    }

    pub(crate) fn check_id_and_get(&mut self, id: u64) -> Result<u64> {
        if id == 0 {
            let id = self.next_id;
            self.next_id += 1;
            return Ok(id);
        }

        let local_next_id = self.next_id;
        if id >= local_next_id {
            return Err(GuiXuError::IllegalId {
                id,
                next_id: local_next_id,
            });
        }
        Ok(id)
    }

    pub(crate) fn append_store(&mut self, id: u64, load: &[u8]) -> Result<()> {
        let file_item = self
            .file_array
            .first_mut()
            .ok_or_else(|| GuiXuError::Corrupt("box is not initialized".to_string()))?;
        let length = i32::try_from(load.len())
            .map_err(|_| GuiXuError::Corrupt("entry is larger than i32::MAX".to_string()))?;
        let position = file_item.store_append_position;
        file_item.store_append_position += load.len() as u64;
        Self::set_index(&mut file_item.index_file, id, position, length)?;
        file_item.store_file.write_all_at(position, load)
    }

    pub(crate) fn get_byte(&self, id: u64) -> Result<Vec<u8>> {
        for file_item in &self.file_array {
            let index_position = id * INDEX_ITEM_LENGTH;
            if index_position + INDEX_ITEM_LENGTH > file_item.index_file.length() {
                continue;
            }

            let mut index_buffer = [0; INDEX_ITEM_LENGTH as usize];
            file_item
                .index_file
                .read_exact_at(index_position, &mut index_buffer)?;
            let length = bytes_to_i32(&index_buffer[8..]);
            if length == 0 {
                continue;
            }
            if length < 0 {
                return Err(GuiXuError::EntryNotFound(id));
            }

            let position = bytes_to_u64(&index_buffer[..8]);
            let mut buffer = vec![0; length as usize];
            file_item.store_file.read_exact_at(position, &mut buffer)?;
            return Ok(buffer);
        }

        Err(GuiXuError::EntryNotFound(id))
    }

    pub(crate) fn all_bytes(&self) -> Result<Vec<Vec<u8>>> {
        let max_id = self
            .file_array
            .first()
            .map(|file_item| file_item.index_file.length() / INDEX_ITEM_LENGTH)
            .unwrap_or(1);

        let mut result = Vec::new();
        for id in 1..max_id {
            if let Ok(bytes) = self.get_byte(id) {
                result.push(bytes);
            }
        }
        Ok(result)
    }

    pub(crate) fn remove_entry(&mut self, id: u64) -> Result<()> {
        let file_item = self
            .file_array
            .first_mut()
            .ok_or_else(|| GuiXuError::Corrupt("box is not initialized".to_string()))?;
        Self::set_index(&mut file_item.index_file, id, 0, DELETE_FLAG)
    }

    pub fn compact(&mut self) -> Result<()> {
        let old_files = std::mem::take(&mut self.file_array);
        if old_files.is_empty() {
            return Ok(());
        }

        let mut meta_buffer = [0; 2];
        {
            let meta = self
                .meta_data_file
                .as_mut()
                .ok_or_else(|| GuiXuError::Corrupt("metadata file is closed".to_string()))?;
            meta.read_exact_at(0, &mut meta_buffer)?;
        }

        let working_file_num = (usize::from(meta_buffer[0]) + 1) % 3;
        let output_store_path = self.path.join(format!("{}-temp", self.name));
        let output_index_path = self.path.join(format!("{}-index-temp", self.name));
        let mut output_store = AutoIncreaseFileAccess::open(&output_store_path, 0)?;
        let mut output_index =
            AutoIncreaseFileAccess::open(&output_index_path, old_files[0].index_file.length())?;

        self.merge_file(&mut output_store, &mut output_index, &old_files)?;
        output_store.flush()?;
        output_index.flush()?;

        let active_store_path = old_files[0].store_file.path().to_path_buf();
        let active_index_path = old_files[0].index_file.path().to_path_buf();
        let old_paths: Vec<(PathBuf, PathBuf)> = old_files
            .iter()
            .map(|item| {
                (
                    item.store_file.path().to_path_buf(),
                    item.index_file.path().to_path_buf(),
                )
            })
            .collect();

        self.in_compact_replace_file = true;

        replace_file(&output_store_path, &active_store_path)?;
        replace_file(&output_index_path, &active_index_path)?;

        let working = FileItem::open(
            self.path
                .join(format!("{}-index-{working_file_num}", self.name)),
            INDEX_ITEM_LENGTH,
            self.path.join(format!("{}-{working_file_num}", self.name)),
        )?;
        let compacted = FileItem::open(active_index_path.clone(), 0, active_store_path.clone())?;
        self.file_array = vec![working, compacted];
        self.in_compact_replace_file = false;

        for (store_path, index_path) in old_paths.into_iter().skip(1) {
            let _ = remove_file(store_path);
            let _ = remove_file(index_path);
        }

        meta_buffer[0] = working_file_num as u8;
        meta_buffer[1] = meta_buffer[1].saturating_add(1).min(2);
        let meta = self
            .meta_data_file
            .as_mut()
            .ok_or_else(|| GuiXuError::Corrupt("metadata file is closed".to_string()))?;
        meta.write_all_at(0, &meta_buffer)?;
        Ok(())
    }

    fn merge_file(
        &self,
        output_store: &mut AutoIncreaseFileAccess,
        output_index: &mut AutoIncreaseFileAccess,
        merge_files: &[FileItem],
    ) -> Result<()> {
        let Some(first_file) = merge_files.first() else {
            return Ok(());
        };

        let max_id = first_file.index_file.length() / INDEX_ITEM_LENGTH;
        let mut new_position = 0;
        for id in 0..max_id {
            let index_position = id * INDEX_ITEM_LENGTH;
            let mut selected: Option<(&FileItem, i32)> = None;

            for file_item in merge_files {
                if index_position + INDEX_ITEM_LENGTH > file_item.index_file.length() {
                    continue;
                }
                let length = file_item.index_file.read_i32(index_position + 8)?;
                if length > 0 {
                    selected = Some((file_item, length));
                    break;
                }
                if length < 0 {
                    break;
                }
            }

            let Some((file_item, length)) = selected else {
                output_index.write_all_at(index_position, &[0; INDEX_ITEM_LENGTH as usize])?;
                continue;
            };

            let old_position = file_item.index_file.read_u64(index_position)?;
            let mut buffer = vec![0; length as usize];
            file_item
                .store_file
                .read_exact_at(old_position, &mut buffer)?;
            output_store.write_all_at(new_position, &buffer)?;
            output_index.write_u64(index_position, new_position)?;
            output_index.write_i32(index_position + 8, length)?;
            new_position += length as u64;
        }
        Ok(())
    }

    fn set_index(
        file: &mut AutoIncreaseFileAccess,
        id: u64,
        position: u64,
        length: i32,
    ) -> Result<()> {
        let file_position = id * INDEX_ITEM_LENGTH;
        let mut buffer = [0; INDEX_ITEM_LENGTH as usize];
        buffer[..8].copy_from_slice(&u64_to_bytes(position));
        buffer[8..].copy_from_slice(&i32_to_bytes(length));
        file.write_all_at(file_position, &buffer)
    }

    pub fn clear(&mut self, re_init: bool) -> Result<()> {
        let meta_file = self.meta_data_file.take();
        if let Some(meta_file) = meta_file {
            let mut meta_file = meta_file;
            meta_file.flush()?;
            let _ = remove_file(meta_file.path());
        }

        let old_files = std::mem::take(&mut self.file_array);
        let old_paths: Vec<(PathBuf, PathBuf)> = old_files
            .iter()
            .map(|item| {
                let _ = item.index_file.flush();
                let _ = item.store_file.flush();
                (
                    item.index_file.path().to_path_buf(),
                    item.store_file.path().to_path_buf(),
                )
            })
            .collect();
        drop(old_files);

        for (index_path, store_path) in old_paths {
            let _ = remove_file(index_path);
            let _ = remove_file(store_path);
        }

        if re_init {
            self.initial_meta_data()?;
        }
        Ok(())
    }

    pub fn close(&mut self) -> Result<()> {
        if let Some(meta) = self.meta_data_file.as_mut() {
            meta.flush()?;
        }
        for file in self.file_array.iter() {
            file.index_file.flush()?;
            file.store_file.flush()?;
        }
        Ok(())
    }

    pub fn get_info(&self) -> BoxInfo {
        let mut data_size = 0;
        let mut index_size = 0;
        for item in self.file_array.iter() {
            data_size += item.store_file.file_size();
            index_size += item.index_file.file_size();
        }
        BoxInfo {
            data_size,
            index_size,
        }
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn name(&self) -> &str {
        &self.name
    }
}

fn replace_file(from: &Path, to: &Path) -> Result<()> {
    let _ = remove_file(to);
    rename(from, to)?;
    Ok(())
}
