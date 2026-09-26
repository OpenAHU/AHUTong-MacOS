// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use crate::byte_ops::{bytes_to_i32, bytes_to_u64, i32_to_bytes, u64_to_bytes};
use crate::error::{GuiXuError, Result};
use memmap2::{MmapMut, MmapOptions};
use std::fs::{create_dir_all, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

const MAX_INCREASE_SIZE: u64 = 1 << 24;

fn ensure_parent(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent)?;
    }
    Ok(())
}

fn to_usize(value: u64) -> Result<usize> {
    usize::try_from(value).map_err(|_| GuiXuError::FileTooLarge(value))
}

pub(crate) struct AutoIncreaseFileAccess {
    path: PathBuf,
    inner: AutoInner,
}

struct AutoInner {
    file: File,
    mmap: MmapMut,
    file_size: u64,
    actual_length: u64,
}

impl AutoIncreaseFileAccess {
    pub(crate) fn open(path: impl Into<PathBuf>, initial_size: u64) -> Result<Self> {
        let path = path.into();
        ensure_parent(&path)?;
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(&path)?;

        let mut file_size = file.metadata()?.len();
        if file_size < 8 {
            file_size = initial_size + 8;
            file.set_len(file_size)?;
            let mut mmap = unsafe {
                MmapOptions::new()
                    .len(to_usize(file_size)?)
                    .map_mut(&file)?
            };
            let footer = to_usize(file_size - 8)?;
            mmap[footer..footer + 8].copy_from_slice(&u64_to_bytes(initial_size));
            mmap.flush()?;
            return Ok(Self {
                path,
                inner: AutoInner {
                    file,
                    mmap,
                    file_size,
                    actual_length: initial_size,
                },
            });
        }

        let mmap = unsafe {
            MmapOptions::new()
                .len(to_usize(file_size)?)
                .map_mut(&file)?
        };
        let footer = to_usize(file_size - 8)?;
        let actual_length = bytes_to_u64(&mmap[footer..footer + 8]);

        Ok(Self {
            path,
            inner: AutoInner {
                file,
                mmap,
                file_size,
                actual_length,
            },
        })
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn length(&self) -> u64 {
        self.inner.actual_length
    }

    pub(crate) fn file_size(&self) -> u64 {
        self.inner.file_size
    }

    pub(crate) fn read_exact_at(&self, position: u64, dst: &mut [u8]) -> Result<()> {
        let start = to_usize(position)?;
        let end = start + dst.len();
        if end > to_usize(self.inner.actual_length)? {
            return Err(GuiXuError::Corrupt(format!(
                "read beyond logical file length at {position}"
            )));
        }
        dst.copy_from_slice(&self.inner.mmap[start..end]);
        Ok(())
    }

    pub(crate) fn write_all_at(&mut self, position: u64, source: &[u8]) -> Result<()> {
        let new_length = position + source.len() as u64;
        self.inner.update_length(new_length)?;
        let start = to_usize(position)?;
        let end = start + source.len();
        self.inner.mmap[start..end].copy_from_slice(source);
        Ok(())
    }

    pub(crate) fn read_i32(&self, position: u64) -> Result<i32> {
        let mut buffer = [0; 4];
        self.read_exact_at(position, &mut buffer)?;
        Ok(bytes_to_i32(&buffer))
    }

    pub(crate) fn write_i32(&mut self, position: u64, value: i32) -> Result<()> {
        self.write_all_at(position, &i32_to_bytes(value))
    }

    pub(crate) fn read_u64(&self, position: u64) -> Result<u64> {
        let mut buffer = [0; 8];
        self.read_exact_at(position, &mut buffer)?;
        Ok(bytes_to_u64(&buffer))
    }

    pub(crate) fn write_u64(&mut self, position: u64, value: u64) -> Result<()> {
        self.write_all_at(position, &u64_to_bytes(value))
    }

    pub(crate) fn read_u8(&self, position: u64) -> Result<u8> {
        let mut buffer = [0; 1];
        self.read_exact_at(position, &mut buffer)?;
        Ok(buffer[0])
    }

    pub(crate) fn write_u8(&mut self, position: u64, value: u8) -> Result<()> {
        self.write_all_at(position, &[value])
    }

    pub(crate) fn flush(&self) -> Result<()> {
        self.inner.mmap.flush()?;
        Ok(())
    }
}

impl AutoInner {
    fn update_length(&mut self, new_length: u64) -> Result<()> {
        if new_length <= self.actual_length {
            return Ok(());
        }

        if new_length >= self.file_size.saturating_sub(8) {
            let grown = new_length.saturating_mul(8);
            let capped = new_length.saturating_add(MAX_INCREASE_SIZE);
            let new_size = grown.min(capped).max(new_length + 8);
            self.resize(new_size)?;
        }

        self.actual_length = new_length;
        let footer = to_usize(self.file_size - 8)?;
        self.mmap[footer..footer + 8].copy_from_slice(&u64_to_bytes(self.actual_length));
        Ok(())
    }

    fn resize(&mut self, new_size: u64) -> Result<()> {
        self.mmap.flush()?;
        self.file.set_len(new_size)?;
        self.mmap = unsafe {
            MmapOptions::new()
                .len(to_usize(new_size)?)
                .map_mut(&self.file)?
        };
        self.file_size = new_size;
        Ok(())
    }
}

pub(crate) struct FixSizeFileAccess {
    path: PathBuf,
    size: u64,
    file: File,
}

impl FixSizeFileAccess {
    pub(crate) fn open(path: impl Into<PathBuf>, size: u64) -> Result<Self> {
        let path = path.into();
        ensure_parent(&path)?;
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(&path)?;
        file.set_len(size)?;
        Ok(Self { path, size, file })
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn read_exact_at(&mut self, position: u64, dst: &mut [u8]) -> Result<()> {
        self.file.seek(SeekFrom::Start(position))?;
        self.file.read_exact(dst)?;
        Ok(())
    }

    pub(crate) fn write_all_at(&mut self, position: u64, source: &[u8]) -> Result<()> {
        self.file.seek(SeekFrom::Start(position))?;
        self.file.write_all(source)?;
        Ok(())
    }

    pub(crate) fn flush(&mut self) -> Result<()> {
        self.file.flush()?;
        Ok(())
    }

    #[allow(dead_code)]
    pub(crate) fn length(&self) -> u64 {
        self.size
    }
}
