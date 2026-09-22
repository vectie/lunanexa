# Quote schedule v1

`quote.xlsx` is a reproducible bilingual engineering template, not an approved
legal instrument or a signed quotation. It introduces no contractual terms.
Generate with `moon run scripts/build-offline-quote-template.mbtx
assets/contracts/offline/quote-v1/quote.xlsx` from the LunaNexa root.

Template identity is `offline-quote-v1`, version `1`. All inputs are on sheet
`Quote`: B2 order reference, B3 organization reference, B4 quote reference,
B5 ISO currency, B6 subtotal in currency minor units, B7 tax in minor units,
B9 currency scale. B8 is the protected `SUM(B6:B7)` total formula and cannot
be overwritten by worker replacements. B6/B7/B9 remain numeric after edits.

The dispatcher must derive these inputs from the immutable approved quote,
not customer-supplied totals. For this profile, subtotal, tax
and the tax-inclusive total must remain within 2^53−1; the commercial ledger's
integer-money total remains authoritative and must agree with the generated
schedule. It never independently computes or changes tax policy. Publishing as an approved commercial
template is a separate authenticated action; this file is not auto-registered.

Formula: total `SUM(B6:B7)`. The worker recalculates caches after replacements and before
rendering. The file's zero caches are merely placeholders, never calculation
evidence. The visual font declaration is `Noto Sans CJK SC`; a renderer must
provide a reviewed licensed font profile or explicitly reject it.
