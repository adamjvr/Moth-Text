# Input-to-Pixel Latency

Convergence C2.3 follows C2.2 exact geometry. C2.2 made the final caret position
correct; C2.3 ensures the correct state is presented promptly during sustained
typing and OS key repeat.

## Ordered batching

LunaHostSDL polls a bounded raw-event batch. Plain printable key-down events defer
to SDL committed text. Adjacent committed-text events concatenate only while they
remain contiguous. Keyboard commands, navigation, pointer input, resize, focus,
and capture-loss events flush pending text and preserve their original order.

Moth therefore receives a rapid character run as one `LunaTextInputEvent` string
and applies it with one document-history insertion. Undo removes the batch as the
same logical typing group, both editor views synchronize, and caret visibility is
resolved once.

## Presentation fairness

The default host budget is 96 raw events or approximately 2 ms. Reaching either
limit is a conservative backlog signal: the host renders and presents, avoids an
extra pacing sleep, then resumes polling. No semantic event is dropped.

## Shaped-layout retention

The exact C2.2 row geometry still requires reshaping the edited row. Moth keeps a
bounded 128-entry, 2 MiB LRU cache so the two pane projections and unchanged rows
reuse layouts without retaining an unbounded chain of historical line prefixes.
Performance snapshots report requests, hits, misses, shaping time, entry count,
and cache cost.

## Acceptance

Hold a printable key for ten seconds, type rapidly on a long row, alternate typing
and Backspace, paste several kilobytes, and type near the bottom viewport edge.
There must be no growing visual backlog, rhythmic repeat stutter, event reordering,
or disagreement between the text and caret presented in one frame.
