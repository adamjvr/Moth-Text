# Post-C2.4 Paired Audit Plan

After C2.4 native acceptance, do not begin M3A immediately. Audit both repositories
and reconvene with findings classified as Critical, High, Medium, Low, or Accepted
Debt.

Review runtime/presentation ownership, SDL scheduling, VSync and sleeping, full
framebuffer costs, text shaping/layout caches, lock scope, per-frame allocations,
snapshot copying, pane duplication, Luna/Moth ownership boundaries, Swift value
and reference semantics, `@unchecked Sendable`, public API shape, error handling,
UTF-8 safety, test categories and missing end-to-end invariants, documentation,
test counts, and roadmap phase labels.

Critical findings block M3A. High findings should be resolved during or before
M3A. Medium findings are scheduled before visible Find/Replace. Low findings and
accepted debt must remain documented with rationale.
