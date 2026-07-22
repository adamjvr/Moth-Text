# Interactive Input-to-Pixel Latency

## C2.3 failure

C2.3 attempted to prevent sustained input from starving presentation by limiting
one SDL poll to 96 raw events or approximately 2 ms and presenting between those
batches. Native testing showed the opposite failure: raw acquisition chunks are
not semantic boundaries. A click or command could remain deeper in the SDL queue
while Moth performed several expensive CPU framebuffer renders and presentations.
The demo restoration, committed-text authority, and diagnostics remain valid; the
stateless polling/presentation policy is rejected.

## C2.4 model

Luna now owns a persistent `LunaInteractiveInputScheduler`. It coalesces compatible
pointer motion and committed text across acquisition passes. Pointer down/up,
keyboard commands, navigation, scrolling, resize, capture loss, and quit are
ordering barriers. Pending text or motion is flushed before a barrier. Pointer
activation, fresh key presses, modified commands, and control loss request prompt
dispatch. Unmodified repeat, scroll, and resize streams remain ordered but may
batch within the strict semantic-work and latency limits.

Raw polling limits only bound one acquisition call. They never request a frame.
Semantic input becomes ready for prompt/control events, when the native source is
idle, when text reaches its UTF-8 byte threshold, when queued semantic work reaches
its bounded threshold, or when the oldest timestamp reaches the presentation
deadline. Moth receives an ordered semantic batch, applies its document/history
operations, and Luna presents only if scene invalidation reports a visible change.

## Layout cache hot path

Moth's shaped-layout cache remains bounded to 128 entries and 2 MiB. Cache hits are
now dictionary lookup plus an access-generation update. They do not search or
shift an ordering array. Least-recently-used selection occurs only during bounded
insertion-time eviction. Diagnostics expose eviction count so tests can confirm
that stable hits do not trigger maintenance.

## Acceptance

Native testing must cover clicks and menu commands behind motion storms, rapid text
immediately followed by Ctrl commands, repeat followed by navigation, scroll then
click, pointer capture loss, resize, and idle input. There must be no growing
backlog, semantic reordering, repeated arbitrary presentations, or disagreement
between caret and text. C2.4 acceptance is followed by the paired audit, not M3A.
