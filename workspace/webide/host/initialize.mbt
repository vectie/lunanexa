///|
/// Runs as an init container before ComfyUI starts, with only the workspace
/// volume mounted. The image and custom-node directories stay read-only.
pub async fn initialize_workspace(root : String, model : String) -> Unit {
  if !root.has_prefix("/") ||
    root == "/" ||
    root.has_suffix("/") ||
    root.split("/").any(part => part == "." || part == "..") ||
    model.is_empty() ||
    model.length() > 128 ||
    !model.all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' ||
      c == '.' ||
      c == ':'
    }) {
    raise HostError::InvalidConfiguration
  }
  guard @fs.kind(root, follow_symlink=false) is Directory else {
    raise HostError::InvalidConfiguration
  }
  for
    suffix in [
      ".lunanexa-bootstrap", "user", "input", "output", "user/default", "user/default/workflows",
    ] {
    let path = root + "/" + suffix
    @fs.mkdir(path, permission=0o700) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => {
        guard @fs.kind(path, follow_symlink=false) is Directory else {
          raise HostError::InvalidConfiguration
        }
      }
      error => raise error
    }
  }
  create_initial_file(
    root + "/user/default/workflows/LunaNexa Video - " + model + ".json",
    root + "/.lunanexa-bootstrap/staged.json",
    starter_workflow(model),
  )
  create_initial_file(
    root + "/user/default/comfy.settings.json",
    root + "/.lunanexa-bootstrap/staged.json",
    { "Comfy.UseNewMenu": "Top", "Comfy.TutorialCompleted": true },
  )
}

///|
/// Atomic, no-replace publication preserves edits and refuses symlinks. A
/// crash can leave only the private staging file, never a truncated workflow.
/// This package never initializes a live/shared directory: the init container
/// finishes before the single workspace pod can serve user requests.
async fn create_initial_file(
  path : String,
  staging : String,
  content : Json,
) -> Unit {
  let existing = Some(@fs.kind(path, follow_symlink=false)) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  }
  if existing is Some(Regular) {
    return
  }
  if existing is Some(_) {
    raise HostError::InvalidConfiguration
  }
  let staged_kind = Some(@fs.kind(staging, follow_symlink=false)) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  }
  if staged_kind is Some(kind) && kind != Regular {
    raise HostError::InvalidConfiguration
  }
  @fs.write_file(
    staging,
    content.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(staging, path, replace=false)
}

///|
fn workflow_widget(name : String, kind : String) -> Json {
  { "name": name, "type": kind, "widget": { "name": name }, "link": null }
}

///|
fn starter_workflow(model : String) -> Json {
  {
    "id": "2c90c86d-9f87-4f65-bafd-c98d55c2f491",
    "revision": 0,
    "last_node_id": 3,
    "last_link_id": 2,
    "nodes": [
      {
        "id": 3,
        "type": "VLLMOmniDiffusionSampling",
        "title": "H3 sampling",
        "pos": [80, 80],
        "size": [300, 250],
        "flags": {},
        "order": 0,
        "mode": 0,
        "inputs": [
          workflow_widget("n", "INT"),
          workflow_widget("num_inference_steps", "INT"),
          workflow_widget("guidance_scale", "FLOAT"),
          workflow_widget("true_cfg_scale", "FLOAT"),
          workflow_widget("vae_use_slicing", "BOOLEAN"),
          workflow_widget("vae_use_tiling", "BOOLEAN"),
          workflow_widget("seed", "INT"),
        ],
        "outputs": [
          {
            "name": "diffusion sampling params",
            "type": "SAMPLING_PARAMS",
            "links": [2],
          },
        ],
        "properties": { "Node name for S&R": "VLLMOmniDiffusionSampling" },
        "widgets_values": [1, 8, 1.0, 1.0, false, false, -1, "randomize"],
        "widgets_values_named": {
          "n": 1,
          "num_inference_steps": 8,
          "guidance_scale": 1.0,
          "true_cfg_scale": 1.0,
          "vae_use_slicing": false,
          "vae_use_tiling": false,
          "seed": -1,
          "control_after_generate": "randomize",
        },
      },
      {
        "id": 1,
        "type": "VLLMOmniGenerateVideo",
        "title": "LunaNexa · Generate video",
        "pos": [420, 80],
        "size": [400, 400],
        "flags": {},
        "order": 1,
        "mode": 0,
        "inputs": [
          { "name": "image", "type": "IMAGE", "shape": 7, "link": null },
          {
            "name": "sampling_params",
            "type": "SAMPLING_PARAMS",
            "shape": 7,
            "link": 2,
          },
          { "name": "lora", "type": "REMOTE_LORA", "shape": 7, "link": null },
          {
            "name": "model_params",
            "type": "VIDEO_PARAMS",
            "shape": 7,
            "link": null,
          },
          workflow_widget("url", "STRING"),
          workflow_widget("model", "STRING"),
          workflow_widget("prompt", "STRING"),
          workflow_widget("negative_prompt", "STRING"),
          workflow_widget("width", "INT"),
          workflow_widget("height", "INT"),
          workflow_widget("fps", "INT"),
          workflow_widget("num_frames", "INT"),
          workflow_widget("generate_sound", "BOOLEAN"),
          workflow_widget("max_wait_seconds", "INT"),
        ],
        "outputs": [{ "name": "video", "type": "VIDEO", "links": [1] }],
        "properties": { "Node name for S&R": "VLLMOmniGenerateVideo" },
        "widgets_values": [
          "http://127.0.0.1:8189/v1", model, "A calm ocean at sunrise, gentle waves, cinematic lighting.",
          "", 512, 512, 24, 25, false, 900,
        ],
        "widgets_values_named": {
          "url": "http://127.0.0.1:8189/v1",
          "model": model,
          "prompt": "A calm ocean at sunrise, gentle waves, cinematic lighting.",
          "negative_prompt": "",
          "width": 512,
          "height": 512,
          "fps": 24,
          "num_frames": 25,
          "generate_sound": false,
          "max_wait_seconds": 900,
        },
      },
      {
        "id": 2,
        "type": "SaveVideo",
        "pos": [860, 80],
        "size": [360, 350],
        "flags": {},
        "order": 2,
        "mode": 0,
        "inputs": [
          { "name": "video", "type": "VIDEO", "link": 1 },
          workflow_widget("filename_prefix", "STRING"),
          workflow_widget("format", "COMFY_DYNAMICCOMBO_V3"),
          workflow_widget("format.codec", "COMFY_DYNAMICCOMBO_V3"),
          workflow_widget("codec", "COMFY_DYNAMICCOMBO_V3"),
        ],
        "outputs": [{ "name": "video", "type": "VIDEO", "links": null }],
        "properties": { "Node name for S&R": "SaveVideo" },
        "widgets_values": ["video/LunaNexa", "auto", "auto", "auto"],
        "widgets_values_named": {
          "filename_prefix": "video/LunaNexa",
          "format": "auto",
          "format.codec": "auto",
          "codec": "auto",
        },
      },
    ],
    "links": [[1, 1, 0, 2, 0, "VIDEO"], [2, 3, 0, 1, 1, "SAMPLING_PARAMS"]],
    "groups": [],
    "config": {},
    "extra": { "ds": { "scale": 0.9, "offset": [0, 0] } },
    "version": 0.4,
  }
}
