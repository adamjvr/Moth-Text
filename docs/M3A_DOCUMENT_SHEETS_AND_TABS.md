# M3A — Document Sheets and Real Tabs

M3A is the first product phase after the accepted C2.5J scalability baseline.
It replaces Moth's single-document replacement workflow with an ordered,
Moth-owned document-sheet workspace while consuming Luna's existing generic tab
mechanics.

## Product behavior

- New File appends and activates a fresh untitled sheet.
- Open appends a file-backed sheet or activates the already-open canonical file.
- Every sheet owns one `MothFileDocument` and independent primary/secondary view
  state, including caret, selection, preferred column, wrapping, and viewport.
- The sidebar projects a clickable Open Files list from the same sheet collection.
- Clicking a tab activates exactly that sheet.
- Closing a tab targets exactly that sheet and applies Save / Don't Save / Cancel
  only to it.
- Closing the final tab creates a fresh untitled sheet so the editor remains usable.
- Ctrl/Cmd+Tab and Ctrl/Cmd+Shift+Tab traverse documents.
- Ctrl/Cmd+Option+Tab and its Shift variant traverse panes.
- The existing Luna overflow layout keeps the active document visible when many
  tabs exceed the available width.

## Ownership boundary

Moth owns:

- document-sheet identity and ordering;
- file canonicalization and duplicate-open reuse;
- document history and dirty state;
- per-sheet editor-view state;
- activation, close, save-prompt, and future session policy.

Luna owns:

- product-neutral tab layout and overflow;
- stable hit-test and close-button targets;
- tab-strip interaction state;
- tab accessibility projection;
- theme-driven tab anatomy.

No Moth file or session policy is introduced into Luna.

## Performance policy

C2.5J remains the accepted large-document baseline. M3A's primary exit condition
is a complete multi-document workflow. The 5,000- and 50,000-line native runs are
retained as regression gates rather than becoming another optimization campaign.

## Next roadmap phase

M2.2B2 Visible Find/Replace follows M3A. It will target the stable active document
sheet established here and route keyboard, menu, palette, and panel actions through
the existing command authority.
