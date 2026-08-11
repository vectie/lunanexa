///|
pub(all) enum ProbeKind {
  Startup
  Readiness
  Liveness
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProbeStagePolicy {
  initial_delay_ms : Int64
  period_ms : Int64
  timeout_ms : Int64
  success_threshold : Int
  failure_threshold : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProbePolicy {
  startup : ProbeStagePolicy
  readiness : ProbeStagePolicy
  liveness : ProbeStagePolicy
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProbeCounters {
  consecutive_successes : Int
  consecutive_failures : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum RuntimeHealthState {
  Starting
  NotReady
  Ready
  RestartRequired
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProbeState {
  runtime_state : RuntimeHealthState
  startup_complete : Bool
  startup : ProbeCounters
  readiness : ProbeCounters
  liveness : ProbeCounters
  runtime_created_unix_ms : Int64
  startup_completed_unix_ms : Int64?
  last_observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ProbeObservation {
  kind : ProbeKind
  success : Bool
  observed_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ProbeRejection {
  InvalidPolicy
  StaleObservation
  StartupIncomplete
  StartupAlreadyComplete
  RuntimeAlreadyTerminal
  InitialDelayActive
  InvalidState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum ProbeDecision {
  Applied(ProbeState)
  Rejected(ProbeRejection)
} derive(Debug, Eq, ToJson, FromJson)

///|
fn valid_stage_policy(policy : ProbeStagePolicy) -> Bool {
  policy.initial_delay_ms >= 0L &&
  policy.period_ms > 0L &&
  policy.timeout_ms > 0L &&
  policy.timeout_ms <= policy.period_ms &&
  policy.success_threshold > 0 &&
  policy.failure_threshold > 0
}

///|
pub fn valid_probe_policy(policy : ProbePolicy) -> Bool {
  valid_stage_policy(policy.startup) &&
  valid_stage_policy(policy.readiness) &&
  valid_stage_policy(policy.liveness)
}

///|
pub fn initial_probe_state(created_unix_ms : Int64) -> ProbeState {
  let counters : ProbeCounters = {
    consecutive_successes: 0,
    consecutive_failures: 0,
  }
  {
    runtime_state: Starting,
    startup_complete: false,
    startup: counters,
    readiness: counters,
    liveness: counters,
    runtime_created_unix_ms: created_unix_ms,
    startup_completed_unix_ms: None,
    last_observed_unix_ms: created_unix_ms,
  }
}

///|
fn valid_counters(counters : ProbeCounters) -> Bool {
  counters.consecutive_successes >= 0 && counters.consecutive_failures >= 0
}

///|
fn observe_counter(
  counters : ProbeCounters,
  success : Bool,
  success_threshold : Int,
  failure_threshold : Int,
) -> ProbeCounters {
  if success {
    let next = if counters.consecutive_successes >= success_threshold {
      success_threshold
    } else {
      counters.consecutive_successes + 1
    }
    { consecutive_successes: next, consecutive_failures: 0 }
  } else {
    let next = if counters.consecutive_failures >= failure_threshold {
      failure_threshold
    } else {
      counters.consecutive_failures + 1
    }
    { consecutive_successes: 0, consecutive_failures: next }
  }
}

///|
pub fn ProbeState::route_eligible(self : ProbeState) -> Bool {
  self.startup_complete && self.runtime_state == Ready
}

///|
pub fn evaluate_probe(
  state : ProbeState,
  observation : ProbeObservation,
  policy : ProbePolicy,
) -> ProbeDecision {
  if !valid_probe_policy(policy) {
    return Rejected(InvalidPolicy)
  }
  if state.runtime_created_unix_ms < 0L ||
    state.last_observed_unix_ms < state.runtime_created_unix_ms ||
    !valid_counters(state.startup) ||
    !valid_counters(state.readiness) ||
    !valid_counters(state.liveness) ||
    (state.startup_complete && state.startup_completed_unix_ms is None) ||
    (!state.startup_complete && state.startup_completed_unix_ms is Some(_)) {
    return Rejected(InvalidState)
  }
  if observation.observed_unix_ms <= state.last_observed_unix_ms {
    return Rejected(StaleObservation)
  }
  if state.runtime_state == RestartRequired {
    return Rejected(RuntimeAlreadyTerminal)
  }
  match observation.kind {
    Startup => {
      if state.startup_complete {
        return Rejected(StartupAlreadyComplete)
      }
      if observation.observed_unix_ms - state.runtime_created_unix_ms <
        policy.startup.initial_delay_ms {
        return Rejected(InitialDelayActive)
      }
      let counters = observe_counter(
        state.startup,
        observation.success,
        policy.startup.success_threshold,
        policy.startup.failure_threshold,
      )
      if counters.consecutive_failures >= policy.startup.failure_threshold {
        Applied({
          ..state,
          runtime_state: RestartRequired,
          startup: counters,
          last_observed_unix_ms: observation.observed_unix_ms,
        })
      } else if counters.consecutive_successes >=
        policy.startup.success_threshold {
        Applied({
          ..state,
          runtime_state: NotReady,
          startup_complete: true,
          startup_completed_unix_ms: Some(observation.observed_unix_ms),
          startup: counters,
          last_observed_unix_ms: observation.observed_unix_ms,
        })
      } else {
        Applied({
          ..state,
          startup: counters,
          last_observed_unix_ms: observation.observed_unix_ms,
        })
      }
    }
    Readiness => {
      if !state.startup_complete {
        return Rejected(StartupIncomplete)
      }
      let started = state.startup_completed_unix_ms.unwrap()
      if observation.observed_unix_ms - started <
        policy.readiness.initial_delay_ms {
        return Rejected(InitialDelayActive)
      }
      let counters = observe_counter(
        state.readiness,
        observation.success,
        policy.readiness.success_threshold,
        policy.readiness.failure_threshold,
      )
      let runtime_state = if counters.consecutive_successes >=
        policy.readiness.success_threshold {
        RuntimeHealthState::Ready
      } else if counters.consecutive_failures >=
        policy.readiness.failure_threshold {
        NotReady
      } else {
        state.runtime_state
      }
      Applied({
        ..state,
        runtime_state,
        readiness: counters,
        last_observed_unix_ms: observation.observed_unix_ms,
      })
    }
    Liveness => {
      if !state.startup_complete {
        return Rejected(StartupIncomplete)
      }
      let started = state.startup_completed_unix_ms.unwrap()
      if observation.observed_unix_ms - started <
        policy.liveness.initial_delay_ms {
        return Rejected(InitialDelayActive)
      }
      let counters = observe_counter(
        state.liveness,
        observation.success,
        policy.liveness.success_threshold,
        policy.liveness.failure_threshold,
      )
      let runtime_state = if counters.consecutive_failures >=
        policy.liveness.failure_threshold {
        RestartRequired
      } else {
        state.runtime_state
      }
      Applied({
        ..state,
        runtime_state,
        liveness: counters,
        last_observed_unix_ms: observation.observed_unix_ms,
      })
    }
  }
}
