// Derived from Delsart/GuiXu, originally licensed under Apache-2.0.
// Rewritten in Rust and modified by GuiXu Rust contributors.
// SPDX-License-Identifier: Apache-2.0

pub(crate) fn i32_to_bytes(value: i32) -> [u8; 4] {
    value.to_be_bytes()
}

pub(crate) fn u64_to_bytes(value: u64) -> [u8; 8] {
    value.to_be_bytes()
}

pub(crate) fn bytes_to_i32(bytes: &[u8]) -> i32 {
    i32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

pub(crate) fn bytes_to_u64(bytes: &[u8]) -> u64 {
    u64::from_be_bytes([
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
    ])
}

pub(crate) fn i32_slice_to_bytes(values: &[i32]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_be_bytes())
        .collect()
}

pub(crate) fn u64_slice_to_bytes(values: &[u64]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_be_bytes())
        .collect()
}

pub(crate) fn f32_slice_to_bytes(values: &[f32]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_bits().to_be_bytes())
        .collect()
}

pub(crate) fn f64_slice_to_bytes(values: &[f64]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|value| value.to_bits().to_be_bytes())
        .collect()
}

pub(crate) fn bytes_to_i32_vec(bytes: &[u8]) -> Vec<i32> {
    bytes.chunks_exact(4).map(bytes_to_i32).collect()
}

pub(crate) fn bytes_to_u64_vec(bytes: &[u8]) -> Vec<u64> {
    bytes.chunks_exact(8).map(bytes_to_u64).collect()
}

pub(crate) fn bytes_to_f32_vec(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks_exact(4)
        .map(bytes_to_i32)
        .map(|value| f32::from_bits(value as u32))
        .collect()
}

pub(crate) fn bytes_to_f64_vec(bytes: &[u8]) -> Vec<f64> {
    bytes
        .chunks_exact(8)
        .map(bytes_to_u64)
        .map(f64::from_bits)
        .collect()
}
