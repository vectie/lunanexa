///|
fn be16(value : Int) -> Array[Byte] {
  [(value / 256).to_byte(), (value % 256).to_byte()]
}

///|
fn be32(value : Int) -> Array[Byte] {
  [
    (value / 16777216).to_byte(),
    (value / 65536 % 256).to_byte(),
    (value / 256 % 256).to_byte(),
    (value % 256).to_byte(),
  ]
}

///|
fn ascii(value : String) -> Array[Byte] {
  [
    for char in value => char.to_int().to_byte()
  ]
}

///|
fn utf16_be(value : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  for code in value {
    bytes.push((code.to_int() / 256).to_byte())
    bytes.push((code.to_int() % 256).to_byte())
  }
  bytes
}

///|
fn fixture_font(family : String, fs_type : Int) -> Bytes {
  let family_bytes = utf16_be(family)
  let header = [
    b'\x00',
    b'\x01',
    b'\x00',
    b'\x00',
    ..be16(2),
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
  ]
  let name_offset = 44
  let name_length = 18 + family_bytes.length()
  let os2_offset = name_offset + name_length
  let records = [
    ..ascii("name"),
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    ..be32(name_offset),
    ..be32(name_length),
    ..ascii("OS/2"),
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    ..be32(os2_offset),
    ..be32(10),
  ]
  let name_table = [
    b'\x00',
    b'\x00',
    ..be16(1),
    ..be16(18),
    ..be16(3),
    ..be16(1),
    ..be16(0x0804),
    ..be16(1),
    ..be16(family_bytes.length()),
    b'\x00',
    b'\x00',
    ..family_bytes,
  ]
  let os2_table = [
    b'\x00',
    b'\x04',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    ..be16(fs_type),
  ]
  Bytes::from_array([..header, ..records, ..name_table, ..os2_table])
}

///|
test "font inspector reads CJK family and installable embedding" {
  let data = fixture_font("仿宋_GB2312", 0)
  assert_eq(font_names(data), ["仿宋_GB2312"])
  assert_eq(u16_be(data, table_offset(data, "OS/2").unwrap() + 8), 0)
}

///|
test "font inspector exposes restricted embedding flag" {
  let data = fixture_font("方正小标宋简体", 2)
  assert_eq(font_names(data), ["方正小标宋简体"])
  assert_eq(u16_be(data, table_offset(data, "OS/2").unwrap() + 8), 2)
}
