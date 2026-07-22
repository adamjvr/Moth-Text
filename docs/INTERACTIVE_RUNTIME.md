# Moth Interactive Runtime Integration

Moth does not own the native event scheduler. `MothTextLinux` supplies a
`LunaSDLApplicationScene`; Luna acquires native events, schedules semantic batches,
and presents invalidated frames. Moth owns the meaning of each delivered event:
document transactions, history groups, commands, caret/view state, dirty policy,
and workspace behavior.

A merged `LunaTextInputEvent` is one ordered insertion transaction. Keyboard and
pointer barriers are delivered after all preceding text and before all following
text. Pointer activation, fresh keys, and modified commands request prompt host
dispatch; unmodified repeat streams may batch within Luna's latency/semantic-work
limits without crossing those barriers. The scene returns explicit invalidation
reasons; it does not request frames based on raw queue counts.

Moth's Unicode layout cache uses access generations. Normal hits update one
existing dictionary entry. Insertion may perform a bounded least-generation scan
to restore the 128-entry/2 MiB limits. Performance counters remain observational
and are not painted as a constantly changing editor string.

## Native acceptance and scalability boundary

C2.4 passed ordinary Moth interaction validation: the short-document shell was
snappy and smooth. The large generated-document lockup occurs after semantic input
has been delivered and must be investigated in snapshot projection, text layout,
shaping, framebuffer composition, or presentation. Do not regress to raw polling
batch frames or add host sleeps as a response to the large-document failure.
