# Private contract fonts

This directory is populated from organization-licensed font files and copied
into the browser distribution by `scripts/install-contract-fonts.sh`. Font
binaries are intentionally ignored by Git.

Required source faces for the youthpolicy v1 contract are:

- `FangSong_GB2312.ttf` — family `FangSong_GB2312` / `仿宋_GB2312`;
- `FZXiaoBiaoSong-B05S.ttf` — family `方正小标宋简体`;
- `SimHei.ttf` — family `SimHei` / `黑体`.

Do not rename a substitute font to satisfy these slots. The install script
checks internal family names and embedding flags before accepting a file.
