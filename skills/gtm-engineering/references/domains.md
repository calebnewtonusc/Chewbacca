# Competence domains

Each domain needs its own representative tasks, failure taxonomy, evidence, and outcome metric. A domain can remain unverified while another passes.

- Commercial strategy: persona, pricing, packaging, account selection, signal, channel. Test whether an approved offer and buying problem actually support the ICP.
- Signals: distinguish event time from discovery time, verify source and entity, expire stale events, measure incremental predictive value against a no-signal baseline.
- List building: measure reachable market coverage, entity resolution, duplication, role currency, exclusions, and source provenance. Row volume alone is not success.
- Qualification: explicit inclusion and exclusion tests, evidence for each verdict, keep/drop/unknown, missing-data reasons, precision and recall on independently labeled holdouts. A generated rationale is inspectable output, not proof.
- Enrichment: provenance, freshness, validated field yield, disagreement resolution, provider errors separate from no-match, cost per usable record. Waterfall ordering must respect conditional yields and billing rules.
- Copy and sequencing: approved factual claims, persona relevance, timing, stop-on-reply behavior, suppression, and bounded retries. Evaluate human judgments separately from observed campaign outcomes.
- Deliverability: inspect current provider requirements, authentication, suppression, bounce and complaint handling. Do not assume an arbitrary warmup duration guarantees inbox placement.
- CRM and routing: owner and tenant isolation, stable keys, idempotency, conflict handling, destination readback, reply classification and ownership.
- Measurement: explicit denominators, mature cohorts, pending outcomes, confidence intervals, control groups where feasible, held meetings and qualified opportunities instead of raw sends.
- Operations: cost limits, permissions, observability, reversible changes, partial failure recovery, incident handling, and documentation that matches actual deployment.

Clay navigation is a cross-cutting execution capability. Test imports, column configuration, formulas, dependencies, filters, views, lookup joins, enrichment setup, schedules, exports, and recovery separately. Test combinations after individual operations pass.
