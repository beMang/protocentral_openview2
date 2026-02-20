/// Pure utility functions for reading little-endian integers from byte lists.

/// Read a 16-bit signed integer (little-endian) from [data] at [offset].
int readInt16LE(List<int> data, int offset) {
  return (data[offset] | (data[offset + 1] << 8)).toSigned(16);
}

/// Read a 16-bit unsigned integer (little-endian) from [data] at [offset].
int readUint16LE(List<int> data, int offset) {
  return data[offset] | (data[offset + 1] << 8);
}

/// Read a 32-bit signed integer (little-endian) from [data] at [offset].
int readInt32LE(List<int> data, int offset) {
  return (data[offset] |
          data[offset + 1] << 8 |
          data[offset + 2] << 16 |
          data[offset + 3] << 24)
      .toSigned(32);
}

/// Read a 32-bit unsigned integer (little-endian) from [data] at [offset].
int readUint32LE(List<int> data, int offset) {
  return (data[offset] |
          data[offset + 1] << 8 |
          data[offset + 2] << 16 |
          data[offset + 3] << 24)
      .toUnsigned(32);
}

/// Sign-extend a 16-bit value using arithmetic shift.
/// Matches the existing `value <<= 16; value >>= 16` pattern.
int signExtend16(int value) {
  return (value << 16) >> 16;
}
