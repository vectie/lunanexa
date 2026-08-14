///|
suberror FontInspectError {
  InvalidFont(String)
} derive(Debug)

///|
fn u16_be(data : Bytes, offset : Int) -> Int raise FontInspectError {
  if offset < 0 || offset + 2 > data.length() {
    raise InvalidFont("truncated UInt16")
  }
  data[offset].to_int() * 256 + data[offset + 1].to_int()
}

///|
fn u32_be(data : Bytes, offset : Int) -> Int raise FontInspectError {
  if offset < 0 || offset + 4 > data.length() {
    raise InvalidFont("truncated UInt32")
  }
  data[offset].to_int() * 16777216 +
  data[offset + 1].to_int() * 65536 +
  data[offset + 2].to_int() * 256 +
  data[offset + 3].to_int()
}

///|
fn table_offset(data : Bytes, name : String) -> Int? raise FontInspectError {
  if data.length() < 12 {
    raise InvalidFont("truncated sfnt header")
  }
  if data[0] == b't' && data[1] == b't' && data[2] == b'c' && data[3] == b'f' {
    raise InvalidFont(
      "font collections are not accepted; provide one licensed face",
    )
  }
  let count = u16_be(data, 4)
  for index in 0..<count {
    let record = 12 + index * 16
    if record + 16 > data.length() {
      raise InvalidFont("truncated table directory")
    }
    let tag = @ascii.decode_lossy(data[record:record + 4])
    if tag == name {
      return Some(u32_be(data, record + 8))
    }
  }
  None
}

///|
fn font_names(data : Bytes) -> Array[String] raise FontInspectError {
  let offset = table_offset(data, "name").unwrap_or_else(() => {
    raise InvalidFont("missing name table")
  })
  let count = u16_be(data, offset + 2)
  let storage = offset + u16_be(data, offset + 4)
  let names : Array[String] = []
  for index in 0..<count {
    let record = offset + 6 + index * 12
    let platform = u16_be(data, record)
    let name_id = u16_be(data, record + 6)
    let length = u16_be(data, record + 8)
    let relative = u16_be(data, record + 10)
    if name_id == 1 || name_id == 4 || name_id == 6 {
      let start = storage + relative
      if start < 0 || start + length > data.length() {
        raise InvalidFont("truncated name string")
      }
      let value = if platform == 0 || platform == 3 {
        @utf16.decode_lossy(data[start:start + length], endianness=Big)
      } else {
        @ascii.decode_lossy(data[start:start + length])
      }
      if value != "" && !names.contains(value) {
        names.push(value)
      }
    }
  }
  names
}

///|
fn inspect_font(path : String, expected : String) -> Unit raise {
  let data = @fs.read_file_to_bytes(path)
  let names = font_names(data)
  if !names.contains(expected) {
    raise FontInspectError::InvalidFont(
      "expected family \"\{expected}\"; found \"\{names.join("|")}\"",
    )
  }
  let os2 = table_offset(data, "OS/2").unwrap_or_else(() => {
    raise InvalidFont("missing OS/2 table")
  })
  let fs_type = u16_be(data, os2 + 8)
  if (fs_type & 2) != 0 {
    raise InvalidFont("OS/2 fsType \{fs_type} forbids embedding")
  }
  println("family=\{expected}")
  println("fs_type=\{fs_type}")
}

///|
fn main raise {
  let args = @env.args()
  if args.length() != 3 {
    println("usage: font-inspect <font-file> <expected-family>")
    raise InvalidFont("expected two arguments")
  }
  inspect_font(args[1], args[2])
}
