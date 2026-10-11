# Run the Evergreen Figma prototype builder

This local development plugin builds **76 editable Figma frames**: 19 screens in dark and light themes, at desktop and mobile sizes. Buttons have native Figma prototype connections. It creates a new page and does not modify existing pages. No network access or account tokens are used.

## Import into Figma

1. Open a design file you can edit in the **Figma desktop app**.
2. Open **Plugins → Development → Import plugin from manifest** and select this folder's `manifest.json`.
3. Run **Evergreen — Clickable Cemetery Prototype** from Development plugins.
4. Select the Desktop or Mobile dark-mode starting flow and click **Present**.

If your Figma version requires a plugin ID, create a new local plugin through **Plugins → Development → New plugin**, then copy the generated manifest's `id` into this manifest. Keep `code.js` as the main file. Do not invent an ID or use an API token.

## Try this journey

Overview → Search → Maria Santos → Save memorial → Find on map → Walking route → Create visit pass → Gate officer check-in → Visit history.

Use **Explore roles / Roles** for admin and lot-owner screens. Theme switches lead to the equivalent screen in the other theme. Search, invalid codes, and successful check-in are linked example states; Figma does not execute the browser prototype's JavaScript or accept live search input.

The builder recreates the original visual direction with native editable text and shapes. It is not a pixel-exact HTML import, an Auto Layout component library, or a binary `.fig` file. Only Maria Santos has a detailed sample journey. Map blocks are illustrative. Text uses Inter and Georgia where available, with installed font fallbacks.

Frames use fixed layouts (1440 × 1024 desktop; 390 × 1120 mobile). All UI elements are directly editable after generation. Re-running adds another page, so run once unless you want another copy.

## Validation status

JavaScript and graph checks can run locally with `node validate.cjs`. Actual import and Present-mode verification require Figma and have not been performed by the assistant. The chat's Figma connection is still unavailable.

API references: https://developers.figma.com/docs/plugins/manifest/ and https://developers.figma.com/docs/plugins/api/properties/nodes-reactions/.
