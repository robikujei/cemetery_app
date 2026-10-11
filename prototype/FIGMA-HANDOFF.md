# Evergreen — Figma prototype handoff

Source: `index.html`, `style.css`, and `app.js` in this directory. This is a preparation document, not a Figma file or a completed import.

## Design setup

- Create desktop frames at 1440 px wide and mobile frames at 390 px wide. Use vertical scrolling for content beyond the viewport.
- Preserve the current Evergreen visual identity and fictional records.
- Start the presentation on Visitor / Overview in dark mode.
- Use editable text, shapes, and components where supported by the import workflow.
- Create reusable navigation, buttons, record rows, badges, search fields, and memorial detail components.
- Keep illustrative-map and demo-pass labels visible.

## Color styles

| Token | Dark | Light |
| --- | --- | --- |
| Background | #101715 | #F5F5EE |
| Panel | #18211E | #FFFEF8 |
| Raised surface | #1D2924 | #ECEFE4 |
| Border | #2D3C34 | #D9DFD0 |
| Primary text | #EDF2E9 | #23382C |
| Secondary text | #9EAFA4 | #647465 |
| Accent | #BEDAA2 | #446C38 |
| On accent | #22331D | #FFFFFF |

Typography: Georgia for display headings; Inter with Segoe UI fallback for interface text. See `style.css` for exact sizes, spacing, and responsive rules.

## Screens and states

| Group | Frames / states |
| --- | --- |
| Visitor | Overview, search results, no results, Block B filter, memorial detail, saved memorial |
| Map | Selected Block A, selected Block B, walking route visible |
| Visit pass | Before generation, generated demo pass, checked-in pass |
| Gate officer | Code entry, invalid code, successful check-in, duplicate check-in |
| History | Empty, completed visit |
| Profile | Display preferences, profile saved |
| Lot owner | My lot, linked memorial, lot location |
| Admin | Dashboard, burial records, lot management, map overview, visitor logs |

Duplicate the main visitor journey in light mode and at mobile width. Use matching dark/light destinations for theme-switch actions.

## Click-through wiring

1. Overview search → search results for Maria Santos.
2. Search result → memorial details overlay; close → previous frame.
3. Save memorial → saved state; remove → unsaved state.
4. Find on map → Block A map selection.
5. Block buttons → matching selected-block frames.
6. Preview walking route → route-visible frame; hide → selected-block frame.
7. Create visit pass → generated pass for the selected memorial.
8. Try gate officer check-in → prefilled code entry.
9. Validate → visitor log containing the new visit.
10. Revalidate the same code → duplicate-check-in feedback.
11. Invalid-code example → pass-not-found feedback.
12. Role selector → each role's landing screen; navigation items → role-specific screens.
13. Appearance toggle → equivalent screen in the other theme.

The browser prototype supports actual text filtering and session state. A Figma recreation must explicitly wire example result states or supported prototype variables; do not assume JavaScript behavior survives screen capture. Demonstrate search using the Maria Santos example and include a separate empty-results state.

## Review checklist

- Verify all navigation and modal close actions in Figma Present mode.
- Verify the visitor → pass → gate officer → history journey.
- Verify dark/light transitions preserve the displayed screen.
- Check mobile navigation scrolling and frame overflow.
- Confirm editable layers after import; screenshots alone are not an editable design.
- Keep sample data, non-scannable pass, and illustrative route limitations visible.

Direct Figma creation and verification remain pending the Figma account connection.
