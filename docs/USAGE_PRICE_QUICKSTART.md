# Explore a candidate rate card against saved usage

The offline `cmd/usage-report` price commands compare analyst-authored candidate
rates with already saved observations and recorded charges. They create a
hypothetical cost analysis, not a quote, invoice, payable balance, refund,
forecast of future demand, or ledger entry. No controller, payment service or
provider is contacted. The existing `summary`, `rows` and `json` commands are
unchanged.

This supports the commercial design's reproducible rate-card calculations and
cost exploration without changing finalized accounting records. All example
prices and usage below are invented fixtures, not offered prices or real costs.

## Run the saved-file example

Build the native CLI using your pinned environment and an absolute external
target directory:

```text
moon --target-dir /absolute/private/build build cmd/usage-report --target native --frozen --strip -j 1 --deny-warn
```

Set `REPORT` to
`/absolute/private/build/native/debug/build/vectie/lunanexa/cmd/usage-report/usage-report.exe`
and `FIXTURES` to this repository's `tests/fixtures` directory, then run:

```text
$REPORT price-summary $FIXTURES/usage-snapshot.synthetic.json $FIXTURES/usage-query.synthetic.json $FIXTURES/usage-price-scenario.synthetic.json > candidate-summary.csv
$REPORT price-rows $FIXTURES/usage-snapshot.synthetic.json $FIXTURES/usage-query.synthetic.json $FIXTURES/usage-price-scenario.synthetic.json > candidate-rows.csv
$REPORT price-json $FIXTURES/usage-snapshot.synthetic.json $FIXTURES/usage-query.synthetic.json $FIXTURES/usage-price-scenario.synthetic.json > candidate-report.json
```

The candidate charges 20 CNY minor units per recorded accelerator-second,
scale 2. The example shows:

- `usage-one`: recorded 12000, hypothetical 2400, delta -9600 minor units.
- `usage-two`: recorded 6000, hypothetical 4000, delta -2000 minor units.
- `usage-unpriced`: hypothetical 6000; recorded amount and delta stay unknown.
- `charge-zero`: recorded zero, but no source observation; no hypothetical amount.
- `credit-one`: recorded -2000, retained separately without a hypothetical credit.

These are gross-charge comparisons for the covered events, not a claim of net
savings. Recorded adjustments are neither subtracted from a proposed bill nor
invented as future credits. Retained absence is not zero. The tool cannot infer
whether unpriced events are prepaid, free, unrated, or omitted by the source.

## Edit and reopen a candidate

1. Use an existing authorized commercial snapshot and the same six-field usage
   query described in [the usage explorer](USAGE_EXPLORER_QUICKSTART.md). The
   selected organization, project/meter filters, half-open service window and
   project/cost-center/meter grouping are unchanged. Do not copy credentials.
   Repricing requires permitted raw usage observations. The customer
   `GET /v1/portal/self/commercial` projection intentionally omits them, so its
   charges remain `MissingObservation`; obtain an authorized operator export
   through the existing process if those observations are needed. This tool
   does not expand access or reconstruct omitted observations.
2. Copy `usage-price-scenario.synthetic.json` to a new private file. Change its
   rate identity/version, exact meter/unit, unit price, currency/scale, and UTC
   millisecond effective range. Every rate uses the existing `RateCard` shape:

```json
{
  "schema_version": 1,
  "rates": [{
    "rate_card_id": "analyst-candidate",
    "version": "draft-1",
    "meter": "accelerator-second",
    "unit": "second",
    "unit_price": {"minor_units": "20", "currency": "CNY", "scale": 2},
    "effective_from_unix_ms": "1790726400000",
    "effective_until_unix_ms": "1791504000000"
  }]
}
```

For a counterfactual historical comparison, the draft's effective range must
explicitly cover those historical event intervals. A future-only rate does not
automatically apply to old observations. Edit your private scenario copy, never
an authoritative published rate or the source timestamps.

3. Rerun with your new file. For the synthetic example, changing `"20"` to
   `"30"` changes the first hypothetical amount to 3600 and its delta to -8400;
   its recorded charge remains 12000. Reopening the same file produces identical
   output. Keep each candidate file and the original snapshot/query together.
4. Use `price-rows` to trace groups to event, workload and ledger-entry IDs;
   historical and candidate rate identities have separate columns. `price-json`
   additionally keeps full candidate rates, historical labels/reasons, the
   query, and all result rows. It is a report projection, not an importable
   commercial snapshot. Reproduce it from the three original input files.

Amounts, quantities and timestamps use quoted decimal strings for Int64 JSON
values. No floating-point money, exchange rates, scale conversion, discounts,
taxes, temporal extrapolation or independent pricing formula is introduced.
Hypothetical amounts use the same `estimate_cost` arithmetic as existing
commercial admission/rating: recorded quantity multiplied by exact unit price.
Signed deltas use existing checked money addition/negation.

## Read coverage and grouping correctly

One candidate must cover an event's entire recorded service interval and match
its meter and unit exactly. A start equal to the rate's effective start and an
end equal to its effective end are accepted, as in ledger rating. Intersecting
query records contribute their entire quantities; `crosses_window` remains
visible. The tool does not prorate, split events across adjacent rates, or infer
which rate is preferred. Partial-interval rates are not matching candidates.

Every row has one explicit status:

- `Compared`: observed charge, one covering rate, identical currency and scale.
  Delta is hypothetical minus recorded charge, including positive or zero deltas.
- `EstimatedUnpriced`: observed usage with one covering rate but no recorded
  charge. Hypothetical amount is present; recorded amount and delta are absent.
- `MissingObservation`: recorded charge lacks its source observation. No estimate
  is made from ledger quantity alone, including a recorded zero-price charge.
- `NoCoveringRate`: no candidate matches the complete interval, meter and unit.
- `AmbiguousRate`: more than one candidate covers the event. The matching count
  is shown; no rate is chosen and no hypothetical amount or delta is produced.
- `MoneyUnitMismatch`: a hypothetical amount exists in its own currency/scale,
  but the recorded amount uses a different currency or scale. Delta is absent.
- `RecordedAdjustment`: existing credit/debit/adjustment retained as recorded.
  Its original charge link remains available; it is not independently repriced.

Summary groups separate status, group identity, meter, unit, recorded currency/
scale, and hypothetical currency/scale. They sum only their own rows with checked
Int64 arithmetic. Unknown money remains blank in CSV and null in JSON. There is
no global net total: do not combine differently dimensioned or unresolved groups
into a savings claim. Empty selections return empty arrays or header-only CSV.

## Limits and privacy

- Snapshot/query file and validation rules are inherited from the usage explorer:
  16 MiB snapshot bytes / 8 Mi characters; 16 KiB query; at most 20000 observations,
  entries, projects and cost centers per collection. Validation covers the
  selected organization before filtering, as in the existing explorer.
- Candidate files: 256 KiB bytes / 64 Ki UTF-16 characters, version 1, 1–128 rates.
  Unknown root/rate/money fields and duplicate rate identity/version pairs fail.
  Existing rate validation requires safe identifiers, nonnegative exact prices,
  uppercase three-letter currency, scale 0–9 and increasing positive times.
  Every candidate validates, even if it is outside the selected query.
- Each new output is capped at 16 Mi UTF-16 characters before stdout is written.
  Parsing, invalid references, overflow or size failure yields nonzero exit,
  stderr and empty stdout. Files must remain stable while being read; inherited
  readers cannot detect a same-size concurrent replacement.
- Use new output paths. Shell redirection can truncate a file before the program
  starts; never redirect over any input. The CLI does not edit inputs or stores.
- CSV uses the existing LF record and quoted-text/formula-escape convention.
  Large integer columns should be imported as text in spreadsheets to avoid
  rounding; JSON preserves exact Int64 strings. Text IDs can contain escaped
  formula prefixes; source JSON remains the exact-string reference.
- Reports omit source node/actor fields, credentials, organization legal
  data and other snapshot domains. They retain private usage/commercial IDs and
  candidate prices, so keep inputs and outputs in approved private storage.

This does not authenticate measurements, validate a whole recovery snapshot,
grant billing permissions, prove paid service, or qualify a production price.
Finalized periods remain untouched and can still be explored hypothetically.

## Focused verification

Portable commercial tests run on native and JS. The CLI white-box test executes
the actual native binary through all old/new commands, saves/reopens output,
edits a candidate file, filters usage, checks atomic failures and byte-identical
originals. Set `USAGE_REPORT_EXE`, `USAGE_REPORT_FIXTURES` and
`USAGE_REPORT_EVIDENCE` to the built executable, source fixture directory and an
existing private writable evidence directory. The test fails explicitly if its
configuration is absent. Browser, API/auth, database, hardware and live financial
workflows are outside these focused tests.
