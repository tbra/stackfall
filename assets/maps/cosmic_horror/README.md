# Horizon watcher silhouette layers

Three transparent 1600 × 520 SVG layers share the same coordinate system: tendrils behind, body in the middle, crown in front. The neutral preview is `docs/art_mockups/cosmic_horizon_silhouette_preview.svg`. The shape is informed by the horizon watcher mockup but redrawn as a simple silhouette to stay readable at distance.

These are source art assets for the deferred cosmic horror map. The separate layers can move slightly relative to one another for breathing or parallax, but there is no animation, scene wiring, or chromatic effect in this package. Keep the creature behind the arena and avoid placing key gameplay information over its bright eye.

Three optional eye overlays (`horizon_eye_dim.svg`, `horizon_eye_watch.svg`, `horizon_eye_flare.svg`) use the same 1600 × 520 transparent canvas. Show exactly one above the body and crown. Their shape changes with the state, so the effect does not rely on color alone. `docs/art_mockups/cosmic_horizon_eye_states.png` compares them against the same background. A later scene can swap frames or fade between them; this package does not prescribe timing or gameplay triggers.
