# Narrow screens (4:3, 16:10): `NX_TALL`, started 2026-10-26

Goal: on a screen narrower than 16:9 (a 4:3 handheld or tablet, a 16:10 tablet), fill the screen with the 3D instead
of the 16:9 picture with bars above and below. The world gets more view above and below (Vert+: the horizontal view
stays the game's); the HUD and menus keep their shape in a centred 16:9 band.

Status: **written, not yet run**. Compiled (syntax) on the Mac; the vertex patch checked on two test shaders. Every
claim about P5R below is to be confirmed on a device.

## How

It is the mirror of `NX_ULTRAWIDE` (`ultrawide-1710.md`, Wonder), done the way `NX_HUD_1080` sizes P5R's 1280x720
targets: the guest's `Texture` keeps its size; only the `GpuImage` behind it is taller.

ky = (16/9) / (screen aspect): 4/3 at 4:3 (960x540 -> 960x720, 1280x720 -> 1280x960), 10/9 at 16:10.

| part | where | what |
|---|---|---|
| taller images | `nvn_image.cpp`, `tall_texture` (`nvn_ultrawide.cpp`) | 2D textures 16:9 within 3%, render targets (flags 0x8) or window textures (0x1), not video (0x2), storage (0x4) or pitch-linear (0x10, 0x40, a stride: the CPU reads those in guest memory, e.g. the occlusion culling's depth pyramid). Each shape is logged once: `nvn: tall: taller ...` / `kept 16:9 ...` |
| pixel spans | `nvn_draw.cpp`, `nvn_sets.cpp`, `nvn_clears.cpp`, `nvn_copy.cpp`, `nvn_vk.cpp` | viewport and scissor rows, the shaders' viewport size, scissored clears, copy and clear rectangles, the window crop: y and height times ky (offsets rounded down, ends up) |
| no uploads | `nvn_pipeline.cpp`, `nvn_copy.cpp` | a tall image is larger than its guest memory: the GPU fills it (as `img->hud`) |
| 2D squeeze | `nvn_draw.cpp`, `patch_x_scale` | draws into a frame target (`tall_ui_target`: guest 1280x720 or 1920x1080) get `gl_Position.y *= 1/ky` (specialization constant 1 of the patched vertex module), except a short draw (<= 6 vertices) that samples a tall image: a screen-space pass (the post pass that brings the 3D in) that must fill the target. P5R's HUD is depth tested, so Wonder's "no depth test = UI" rule cannot be used |
| camera | `games/p5r/game.cpp`, `tall_cameras` | aspect 16/9 -> 16/9/ky and fovy -> 2 atan(tan(fovy/2) ky), on every camera a heap scan finds |
| launcher | `Launcher.java` | "Screen shape" option: `NX_TALL=0` (default) or `auto`; the display's size goes to the runtime as `NX_TALL_SCREEN` |

The pipeline key's `restart` (a `uint32_t` holding 0 or 1) became `uint8_t restart, uint8_t uw_axis, uint16_t unused`:
the key keeps its size and layout, so the saved pipeline caches (`<cache>.keys`, checked by `sizeof(WarmRec)`) stay
valid. A `static_assert` in `nvn_pipeline.h` holds it there.

### The camera (the unknown part)

Where P5R's Switch build keeps its camera is not known. The guess comes from the PC version (same GFD engine, also
LP64, so the same struct layout is likely): `p5rpc.ultrawide` (github.com/MonoHearted/p5rpc.ultrawide) writes the
camera's aspect at `camera + 0x1ac`; GFDLibrary's camera data is `{near, far, fovy, aspect}`. So the scan looks for the
float 16/9 (`0x3fe38e39`) right after three floats that look like near (0..100], far (near..1e6] and a field of view
(0.05..2.8 rad or 3..160 deg), every 3 s on a worker thread (`p5r-camscan`), and the frame (the interval setter hook,
once per frame) writes the 4:3 values, and again whenever the game writes 16/9 back.

If that guess is wrong the log says so (`p5r tall: no camera found after 10 scans`) and lists the 16/9 floats in the
heap with the words around them: the next step is reading that list for the real layout.

Without a patched camera the 3D is **stretched** 1.33x in height (the targets are taller, the projection is not).

## Switches

| switch | effect |
|---|---|
| `NX_TALL=auto\|<a>:<b>\|<w>x<h>` | on; `auto`: `NX_TALL_SCREEN` (set by the launcher) or the window's size. 16:9 and wider: off. Off when `NX_ULTRAWIDE` is on |
| `NX_TALL_UI=<w>x<h>,...` | the frame targets whose draws are squeezed (default `1280x720,1920x1080`; `none`: none) |
| `NX_TALL_FILL=untextured` | short untextured draws in the frame targets (fades, dimming quads) are not squeezed, so they cover the bands (and so do untextured HUD shapes, which then come out stretched) |
| `NX_TALL_FLAGS0=1` | also make 16:9 textures with no flags taller (Wonder's scene colour has flags 0; an uploaded 16:9 picture then comes out black) |
| `NX_P5R_TALL_CAMERA=0` | no camera patch (the 3D stretched: to compare) |
| `NX_P5R_TALL_FOV=0` | aspect only (Hor-: the game's vertical view, the sides cut) |
| `NX_P5R_CAM_FOV=<bytes>` | the field of view's offset from the aspect (default -4) |
| `NX_P5R_CAM_SCAN_MS=<ms>` | the camera scan's period (default 3000) |
| `NX_UW_TRACE=<first>:<count>` | one `uwdraw` line per draw, now also in tall mode (`wide 1` = a tall target, `scaled 1` = squeezed) |

## First test (what to run, what to send)

1. Launcher: Screen shape -> "Fill 4:3 and 16:10 screens". Start with `adb logcat -s p5r:V > tall-1.txt`.
2. Look at: the title (the 3D Joker fall), a menu, a field (Yongen-Jaya / Shibuya), a battle, a cutscene, a film.
3. Send the log and a screenshot or photo of each. In the log: `nvn: tall:` (screen shape, which targets were made
   taller and which kept), `p5r tall:` (the cameras found and patched, the scan's cost, how often the game writes
   16/9 back), and `a 16:9 target ... samples a tall image` (passes that may read a tall image short).

## Risks to watch in the first run

* **Camera not found**: the 3D stretched vertically. Then the `16/9 at` lines give the layout.
* **A patched non-camera**: random 16/9 data that looked like a camera. Each patch is logged (`p5r tall: camera ...:
  aspect ... fov ...`).
* **Occlusion pop-ins**: P5R's occlusion culling reads a 16:9 depth pyramid made from the (now tall) depth. Through
  texture coordinates it stays right; through texel fetches the pyramid would hold only the top 3/4 of the picture
  (then: buildings hidden or shown wrongly). The `samples a tall image` lines name the shaders to look at.
* **Screen-space shaders** that turn `gl_FragCoord` into texture coordinates with the game's 1/1280, 1/720 constants
  read a tall image's top 3/4 (bloom, blur shifted). Same lines.
* **Fades and menus' dimming** in the frame target are squeezed with the 2D: the bands above and below stay lit during
  a fade to black. `NX_TALL_FILL=untextured` is the alternative.
* **Scan cost**: a pass over the whole heap every 3 s on a worker thread (`camera scan N: <ms> over <MB>`); on the
  Adreno 610 tablet expect hundreds of ms per pass. Replace by a hook on the camera setter once its address is known
  (the camera's first word, logged, may be a vtable that leads there).
* **GPU cost**: 33% more pixels at 4:3 (11% at 16:10).
