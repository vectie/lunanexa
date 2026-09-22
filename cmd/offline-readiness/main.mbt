///|
/// Command line shape of the offline-commerce readiness signer.
let readiness_usage : String = "usage: lunanexa-offline-readiness --input INPUT.json --output OUTPUT.json --secret SECRET [--issued-unix-ms UNIX_MS] [--validity-ms MILLISECONDS]\n\nSigns the lunanexa.offline-commerce-readiness.v1 document that the control\nplane loads from LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH and verifies with\nLUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET.\n\n  --input PATH        JSON with a \"capabilities\" array holding exactly one\n                      entry for each of the ten capabilities.\n  --output PATH       Destination for the signed document.\n  --secret VALUE      HMAC-SHA256 signing secret, 32 to 4096 characters.\n  --issued-unix-ms MS Issue time in unix milliseconds; defaults to now.\n  --validity-ms MS    Issue-to-expiry window; defaults to 2678400000 (31 days),\n                      which is also the maximum the control plane accepts.\n  --help              Print this message."

///|
/// The default issue-to-expiry window: the widest window the control plane
/// accepts, so the default never has to be lowered when the bound moves.
let default_readiness_validity_ms : Int64 = @offline.offline_readiness_maximum_validity_ms

///|
priv struct OfflineReadinessEvidenceInput {
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence]
} derive(FromJson)

///|
fn argument_value(args : Array[String], name : String) -> String? {
  for index in 1..<(args.length() - 1) {
    if args[index] == name {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn required_argument(args : Array[String], name : String) -> String raise {
  guard argument_value(args, name) is Some(value) && value != "" else {
    raise Failure::Failure("missing required argument: \{name}")
  }
  value
}

///|
fn int64_argument(
  args : Array[String],
  name : String,
  fallback : Int64,
) -> Int64 raise {
  match argument_value(args, name) {
    None => fallback
    Some(value) =>
      @string.parse_int64(value) catch {
        _ => raise Failure::Failure("argument is not an integer: \{name}")
      }
  }
}

///|
fn capability_label(capability : @offline.OfflineCommerceCapability) -> String {
  capability.to_json().stringify()
}

///|
/// Refuses any document the control plane would reject, before it is signed.
/// The final cross-check reuses the reader's own projection, so a document the
/// tool accepts cannot be turned into a `Readiness` blocker at startup.
fn validate_readiness_evidence(
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence],
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
) -> Unit raise {
  if issued_unix_ms <= 0L {
    raise Failure::Failure("issued-unix-ms must be a positive unix millisecond")
  }
  if expires_unix_ms <= issued_unix_ms {
    raise Failure::Failure(
      "the expiry window must end after the document is issued",
    )
  }
  if expires_unix_ms - issued_unix_ms >
    @offline.offline_readiness_maximum_validity_ms {
    raise Failure::Failure(
      "the expiry window must not exceed 31 days (\{@offline.offline_readiness_maximum_validity_ms} ms)",
    )
  }
  let expected = required_readiness_capabilities()
  if capabilities.length() != expected.length() {
    raise Failure::Failure(
      "exactly \{expected.length()} capability entries are required, found \{capabilities.length()}",
    )
  }
  let declared : Array[@offline.OfflineCommerceCapability] = []
  let references : Map[String, Unit] = Map([])
  for entry in capabilities {
    if declared.contains(entry.capability) {
      raise Failure::Failure(
        "capability is declared more than once: \{capability_label(entry.capability)}",
      )
    }
    declared.push(entry.capability)
    match entry.evidence_ref {
      None => ()
      Some(reference) => {
        if !@offline.valid_readiness_ref(reference) {
          raise Failure::Failure(
            "evidence_ref must be 1 to 256 ASCII alphanumerics or - _ . : / : \{capability_label(entry.capability)}",
          )
        }
        if references.contains(reference) {
          raise Failure::Failure(
            "evidence_ref is retained by more than one capability: \{reference}",
          )
        }
        references[reference] = ()
      }
    }
  }
  for capability in expected {
    if !declared.contains(capability) {
      raise Failure::Failure(
        "capability entry is missing: \{capability_label(capability)}",
      )
    }
  }
  let readiness = @offline.offline_commerce_readiness(
    capabilities, issued_unix_ms,
  )
  if readiness.blocker_codes.any(code => code.has_prefix("Readiness")) {
    raise Failure::Failure(
      "the control plane would reject this capability set: \{readiness.blocker_codes.join(",")}",
    )
  }
}

///|
/// The ten capability gates the document must cover exactly once. Missing or
/// duplicated entries are what the reader reports as `Readiness` blockers.
fn required_readiness_capabilities() -> Array[
  @offline.OfflineCommerceCapability,
] {
  [
    @offline.ApprovedLegalTemplates,
    @offline.ObjectStorage,
    @offline.MalwareScanner,
    @offline.OoxmlWorker,
    @offline.PdfRenderer,
    @offline.SpreadsheetFormulaEngine,
    @offline.CjkFonts,
    @offline.MachineCallbackIdentity,
    @offline.EntitlementAuthority,
    @offline.FinanceLegalPolicy,
  ]
}

///|
/// Builds the exact document the control plane loads. Validation runs before
/// the signature exists, so a rejected document is never signed.
fn sign_readiness_evidence(
  capabilities : Array[@offline.OfflineCommerceCapabilityEvidence],
  issued_unix_ms : Int64,
  expires_unix_ms : Int64,
  secret : String,
) -> @offline.OfflineReadinessEvidenceDocument raise {
  if secret.length() < 32 || secret.length() > 4096 {
    raise Failure::Failure(
      "the signing secret must be 32 to 4096 characters; the control plane rejects anything else",
    )
  }
  validate_readiness_evidence(capabilities, issued_unix_ms, expires_unix_ms)
  let unsigned : @offline.OfflineReadinessEvidenceDocument = {
    schema_version: @offline.offline_readiness_schema_version,
    issued_unix_ms,
    expires_unix_ms,
    capabilities,
    signature: "",
  }
  {
    ..unsigned,
    signature: @offline.offline_readiness_signature(unsigned, secret),
  }
}

///|
/// The document type decodes an explicit `null` evidence_ref as a decode
/// error, exactly as the control plane does. The tool's input accepts it by
/// dropping the key, so either spelling of "no retained reference" signs into
/// a document the reader can still load.
fn without_null_readiness_refs(value : Json) -> Json {
  value.transform(
    @json.Replacer((key, item) => {
      match (key, item) {
        ("evidence_ref", Null) => None
        _ => Some(item)
      }
    }),
  )
}

///|
async fn read_readiness_input(
  path : String,
) -> Array[@offline.OfflineCommerceCapabilityEvidence] {
  if !@fs.exists(path) {
    raise Failure::Failure("readiness input does not exist: \{path}")
  }
  let input : OfflineReadinessEvidenceInput = @json.from_json(
    without_null_readiness_refs(@json.parse(@fs.read_file(path).text())),
  ) catch {
    _ =>
      raise Failure::Failure(
        "readiness input must be JSON with a capabilities array: \{path}",
      )
  }
  input.capabilities
}

///|
async fn write_readiness_document(
  path : String,
  document : @offline.OfflineReadinessEvidenceDocument,
) -> Unit {
  let temporary = "\{path}.next"
  @fs.write_file(
    temporary,
    document.to_json().stringify(indent=2),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn sign_readiness_evidence_from_arguments(args : Array[String]) -> Unit {
  let input_path = required_argument(args, "--input")
  let output_path = required_argument(args, "--output")
  let secret = readiness_secret_argument(args, @env.get_env_var)
  let issued_unix_ms = int64_argument(args, "--issued-unix-ms", @async.now())
  let expires_unix_ms = issued_unix_ms +
    int64_argument(args, "--validity-ms", default_readiness_validity_ms)
  let capabilities = read_readiness_input(input_path)
  let document = sign_readiness_evidence(
    capabilities, issued_unix_ms, expires_unix_ms, secret,
  )
  write_readiness_document(output_path, document)
  let ready = capabilities
    .filter(entry => entry.configured && entry.verified)
    .length()
  println("readiness evidence written: \{output_path}")
  println("signature: \{document.signature}")
  println(
    "window: \{document.issued_unix_ms} issued .. \{document.expires_unix_ms} expires (unix ms)",
  )
  println(
    "capabilities configured and verified: \{ready} of \{capabilities.length()}",
  )
}

///|
/// Keep deployment signing material out of process arguments. Explicit legacy
/// --secret remains supported; ambiguous sources are refused.
fn readiness_secret_argument(
  args : Array[String],
  lookup : (String) -> String?,
) -> String raise {
  match
    (argument_value(args, "--secret"), argument_value(args, "--secret-env")) {
    (Some(_), Some(_)) => fail("choose one signing secret source")
    (Some(value), None) => value
    (None, Some(name)) => {
      guard name != "" &&
        name.all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_') else {
        fail("invalid signing secret environment variable name")
      }
      guard lookup(name) is Some(value) && value != "" else {
        fail("signing secret environment variable is missing or empty")
      }
      value
    }
    (None, None) => fail("provide --secret-env NAME or --secret VALUE")
  }
}

///|
async fn main {
  let args = @env.args()
  if args.contains("--help") || args.contains("-h") {
    println(readiness_usage)
    println(
      "\nProduction alternative: replace --secret VALUE with --secret-env ENV_NAME to read the signing secret from the environment. Do not supply both.",
    )
    return
  }
  sign_readiness_evidence_from_arguments(args)
}
