# ComfyUI durable outputs adapter

The workspace mounts input, output, workflows and the SQLite asset index on its
own PVC. Start ComfyUI with `--enable-assets` and
`--database-url sqlite:////workspace/user/comfyui.db`. This enables indexing of
existing files after replacement; retaining files without discoverability is
not sufficient acceptance.

The reviewed frontend 1.51.9 community bundle still binds the media output list
to transient execution history. It already contains a paginated flat-output
asset implementation. Our pinned compatibility patch uses that implementation
for the output list and refreshes it on existing execution/status updates. It
does not change input handling, model APIs, authentication or job history.

Before building `Containerfile.comfyui-workspace`:

1. Extract the original frontend 1.51.9
   `static/assets/settingStore-KkBYyEnh.js` into an isolated build directory.
   The accepted SHA256 is
   `8c7ffdcbb2cb0ee5db8e102d575f366f69edbe9ac124be0b2965deef36238684`.
2. Run `moon run scripts/patch-comfyui-frontend-assets.mbtx <staged-file>`.
   MoonBit, OpenSSL and Node are build-host tools, not new workspace services.
   The script rejects unknown bytes and checks the resulting JavaScript syntax.
3. Supply the result as `comfyui-frontend-assets.js` in the image build context.
   Its SHA256 is
   `a413a8e373f569276609be5eea3b905dc1415fbac07835099b2f03ed17829660`.

Do not patch a running container or a customer's volume. Build a new immutable
image and replace the workspace. An upstream upgrade requires reviewing the
new source and repeating browser generation, replacement, list, pagination and
download acceptance; a version number alone is not a compatibility guarantee.
Remove this patch once the upstream community output panel uses durable assets.
