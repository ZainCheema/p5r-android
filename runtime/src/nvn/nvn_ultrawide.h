// Ultrawide (NX_ULTRAWIDE, docs/nvn/studies/ultrawide-1710.md): the game renders a fixed 16:9 picture (its render
// targets are built from 1920x1080 immediates and its cameras assume 16:9). With the switch on, the runtime widens
// every 16:9 colour/depth render target by k = (display aspect) / (16:9), widens viewports, scissors, clears and the
// window crop to match, and scales gl_Position.x of the vertex shaders by 1/k in passes into widened targets, so the
// world keeps its height and shows more to the sides (Hor+). Off (the default): none of this runs.
#pragma once

#include <cstdint>
#include <vector>

namespace nx::nvn {

struct ShaderInfo;
struct Texture;

float uw_factor();                        // k > 1 when on, 1 when off (decided once)
inline bool uw_on() { return uw_factor() > 1.0f; }
uint32_t uw_widen(uint32_t w);            // the widened width of a 16:9-chain size
bool uw_widen_texture(Texture& t);        // a screen-sized render target: width widened, t.uw set
bool uw_crop(int32_t crop[4]);            // nvnWindowSetCrop's rect widened when it is the whole 16:9 picture
// Set by the draw replay before it builds descriptor sets and state: the draw's colour/depth target is a widened one.
extern bool g_uw_wide;
// A guest viewport/scissor span on a widened target: x and width scaled by k, kept inside `extent_w`.
void uw_span(int32_t& x, int32_t& w, uint32_t extent_w);
void uw_cameras(uint64_t present);     // camera aspect patch (called at each present)
void uw_scan(uint64_t present);        // NX_UW_SCAN debug
void uw_ui_vertex_shader(const ShaderInfo* vs);  // learned: drew into a UI layer target
bool uw_is_ui_vertex_shader(const ShaderInfo* vs);
bool uw_vs_scaled(const ShaderInfo* vs);  // does this vertex shader's x get scaled by 1/k (world and UI geometry)
// A copy of a vertex module whose gl_Position.x is multiplied by specialization constant 0 and gl_Position.y by
// specialization constant 1 (both default 1.0).
bool patch_x_scale(const std::vector<uint32_t>& in, std::vector<uint32_t>& out);

// ---- Narrow screens (NX_TALL, docs/nvn/studies/tall-4x3.md) ----------------------------------------------------------
// The mirror of the above for screens narrower than 16:9 (4:3, 16:10): the 16:9 screen-sized render targets get a
// taller GPU image (960x540 -> 960x720 at 4:3), as NX_HUD_1080 does it: the guest's Texture keeps its size, only the
// GpuImage grows (GpuImage::tall), and guest pixel spans on it (viewports, scissors, copy and clear rectangles, the
// window crop) are scaled in y by ky = (16/9) / (screen aspect). The game's camera is made 4:3 by the game
// (games/p5r/game.cpp: same horizontal view, more above and below: Vert+); draws into the frame targets the HUD and
// menus go to (tall_ui_target) get gl_Position.y * 1/ky, so the 2D keeps its shape in a centred 16:9 band.
// NX_TALL=auto (the window's shape) | <a>:<b> | <w>x<h>; 16:9 and wider: off. Off (the default): none of this runs.
bool tall_on();
float tall_factor();                 // ky >= 1 (1 when off)
int32_t tall_up(int32_t v);          // floor(v * ky): an offset
int32_t tall_up_end(int32_t v);      // ceil(v * ky): an end
bool tall_texture(const Texture& t);  // a 16:9 screen-sized render target whose image is made taller
bool tall_ui_target(uint32_t guest_w, uint32_t guest_h);  // a frame target the 2D is drawn into (NX_TALL_UI)
// A guest rectangle {x, y, z, w, h, d} on a tall image: y and height scaled.
inline void tall_rect(int32_t* r) {
    const int32_t y1 = tall_up_end(r[1] + r[4]);
    r[1] = tall_up(r[1]), r[4] = y1 - r[1];
}
// Set by the draw replay: this draw's colour/depth target is a tall image.
extern bool g_tall_target;

}  // namespace nx::nvn
