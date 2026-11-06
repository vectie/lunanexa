///|
pub(all) suberror ImageError {
  InvalidConfiguration
  InvalidRequest
  InvalidResponse
  Unavailable
}

///|
/// Operator-pinned files on one qualified runtime. Consumers can change only
/// the prompt and seed; there are no arbitrary nodes, paths, URLs or uploads.
pub(all) struct Profile {
  diffusion : String
  text_encoder : String
  vae : String
} derive(ToJson, FromJson)

///|
pub extend Profile with ToJson::{to_json}

///|
pub extend Profile with FromJson::{from_json}

///|
pub struct Provider {
  origin : String
  profile : Profile
}

///|
pub(all) enum Observation {
  Pending
  Failed
  Complete(String)
} derive(Debug, Eq)

///|
pub extend Observation with Debug::{to_repr}

///|
pub extend Observation with Eq::{not_equal, equal}

///|
fn safe(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 160 &&
  !value.contains("..") &&
  value.all(c => c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '_' | '-' | '.'))
}

///|
pub fn Provider::new(origin : String, profile : Profile) -> Provider raise {
  let authority = match origin.strip_prefix("http://") {
    Some(host) => Some(host)
    None => origin.strip_prefix("https://")
  }
  guard authority is Some(host) &&
    !host.is_empty() &&
    host.all(c => c is ('a'..<='z' | '0'..<='9' | '.' | '-' | ':')) &&
    safe(profile.diffusion) &&
    safe(profile.text_encoder) &&
    safe(profile.vae) else {
    raise InvalidConfiguration
  }
  { origin, profile, }
}

///|
/// Fixed Z-Image-Turbo graph, based on Comfy's published eight-step template.
pub fn Provider::workflow(
  self : Provider,
  prompt : String,
  seed : UInt32,
  request_id : String,
) -> Json raise {
  guard !prompt.trim().is_empty() && prompt.length() <= 2000 && safe(request_id) else {
    raise InvalidRequest
  }
  {
    "client_id": request_id,
    "extra_data": { "lunanexa_request_id": request_id },
    "prompt": {
      "1": {
        "class_type": "UNETLoader",
        "inputs": {
          "unet_name": self.profile.diffusion,
          "weight_dtype": "default",
        },
      },
      "2": {
        "class_type": "CLIPLoader",
        "inputs": {
          "clip_name": self.profile.text_encoder,
          "type": "lumina2",
          "device": "default",
        },
      },
      "3": {
        "class_type": "VAELoader",
        "inputs": { "vae_name": self.profile.vae },
      },
      "4": {
        "class_type": "CLIPTextEncode",
        "inputs": { "clip": ["2", 0], "text": prompt },
      },
      "5": {
        "class_type": "ConditioningZeroOut",
        "inputs": { "conditioning": ["4", 0] },
      },
      "6": {
        "class_type": "EmptySD3LatentImage",
        "inputs": { "width": 1024, "height": 1024, "batch_size": 1 },
      },
      "7": {
        "class_type": "ModelSamplingAuraFlow",
        "inputs": { "model": ["1", 0], "shift": 3, "sampling": "flow" },
      },
      "8": {
        "class_type": "KSampler",
        "inputs": {
          "model": ["7", 0],
          "positive": ["4", 0],
          "negative": ["5", 0],
          "latent_image": ["6", 0],
          "seed": seed.to_double(),
          "steps": 8,
          "cfg": 1,
          "sampler_name": "res_multistep",
          "scheduler": "simple",
          "denoise": 1,
        },
      },
      "9": {
        "class_type": "VAEDecode",
        "inputs": { "samples": ["8", 0], "vae": ["3", 0] },
      },
      "10": {
        "class_type": "SaveImage",
        "inputs": { "images": ["9", 0], "filename_prefix": request_id },
      },
    },
  }
}

///|
async fn limited(reader : &@io.Reader, max : Int32) -> Bytes {
  let buffer = FixedArray::make(max + 1, b'\x00')
  let mut size = 0
  while size <= max {
    let n = reader.read(buffer, offset=size, max_len=max + 1 - size)
    if n == 0 {
      return buffer.unsafe_reinterpret_as_bytes()[:size].to_owned()
    }
    size += n
  }
  raise InvalidResponse
}

///|
pub async fn Provider::submit(
  self : Provider,
  prompt : String,
  seed : UInt32,
  request_id : String,
) -> String {
  let graph = self.workflow(prompt, seed, request_id)
  @async.with_timeout(10000, () => {
    let client = @http.Client(self.origin, headers={
      "content-type": "application/json",
    })
    defer client.close()
    let response = client.post("/prompt", graph.stringify())
    guard response.code == 200 &&
      @json.parse(@utf8.decode(limited(client, 1048576)))
      is { "prompt_id": String(id), .. } &&
      safe(id) else {
      raise InvalidResponse
    }
    id
  })
}

///|
pub async fn Provider::observe(
  self : Provider,
  id : String,
  request_id : String,
) -> Observation {
  guard safe(id) && safe(request_id) else { raise InvalidRequest }
  @async.with_timeout(5000, () => {
    let client = @http.Client(self.origin)
    defer client.close()
    let response = client.get("/history/" + id)
    guard response.code == 200 &&
      @json.parse(@utf8.decode(limited(client, 2097152))) is Object(history) else {
      raise InvalidResponse
    }
    guard history.get(id) is Some(value) else { return Pending }
    if value is { "status": { "status_str": String("error"), .. }, .. } {
      return Failed
    }
    guard value
      is {
        "status": { "completed": True, .. },
        "outputs": { "10": { "images": Array(images), .. }, .. },
        ..
      } else {
      return Pending
    }
    guard images.length() == 1 &&
      images[0]
      is {
        "filename": String(filename),
        "subfolder": String(""),
        "type": String("output"),
        ..
      } &&
      safe(filename) &&
      filename.has_prefix(request_id + "_") &&
      filename.has_suffix(".png") else {
      raise InvalidResponse
    }
    Complete(filename)
  })
}

///|
pub async fn Provider::content(self : Provider, filename : String) -> Bytes {
  guard safe(filename) && filename.has_suffix(".png") else {
    raise InvalidRequest
  }
  @async.with_timeout(10000, () => {
    let client = @http.Client(self.origin)
    defer client.close()
    let response = client.get(
      "/view?type=output&subfolder=&filename=" + filename,
    )
    guard response.code == 200 else { raise Unavailable }
    let bytes = limited(client, 8388608)
    guard bytes.length() > 8 && bytes[:8].to_owned() == b"\x89PNG\r\n\x1a\n" else {
      raise InvalidResponse
    }
    bytes
  })
}

///|
fn tuple_request(value : Json, request_id : String) -> String? {
  guard value is Array(items) &&
    items.length() >= 4 &&
    items[1] is String(id) &&
    safe(id) &&
    items[3] is Object(metadata) &&
    (
      metadata.get("lunanexa_request_id") == Some(Json::string(request_id)) ||
      metadata.get("client_id") == Some(Json::string(request_id))
    ) else {
    return None
  }
  Some(id)
}

///|
/// Reconcile a lost POST response using reads only. Never resend a graph when
/// acceptance is ambiguous, including after either process restarts.
pub async fn Provider::lookup(self : Provider, request_id : String) -> String? {
  guard safe(request_id) else { raise InvalidRequest }
  let found : Array[String] = []
  @async.with_timeout(10000, () => {
    for path in ["/history?max_items=128", "/queue"] {
      let client = @http.Client(self.origin)
      defer client.close()
      let response = client.get(path)
      guard response.code == 200 &&
        @json.parse(@utf8.decode(limited(client, 2097152))) is Object(values) else {
        raise InvalidResponse
      }
      if path.has_prefix("/history") {
        for _, value in values {
          if value is { "prompt": prompt, .. } &&
            tuple_request(prompt, request_id) is Some(id) &&
            !found.contains(id) {
            found.push(id)
          }
        }
      } else {
        for key in ["queue_running", "queue_pending"] {
          if values.get(key) is Some(Array(jobs)) {
            for job in jobs {
              if tuple_request(job, request_id) is Some(id) &&
                !found.contains(id) {
                found.push(id)
              }
            }
          }
        }
      }
    }
  })
  if found.length() > 1 {
    raise InvalidResponse
  }
  found.get(0)
}
