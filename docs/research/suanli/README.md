# Suanli documentation research snapshot

This directory records a LunaNexa-focused review of the public documentation at
[suanli.cn/docs](https://suanli.cn/docs/), captured on **2026-08-11**.

The site was downloaded for analysis and every documentation URL advertised by
its sitemap was fetched. The local result is deliberately a source-linked
Markdown knowledge base rather than a verbatim republication of third-party
documentation. It preserves the complete page inventory, architectural facts,
and conclusions needed by this project while the original pages remain the
authoritative source.

## Coverage and method

The visible documentation sidebar exposed 59 links. The sitemap exposed 227
documentation URLs, including pages not mounted in the initial sidebar. The
sitemap therefore formed the completeness boundary.

| Section | Pages fetched |
| --- | ---: |
| Documentation root | 1 |
| Platform overview | 2 |
| Platform, identity, and OpenAPI | 24 |
| Cloud hosting | 41 |
| Flexible deployment and prebuilt services | 74 |
| Batch jobs and queues | 18 |
| Hosted model API | 14 |
| Bare-metal rental | 8 |
| Storage services | 10 |
| Docker tutorials | 12 |
| Billing and expense center | 13 |
| Release notes | 10 |
| **Total** | **227** |

All 227 URLs returned HTTP 200 with non-empty documentation content during the
snapshot. For each page the review captured its URL, title, headings, and enough
page text to classify it. Navigation boilerplate was excluded from the
assessment. The complete source list is in [CATALOG](CATALOG.md).
The [page-by-page notes](PAGE_NOTES.md) provide a compact topic outline and
initial applicability label for each of the 227 pages.

This is a point-in-time review. Suanli can change its sitemap or page contents;
any implementation decision should re-check the linked source before treating a
provider-specific behavior as current.

## Main findings for LunaNexa

Suanli validates several choices already present in LunaNexa:

- keep the OCI runtime image separate from large model artifacts;
- cache or prewarm images and models on the node that will execute them;
- use distinct startup, readiness, and liveness checks for slow-starting model
  servers;
- drain unhealthy or terminating instances before routing traffic;
- expose deterministic APIs for deployment, scaling, jobs, and status;
- meter CPU, memory, GPU utilization, GPU memory, power, and temperature;
- bound queues, retries, concurrency, and scale activity with explicit limits;
- keep model storage external to a container image and mount or materialize it
  read-only at runtime.

The most important difference is the trust and placement model. Suanli is a
general public cloud platform and documents arbitrary cloud hosts, SSH access,
custom Kubernetes YAML, public/private registries, provider credentials, and
cross-region scheduling. LunaNexa is a private management plane for four
explicitly enrolled DGX Spark nodes. It must preserve exclusive-node leases and
copy a verified artifact only to the assigned node. It must not turn the DGX
fleet into general public cloud VMs or give a runtime container direct authority
over `/data/models`.

See [APPLICABILITY](APPLICABILITY.md) for the detailed adopt/adapt/reject matrix
and implementation gaps.

The [commercial control-plane review](COMMERCIAL_CONTROL_PLANE.md) covers cost
centers, metering, budgets, reservations, digital agreements, organization
verification, invoices, payments, SLA credits, privacy, and audit evidence.

## Primary source pages used in the assessment

- [Open API usage](https://suanli.cn/docs/platform/openapi/zx3iwhbv1i8sxdkeiapcprxhn8d/)
- [Open API RSA mode](https://suanli.cn/docs/platform/openapi/m3p6whioxidzwaksughc4gfhnro/)
- [Health checks](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/qxsswhtpfifsuskfwxgcwbstnwb/)
- [Image prewarming](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/caslwb4whih2h8kump9cmrspnyg/)
- [Resource monitoring](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/mgywwvml7ionb1ksgpdcimvmn9e/)
- [Object-storage acceleration](https://suanli.cn/docs/storage-service/object-storage-acceleration/nceowz55diqv9hkid8wcgkosnkg/)
- [Queue management](https://suanli.cn/docs/job-batch-processing/function-usage-instructions/vzbtwhdqxicfqekfnxhcvwfjndd/)
- [Multi-strategy load balancing](https://suanli.cn/docs/flexible-deployment/best-practice/db6owixieidl3gk97nzc99tjn3d/)
- [Multi-container deployments](https://suanli.cn/docs/flexible-deployment/function-usage-instructions/ivnkwepb7ixtwiknmazc5prunmf/)
- [Hosted model API quickstart](https://suanli.cn/docs/large-model-cloud-service/quickstart/cqsrwzrbsim4idkkjbxcdux4nfg/)

## Legal and security notes

The catalog does not copy credentials, private data, model-license material, or
production state. No Suanli examples or images are vendored into LunaNexa. The
review is technical research, not legal advice and not an endorsement of the
provider. Suanli pricing, agreements, service-level promises, and privacy terms
are cataloged for completeness but are not LunaNexa requirements.
