///|
pub(all) enum PrewarmFailure {
  TransferUnavailable
  DigestMismatch
  SignatureRejected
  InsufficientCache
  NodeUnavailable
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PrewarmState {
  Queued
  Reserved
  Transferring
  Verifying
  Ready
  CancellationRequested
  Cancelled
  Failed(PrewarmFailure)
  Expired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PrewarmIntent {
  operation_id : String
  deployment_id : String
  node_id : String
  model_digest : String
  size_bytes : Int64
  created_unix_ms : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PrewarmProgress {
  transferred_bytes : Int64
  total_bytes : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CacheReservation {
  node_id : String
  model_digest : String
  bytes : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct PrewarmOperation {
  intent : PrewarmIntent
  state : PrewarmState
  progress : PrewarmProgress
  reservation : CacheReservation?
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PrewarmEvent {
  Reserve
  StartTransfer
  ReportProgress(transferred_bytes~ : Int64)
  BeginVerification
  PublishReady
  RequestCancellation
  ObserveCancellation
  Fail(reason~ : PrewarmFailure)
  ObserveTime
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PrewarmRejection {
  InvalidIdentity
  InvalidDigest
  InvalidSize
  InvalidTimeRange
  AlreadyExpired
  TerminalState
  InvalidTransition
  ProgressRegressed
  ProgressExceedsArtifact
  TransferIncomplete
  ObservationBeforeLastUpdate
  InvalidOperation
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum PrewarmDecision {
  Accepted(PrewarmOperation)
  Rejected(PrewarmRejection)
} derive(Debug, Eq, ToJson, FromJson)

///|
fn valid_digest(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  value.all(char => {
    match char {
      '0'..='9' | 'a'..='f' => true
      _ => false
    }
  })
}

///|
fn prewarm_terminal(state : PrewarmState) -> Bool {
  match state {
    Ready | Cancelled | Failed(_) | Expired => true
    _ => false
  }
}

///|
fn valid_prewarm_operation(operation : PrewarmOperation) -> Bool {
  let intent = operation.intent
  let progress = operation.progress
  let identity_valid = !intent.operation_id.is_empty() &&
    !intent.deployment_id.is_empty() &&
    !intent.node_id.is_empty() &&
    valid_digest(intent.model_digest)
  let progress_valid = intent.size_bytes > 0L &&
    progress.total_bytes == intent.size_bytes &&
    progress.transferred_bytes >= 0L &&
    progress.transferred_bytes <= intent.size_bytes &&
    progress.updated_unix_ms >= intent.created_unix_ms &&
    progress.updated_unix_ms <= operation.updated_unix_ms
  let reservation_valid = match operation.reservation {
    None => true
    Some(reservation) =>
      reservation.node_id == intent.node_id &&
      reservation.model_digest == intent.model_digest &&
      reservation.bytes == intent.size_bytes &&
      reservation.expires_unix_ms == intent.expires_unix_ms
  }
  let state_valid = match operation.state {
    Reserved | Transferring | Verifying => operation.reservation is Some(_)
    Ready =>
      operation.reservation is None &&
      progress.transferred_bytes == intent.size_bytes
    Cancelled | Failed(_) | Expired => operation.reservation is None
    _ => true
  }
  identity_valid &&
  progress_valid &&
  reservation_valid &&
  state_valid &&
  intent.created_unix_ms >= 0L &&
  intent.expires_unix_ms > intent.created_unix_ms &&
  operation.updated_unix_ms >= intent.created_unix_ms
}

///|
pub fn begin_prewarm(
  intent : PrewarmIntent,
  now_unix_ms : Int64,
) -> PrewarmDecision {
  if intent.operation_id.is_empty() ||
    intent.deployment_id.is_empty() ||
    intent.node_id.is_empty() {
    return Rejected(InvalidIdentity)
  }
  if !valid_digest(intent.model_digest) {
    return Rejected(InvalidDigest)
  }
  if intent.size_bytes <= 0L {
    return Rejected(InvalidSize)
  }
  if intent.created_unix_ms < 0L ||
    intent.expires_unix_ms <= intent.created_unix_ms {
    return Rejected(InvalidTimeRange)
  }
  if now_unix_ms < intent.created_unix_ms {
    return Rejected(InvalidTimeRange)
  }
  if now_unix_ms >= intent.expires_unix_ms {
    return Rejected(AlreadyExpired)
  }
  Accepted({
    intent,
    state: Queued,
    progress: {
      transferred_bytes: 0L,
      total_bytes: intent.size_bytes,
      updated_unix_ms: now_unix_ms,
    },
    reservation: None,
    updated_unix_ms: now_unix_ms,
  })
}

///|
pub fn advance_prewarm(
  operation : PrewarmOperation,
  event : PrewarmEvent,
  now_unix_ms : Int64,
) -> PrewarmDecision {
  if !valid_prewarm_operation(operation) {
    return Rejected(InvalidOperation)
  }
  if now_unix_ms < operation.updated_unix_ms {
    return Rejected(ObservationBeforeLastUpdate)
  }
  if prewarm_terminal(operation.state) {
    return Rejected(TerminalState)
  }
  if now_unix_ms >= operation.intent.expires_unix_ms {
    return Accepted({
      ..operation,
      state: Expired,
      reservation: None,
      updated_unix_ms: now_unix_ms,
    })
  }
  match event {
    RequestCancellation =>
      Accepted({
        ..operation,
        state: CancellationRequested,
        updated_unix_ms: now_unix_ms,
      })
    ObserveCancellation if operation.state == CancellationRequested =>
      Accepted({
        ..operation,
        state: Cancelled,
        reservation: None,
        updated_unix_ms: now_unix_ms,
      })
    Fail(reason~) =>
      Accepted({
        ..operation,
        state: Failed(reason),
        reservation: None,
        updated_unix_ms: now_unix_ms,
      })
    Reserve if operation.state == Queued =>
      Accepted({
        ..operation,
        state: Reserved,
        reservation: Some({
          node_id: operation.intent.node_id,
          model_digest: operation.intent.model_digest,
          bytes: operation.intent.size_bytes,
          expires_unix_ms: operation.intent.expires_unix_ms,
        }),
        updated_unix_ms: now_unix_ms,
      })
    StartTransfer if operation.state == Reserved =>
      Accepted({
        ..operation,
        state: Transferring,
        updated_unix_ms: now_unix_ms,
      })
    ReportProgress(transferred_bytes~) if operation.state == Transferring =>
      if transferred_bytes < operation.progress.transferred_bytes {
        Rejected(ProgressRegressed)
      } else if transferred_bytes > operation.intent.size_bytes {
        Rejected(ProgressExceedsArtifact)
      } else {
        Accepted({
          ..operation,
          progress: {
            transferred_bytes,
            total_bytes: operation.intent.size_bytes,
            updated_unix_ms: now_unix_ms,
          },
          updated_unix_ms: now_unix_ms,
        })
      }
    BeginVerification if operation.state == Transferring =>
      if operation.progress.transferred_bytes != operation.intent.size_bytes {
        Rejected(TransferIncomplete)
      } else {
        Accepted({ ..operation, state: Verifying, updated_unix_ms: now_unix_ms })
      }
    PublishReady if operation.state == Verifying =>
      Accepted({
        ..operation,
        state: Ready,
        reservation: None,
        updated_unix_ms: now_unix_ms,
      })
    ObserveTime => Accepted({ ..operation, updated_unix_ms: now_unix_ms })
    _ => Rejected(InvalidTransition)
  }
}
