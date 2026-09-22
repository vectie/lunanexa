///|
/// Count stored bytes without reading model contents or following symlinks.
async fn cache_entry_size(path : String) -> Int64 {
  match @fs.kind(path, follow_symlink=false) {
    Directory => {
      let mut total = 0L
      for entry in @fs.readdir(path, include_hidden=true) {
        total += cache_entry_size("\{path}/\{entry}")
      }
      total
    }
    Regular => {
      let file = @fs.open(path, mode=ReadOnly)
      defer file.close()
      file.size()
    }
    _ => 0L
  }
}
