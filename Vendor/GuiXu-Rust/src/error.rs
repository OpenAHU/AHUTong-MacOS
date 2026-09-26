// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

use thiserror::Error;

pub type Result<T> = std::result::Result<T, GuiXuError>;

#[derive(Debug, Error)]
pub enum GuiXuError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("item id:{0} do not exist")]
    EntryNotFound(u64),
    #[error("id >= next_id id:{id}, next_id:{next_id}")]
    IllegalId { id: u64, next_id: u64 },
    #[error("key:{0}")]
    KeyNotFound(String),
    #[error("stored type:{stored}, expected type:{expected}")]
    TypeError { stored: u8, expected: u8 },
    #[error("serialization error: {0}")]
    Serialization(String),
    #[error("file is too large to map on this platform: {0} bytes")]
    FileTooLarge(u64),
    #[error("corrupt store: {0}")]
    Corrupt(String),
}
