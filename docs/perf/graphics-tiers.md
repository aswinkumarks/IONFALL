# Graphics quality tiers (desktop, Radeon Vega iGPU, 1080p)

Measured with `tools/look_capture` (each map alone, then the four characters at
3, 8 and 15 m; GPU time per frame). Means over the 12 shots per preset.

| Preset | main | quality tiers |
|---|---|---|
| Low    | 2.48 ms | 2.64 ms |
| Medium | 3.19 ms | 3.50 ms |
| High   | 7.56 ms | 8.12 ms |
| Ultra  | 9.17 ms | 10.84 ms |

The worst shot per preset moved by at most 0.2 ms on Low, Medium and High.

## Forward+ on desktop: an option, not the default

Forward+ adds ambient occlusion (High, Ultra) and FSR1 upscaling. On this GPU it
costs about twice as much as Mobile for the same scene:

| High preset, Station / Spire map shot | GPU |
|---|---|
| Mobile | 7.3 / 7.2 ms |
| Forward+, SSAO + MSAA 2x | 17.8 / 19.4 ms |
| Forward+, no SSAO | 13.0 / 14.4 ms |
| Forward+, no SSAO, no MSAA | 11.2 / 12.0 ms |
| Low: Forward+ FSR1 / bilinear / Mobile bilinear | 4.2 / 2.6 / 2.3 ms |

The extra cost is in the renderer itself, not in its effects, so Mobile stays
the default and Forward+ is a Video setting for dedicated GPUs
(`Settings.RENDERERS`). The renderer is chosen at startup, so the setting writes
`user://renderer.cfg`, which project.godot names as its
`project_settings_override`; it applies from the next start.

Forward+ (via the setting), means over the 12 shots: Medium 7.84 ms, High
21.23 ms. Its reflection probe is far stronger than Mobile's and tinted every
metal surface with the light strips' cyan; MapDetail lowers it to 0.35 under
Forward+. Measure again on a dedicated-GPU PC (PLAN.md M6).
