#!/usr/bin/env python3
"""Builds the MaterialYouExpressive Kvantum theme as matugen templates.

Kvantum draws widgets from SVG elements found by id, as 9-patches:
`<name>-<state>` is the interior and `<name>-<state>-{top,topleft,...}` the frame.
This script writes those pieces with `{{colors.<role>.default.hex}}` placeholders,
so matugen renders a theme that follows the wallpaper palette.

Usage: build_m3e_theme.py <output dir>   (writes .svg and .kvconfig)
"""

import os
import sys

NAME = "MaterialYouExpressive"
STATES = ("normal", "focused", "pressed", "toggled", "disabled")
SIDES = ("top", "bottom", "left", "right")
CORNERS = ("topleft", "topright", "bottomleft", "bottomright")


def C(role):
    return "{{colors.%s.default.hex}}" % role


class Svg:
    def __init__(self):
        self.parts = []
        self.x = 0
        self.y = 0
        self.row_h = 0

    def place(self, w, h):
        """Returns a free spot on the canvas for a w*h piece."""
        if self.x + w > 2000:
            self.x = 0
            self.y += self.row_h + 10
            self.row_h = 0
        pos = (self.x, self.y)
        self.x += w + 10
        self.row_h = max(self.row_h, h)
        return pos

    def group(self, id_, x, y, w, h, body):
        # The transparent rect pins the element bounds to the full piece
        self.parts.append(
            f'<g id="{id_}"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#000000" fill-opacity="0"/>{body}</g>'
        )

    def render(self):
        height = self.y + self.row_h + 10
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="{height}" viewBox="0 0 2000 {height}">\n'
            + "\n".join(self.parts)
            + "\n</svg>\n"
        )


def fill(color, opacity):
    if opacity >= 1:
        return f'fill="{color}"'
    return f'fill="{color}" fill-opacity="{opacity}"'


def corner_path(x, y, f, d, r, corner):
    """Area of a corner piece covered by a rounded rect inset by d with radius r."""
    s = f - d  # extent of the shape inside the piece
    if s <= 0:
        return ""
    r = max(0.0, min(r, s))
    # Built for topleft in local coords, then mirrored
    pts = []
    if r > 0:
        path = [("M", d, d + r), ("A", d + r, d), ("L", f, d), ("L", f, f), ("L", d, f), ("Z",)]
    else:
        path = [("M", d, d), ("L", f, d), ("L", f, f), ("L", d, f), ("Z",)]
    mx = corner.endswith("right")
    my = corner.startswith("bottom")

    def tx(px, py):
        return (x + (f - px if mx else px), y + (f - py if my else py))

    sweep = 1 if mx == my else 0
    for seg in path:
        if seg[0] == "Z":
            pts.append("Z")
        elif seg[0] == "A":
            px, py = tx(seg[1], seg[2])
            pts.append(f"A{r:g},{r:g} 0 0 {sweep} {px:g},{py:g}")
        else:
            px, py = tx(seg[1], seg[2])
            pts.append(f"{seg[0]}{px:g},{py:g}")
    return " ".join(pts)


def side_rect(x, y, f, length, d, side):
    """Rect of an edge piece covered by a shape inset by d."""
    if f - d <= 0:
        return None
    if side == "top":
        return (x, y + d, length, f - d)
    if side == "bottom":
        return (x, y, length, f - d)
    if side == "left":
        return (x + d, y, f - d, length)
    return (x, y, f - d, length)


def frame(svg, name, f, layers, interior=True, sides=SIDES, size=None):
    """9-patch element. layers: list of (color, opacity, inset, radius, ring_width).

    ring_width 0 = filled shape, otherwise only a ring of that width.
    f is the frame width (the corner size in the SVG, Kvantum scales it).
    """
    length = 20
    for corner in CORNERS:
        x, y = svg.place(f, f)
        body = ""
        for color, op, d, r, ring in layers:
            p = corner_path(x, y, f, d, r, corner)
            if not p:
                continue
            if ring:
                p += " " + corner_path(x, y, f, d + ring, max(r - ring, 0), corner)
                body += f'<path d="{p}" {fill(color, op)} fill-rule="evenodd"/>'
            else:
                body += f'<path d="{p}" {fill(color, op)}/>'
        if corner_visible(corner, sides):
            svg.group(f"{name}-{corner}", x, y, f, f, body)
    for side in SIDES:
        w, h = (length, f) if side in ("top", "bottom") else (f, length)
        x, y = svg.place(w, h)
        body = ""
        for color, op, d, r, ring in layers:
            rect = side_rect(x, y, f, length, d, side)
            if not rect:
                continue
            rx, ry, rw, rh = rect
            if ring:
                if side == "top":
                    rh = min(rh, ring)
                elif side == "bottom":
                    ry, rh = ry + rh - min(rh, ring), min(rh, ring)
                elif side == "left":
                    rw = min(rw, ring)
                else:
                    rx, rw = rx + rw - min(rw, ring), min(rw, ring)
            body += f'<rect x="{rx:g}" y="{ry:g}" width="{rw:g}" height="{rh:g}" {fill(color, op)}/>'
        if side in sides:
            svg.group(f"{name}-{side}", x, y, w, h, body)
    if interior:
        x, y = svg.place(length, length)
        body = "".join(
            f'<rect x="{x}" y="{y}" width="{length}" height="{length}" {fill(color, op)}/>'
            for color, op, d, r, ring in layers
            if not ring
        )
        svg.group(name, x, y, length, length, body)


def corner_visible(corner, sides):
    v = "top" if corner.startswith("top") else "bottom"
    h = "left" if corner.endswith("left") else "right"
    return v in sides and h in sides


def icon(svg, id_, size, body_fn):
    x, y = svg.place(size, size)
    svg.group(id_, x, y, size, size, body_fn(x, y))


def stroke_path(d, color, width, opacity=1):
    op = "" if opacity >= 1 else f' stroke-opacity="{opacity}"'
    return (
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{op} '
        'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def chevron(direction, color, opacity=1, size=16, width=2):
    def body(x, y):
        s = size
        pts = {
            "down": [(0.3, 0.4), (0.5, 0.6), (0.7, 0.4)],
            "up": [(0.3, 0.6), (0.5, 0.4), (0.7, 0.6)],
            "left": [(0.6, 0.3), (0.4, 0.5), (0.6, 0.7)],
            "right": [(0.4, 0.3), (0.6, 0.5), (0.4, 0.7)],
        }[direction]
        d = "M" + " L".join(f"{x + px * s:g},{y + py * s:g}" for px, py in pts)
        return stroke_path(d, color, width, opacity)

    return body


def plus_minus(kind, color, opacity=1, size=16, width=2):
    def body(x, y):
        s = size
        d = f"M{x + s * 0.3:g},{y + s / 2:g} L{x + s * 0.7:g},{y + s / 2:g}"
        if kind == "plus":
            d += f" M{x + s / 2:g},{y + s * 0.3:g} L{x + s / 2:g},{y + s * 0.7:g}"
        return stroke_path(d, color, width, opacity)

    return body


def cross(color, opacity=1, size=16, width=1.6):
    def body(x, y):
        s = size
        a, b = 0.32, 0.68
        d = (
            f"M{x + s * a:g},{y + s * a:g} L{x + s * b:g},{y + s * b:g} "
            f"M{x + s * b:g},{y + s * a:g} L{x + s * a:g},{y + s * b:g}"
        )
        return stroke_path(d, color, width, opacity)

    return body


def build_svg():
    svg = Svg()
    on_s = C("on_surface")
    on_sv = C("on_surface_variant")

    # --- Buttons: tonal pill, morphs to a squarer shape while pressed ------
    f = 10
    frame(svg, "button-normal", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "button-focused", f, [(C("secondary_container"), 1, 0, f, 0), (C("on_secondary_container"), 0.08, 0, f, 0)])
    frame(svg, "button-pressed", f, [(C("secondary_container"), 1, 0, f * 0.45, 0), (C("on_secondary_container"), 0.12, 0, f * 0.45, 0)])
    frame(svg, "button-toggled", f, [(C("primary"), 1, 0, f, 0)])
    frame(svg, "button-disabled", f, [(on_s, 0.12, 0, f, 0)])

    # --- Tool buttons: flat, state layer pill on hover, tonal when checked --
    frame(svg, "tbutton-normal", f, [])
    frame(svg, "tbutton-focused", f, [(on_s, 0.08, 0, f, 0)])
    frame(svg, "tbutton-pressed", f, [(on_s, 0.12, 0, f * 0.45, 0)])
    frame(svg, "tbutton-toggled", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "tbutton-disabled", f, [])

    # --- Text fields and combos: filled pill, primary ring when focused ---
    f = 12
    field = C("surface_container_highest")
    frame(svg, "lineedit-normal", f, [(field, 1, 0, f, 0)])
    frame(svg, "lineedit-focused", f, [(field, 1, 0, f, 0), (C("primary"), 1, 0, f, 1.2)])
    frame(svg, "lineedit-disabled", f, [(on_s, 0.06, 0, f, 0)])
    frame(svg, "combo-normal", f, [(field, 1, 0, f, 0)])
    frame(svg, "combo-focused", f, [(field, 1, 0, f, 0), (on_s, 0.08, 0, f, 0)])
    frame(svg, "combo-pressed", f, [(field, 1, 0, f * 0.5, 0), (on_s, 0.12, 0, f * 0.5, 0)])
    frame(svg, "combo-toggled", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "combo-disabled", f, [(on_s, 0.06, 0, f, 0)])

    # --- Item views: rounded selection, hover state layer -----------------
    f = 12
    frame(svg, "itemview-focused", f, [(on_s, 0.08, 0, f, 0)])
    frame(svg, "itemview-pressed", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "itemview-toggled", f, [(C("secondary_container"), 1, 0, f, 0)])

    # --- Menus --------------------------------------------------------------
    # Menu and tooltip edges live in their shadow pieces (see shadow())
    frame(svg, "menu-normal", 12, [(C("surface_container_high"), 1, 0, 0, 0)])
    f = 8
    # Kvantum draws the highlighted menu item with the "normal" state
    frame(svg, "menuitem-normal", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "menubar-normal", 2, [])
    frame(svg, "menubaritem-focused", 8, [(on_s, 0.08, 0, 8, 0)])
    frame(svg, "menubaritem-pressed", 8, [(C("secondary_container"), 1, 0, 8, 0)])
    frame(svg, "menubaritem-toggled", 8, [(C("secondary_container"), 1, 0, 8, 0)])
    shadow(svg, "menu-shadow", 18, 6, 0.32, C("surface_container_high"))
    shadow(svg, "tooltip-shadow", 14, 6, 0.26, C("inverse_surface"))

    # --- Tooltips: inverse surface ------------------------------------------
    frame(svg, "tooltip-normal", 8, [(C("inverse_surface"), 1, 0, 0, 0)])

    # --- Tabs: tonal pill for the current tab ------------------------------
    f = 10
    frame(svg, "tab-normal", f, [])
    frame(svg, "tab-focused", f, [(on_s, 0.08, 0, f, 0)])
    frame(svg, "tab-toggled", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "tab-disabled", f, [])
    frame(svg, "tabframe-normal", 12, [(C("surface_container_low"), 1, 0, 12, 0)])

    # --- Headers of detail views: flat with a hairline under ----------------
    frame(svg, "header-normal", 2, [(C("outline_variant"), 1, 0, 0, 1)], sides=("bottom",))
    frame(svg, "header-focused", 2, [(on_s, 0.08, 0, 0, 0)])
    frame(svg, "header-pressed", 2, [(on_s, 0.12, 0, 0, 0)])
    frame(svg, "header-toggled", 2, [(C("outline_variant"), 1, 0, 0, 1)], sides=("bottom",))

    # --- Group boxes, docks, generic frames ---------------------------------
    frame(svg, "common-normal", 12, [(C("surface_container_low"), 1, 0, 12, 0)])
    frame(svg, "common-focused", 12, [(C("surface_container_low"), 1, 0, 12, 0)])
    frame(svg, "dock-normal", 2, [])
    frame(svg, "toolbar-normal", 2, [])

    # --- Progress bars: secondary track, primary indicator, both pills ------
    f = 6
    frame(svg, "progress-normal", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "progress-pattern-normal", f, [(C("primary"), 1, 0, f, 0)])
    frame(svg, "progress-pattern-disabled", f, [(on_s, 0.38, 0, f, 0)])

    # --- Scrollbars: thin overlay pill -------------------------------------
    f = 4
    frame(svg, "scrollbarslider-normal", f, [(on_sv, 0.45, 0, f, 0)])
    frame(svg, "scrollbarslider-focused", f, [(on_sv, 0.7, 0, f, 0)])
    frame(svg, "scrollbarslider-pressed", f, [(C("primary"), 1, 0, f, 0)])
    frame(svg, "scrollbarslider-disabled", f, [(on_s, 0.12, 0, f, 0)])

    # --- Sliders: thick tonal track, tall narrow handle ---------------------
    f = 6
    frame(svg, "slider-normal", f, [(C("secondary_container"), 1, 0, f, 0)])
    frame(svg, "slider-toggled", f, [(C("primary"), 1, 0, f, 0)])
    frame(svg, "slider-disabled", f, [(on_s, 0.12, 0, f, 0)])
    for state, color, op in (
        ("normal", C("primary"), 1),
        ("focused", C("primary"), 1),
        ("pressed", C("primary"), 1),
        ("disabled", on_s, 0.38),
    ):
        handle_w = 3 if state == "pressed" else 4

        def handle(x, y, hw=handle_w, color=color, op=op):
            return f'<rect x="{x + 10 - hw / 2:g}" y="{y + 1}" width="{hw}" height="22" rx="{hw / 2:g}" {fill(color, op)}/>'

        x, y = svg.place(20, 24)
        svg.group(f"slidercursor-{state}", x, y, 20, 24, handle(x, y))
        x, y = svg.place(20, 24)
        svg.group(f"slidercursor-tickless-{state}", x, y, 20, 24, handle(x, y))
    icon(svg, "slider-tick-normal", 4, lambda x, y: f'<circle cx="{x + 2}" cy="{y + 2}" r="1.5" {fill(on_sv, 0.6)}/>')

    # --- Check boxes and radio buttons --------------------------------------
    for prefix in ("", "menu-"):
        for state in ("normal", "focused", "pressed", "disabled"):
            dis = state == "disabled"
            border = on_s if state in ("focused", "pressed") else on_sv
            bop = 0.38 if dis else 1
            accent = on_s if dis else C("primary")
            aop = 0.38 if dis else 1
            mark = C("surface") if dis else C("on_primary")

            def box(x, y, border=border, bop=bop):
                return (
                    f'<rect x="{x + 3}" y="{y + 3}" width="18" height="18" rx="3" fill="none" '
                    f'stroke="{border}" stroke-opacity="{bop}" stroke-width="2"/>'
                )

            def checked(x, y, accent=accent, aop=aop, mark=mark):
                return (
                    f'<rect x="{x + 2}" y="{y + 2}" width="20" height="20" rx="4" {fill(accent, aop)}/>'
                    + stroke_path(f"M{x + 7},{y + 12.2} L{x + 10.5},{y + 15.5} L{x + 17},{y + 8.8}", mark, 2.2)
                )

            def tristate(x, y, accent=accent, aop=aop, mark=mark):
                return f'<rect x="{x + 2}" y="{y + 2}" width="20" height="20" rx="4" {fill(accent, aop)}/>' + stroke_path(
                    f"M{x + 7.5},{y + 12} L{x + 16.5},{y + 12}", mark, 2.2
                )

            def radio(x, y, border=border, bop=bop):
                return f'<circle cx="{x + 12}" cy="{y + 12}" r="9" fill="none" stroke="{border}" stroke-opacity="{bop}" stroke-width="2"/>'

            def radio_on(x, y, accent=accent, aop=aop):
                a = f'stroke="{accent}"' + ("" if aop >= 1 else f' stroke-opacity="{aop}"')
                return (
                    f'<circle cx="{x + 12}" cy="{y + 12}" r="9" fill="none" {a} stroke-width="2"/>'
                    f'<circle cx="{x + 12}" cy="{y + 12}" r="5" {fill(accent, aop)}/>'
                )

            icon(svg, f"{prefix}checkbox-{state}", 24, box)
            icon(svg, f"{prefix}checkbox-checked-{state}", 24, checked)
            icon(svg, f"{prefix}checkbox-tristate-{state}", 24, tristate)
            icon(svg, f"{prefix}radio-{state}", 24, radio)
            icon(svg, f"{prefix}radio-checked-{state}", 24, radio_on)

    # --- Arrows and small glyphs --------------------------------------------
    arrow_colors = {
        # prefix: {state: (color, opacity)}
        "arrow": {"normal": (on_sv, 1), "focused": (on_s, 1), "pressed": (on_s, 1), "toggled": (C("on_primary"), 1), "disabled": (on_s, 0.38)},
        "carrow": {"normal": (on_sv, 1), "focused": (on_s, 1), "pressed": (on_s, 1), "toggled": (C("on_secondary_container"), 1), "disabled": (on_s, 0.38)},
        "tarrow": {"normal": (on_sv, 1), "focused": (on_s, 1), "pressed": (on_s, 1), "toggled": (C("on_secondary_container"), 1), "disabled": (on_s, 0.38)},
        "flat-arrow": {"normal": (on_sv, 1), "focused": (on_s, 1), "pressed": (on_s, 1), "toggled": (on_s, 1), "disabled": (on_s, 0.38)},
        "menuitem-arrow": {"normal": (on_sv, 1), "focused": (C("on_secondary_container"), 1), "pressed": (C("on_secondary_container"), 1), "toggled": (C("on_secondary_container"), 1), "disabled": (on_s, 0.38)},
    }
    for prefix, states in arrow_colors.items():
        for direction in ("down", "up", "left", "right"):
            for state, (color, op) in states.items():
                icon(svg, f"{prefix}-{direction}-{state}", 16, chevron(direction, color, op))
    for state, (color, op) in arrow_colors["arrow"].items():
        icon(svg, f"arrow-plus-{state}", 16, plus_minus("plus", color, op))
        icon(svg, f"arrow-minus-{state}", 16, plus_minus("minus", color, op))
        icon(svg, f"spin-plus-{state}", 16, plus_minus("plus", color, op))
        icon(svg, f"spin-minus-{state}", 16, plus_minus("minus", color, op))
        icon(svg, f"spin-up-{state}", 16, chevron("up", color, op))
        icon(svg, f"spin-down-{state}", 16, chevron("down", color, op))
        icon(svg, f"tree-plus-{state}", 16, chevron("right", color, op))
        icon(svg, f"tree-minus-{state}", 16, chevron("down", color, op))
    icon(svg, "arrow-menu-normal", 16, chevron("right", on_sv))
    icon(svg, "arrow-menu-disabled", 16, chevron("right", on_s, 0.38))
    for state, (color, op) in {"normal": (on_sv, 1), "focused": (C("error"), 1), "pressed": (C("error"), 1)}.items():
        icon(svg, f"tab-close-{state}", 16, cross(color, op))
        for mdi in ("close", "minimize", "maximize", "restore"):
            icon(svg, f"mdi-{mdi}-{state}", 16, cross(color, op))
    for state, op in (("normal", 0.45), ("focused", 0.7), ("pressed", 1)):
        icon(svg, f"grip-{state}", 8, lambda x, y: "")
        icon(svg, f"splitter-grip-{state}", 8, lambda x, y: "")
        icon(svg, f"resize-grip-{state}", 16, lambda x, y, op=op: stroke_path(f"M{x + 13},{y + 6} L{x + 6},{y + 13} M{x + 13},{y + 10} L{x + 10},{y + 13}", on_sv, 1.5, op))
    icon(svg, "splitter-normal", 4, lambda x, y: "")
    icon(svg, "toolbar-handle", 8, lambda x, y: "")
    return svg.render()


def shadow(svg, name, size, hint, opacity, body):
    """Shadow pieces of a composited popup (menu, tooltip).

    Kvantum paints these in the popup's frame band instead of the frame, so each
    piece holds the outer shadow (`hint` units thick, the hint elements tell
    Kvantum that thickness) and the rounded body edge (the remaining units).
    """
    color = C("shadow")
    s, length = size, 20
    radius = s - hint

    def stops(start):
        return (
            f'<stop offset="{start:g}" stop-color="{color}" stop-opacity="{opacity}"/>'
            f'<stop offset="1" stop-color="{color}" stop-opacity="0"/>'
        )

    for side in SIDES:
        w, h = (length, s) if side in ("top", "bottom") else (s, length)
        x, y = svg.place(w, h)
        # Shadow band on the outer side, body on the inner side
        if side == "top":
            sh, bd, vec = (x, y, w, hint), (x, y + hint, w, s - hint), (0, 1, 0, 0)
        elif side == "bottom":
            sh, bd, vec = (x, y + s - hint, w, hint), (x, y, w, s - hint), (0, 0, 0, 1)
        elif side == "left":
            sh, bd, vec = (x, y, hint, h), (x + hint, y, s - hint, h), (1, 0, 0, 0)
        else:
            sh, bd, vec = (x + s - hint, y, hint, h), (x, y, s - hint, h), (0, 0, 1, 0)
        gid = f"{name}-{side}-g"
        svg.parts.append(
            f'<defs><linearGradient id="{gid}" x1="{vec[0]}" y1="{vec[1]}" x2="{vec[2]}" y2="{vec[3]}">{stops(0)}</linearGradient></defs>'
        )
        svg.group(
            f"{name}-{side}", x, y, w, h,
            f'<rect x="{sh[0]}" y="{sh[1]}" width="{sh[2]}" height="{sh[3]}" fill="url(#{gid})"/>'
            f'<rect x="{bd[0]}" y="{bd[1]}" width="{bd[2]}" height="{bd[3]}" fill="{body}"/>',
        )
        hw, hh = (2, hint) if side in ("top", "bottom") else (hint, 2)
        hx, hy = svg.place(hw, hh)
        svg.group(f"{name}-hint-{side}", hx, hy, hw, hh, "")
    for corner in CORNERS:
        x, y = svg.place(s, s)
        cx = x if corner.endswith("right") else x + s
        cy = y if corner.startswith("bottom") else y + s
        gid = f"{name}-{corner}-g"
        svg.parts.append(
            f'<defs><radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{s}" gradientUnits="userSpaceOnUse">{stops(radius / s)}</radialGradient></defs>'
        )
        svg.group(
            f"{name}-{corner}", x, y, s, s,
            f'<rect x="{x}" y="{y}" width="{s}" height="{s}" fill="url(#{gid})"/>'
            f'<path d="{corner_path(x, y, s, hint, radius, corner)}" fill="{body}"/>',
        )


def build_kvconfig():
    on_s, on_sv = C("on_surface"), C("on_surface_variant")
    on_sc = C("on_secondary_container")
    return f"""[%General]
author=illogical-impulse
comment=Material 3 Expressive, rendered by matugen from the wallpaper palette
x11drag=menubar_and_primary_toolbar
alt_mnemonic=true
left_tabs=false
attach_active_tab=false
mirror_doc_tabs=false
group_toolbar_buttons=false
toolbar_item_spacing=2
toolbar_interior_spacing=4
spread_progressbar=true
composite=true
menu_shadow_depth=6
tooltip_shadow_depth=7
spread_menuitems=false
splitter_width=1
scroll_width=8
scroll_arrows=false
scroll_min_extent=48
slider_width=12
slider_handle_width=20
slider_handle_length=24
tickless_slider_handle_size=24
center_toolbar_handle=true
check_size=22
textless_progressbar=false
progressbar_thickness=8
menubar_mouse_tracking=true
toolbutton_style=0
double_click=false
translucent_windows=false
blurring=false
popup_blurring=false
vertical_spin_indicators=false
spin_button_width=28
fill_rubberband=false
merge_menubar_with_toolbar=true
small_icon_size=16
large_icon_size=32
button_icon_size=16
toolbar_icon_size=16
combo_as_lineedit=false
animate_states=true
button_contents_shift=false
combo_menu=true
hide_combo_checkboxes=true
combo_focus_rect=false
groupbox_top_label=true
inline_spin_indicators=true
joined_inactive_tabs=false
layout_spacing=6
layout_margin=8
scrollbar_in_view=true
transient_scrollbar=true
transient_groove=false
submenu_overlap=0
tooltip_delay=-1
tree_branch_line=false
no_window_pattern=false
opaque=kaffeine,kmplayer,subtitlecomposer,kdenlive,vlc,smplayer,smplayer2,avidemux,avidemux2_qt4,avidemux3_qt4,avidemux3_qt5,kamoso,QtCreator,VirtualBox,trojita,dragon,digikam
reduce_window_opacity=0
respect_DE=true
scrollable_menu=false
submenu_delay=150
no_inactiveness=false
reduce_menu_opacity=0
click_behavior=0
contrast=1.00
dialog_button_layout=0
intensity=1.00
saturation=1.00
shadowless_popup=false
drag_from_buttons=false
menu_blur_radius=0
tooltip_blur_radius=0
dark_titlebar=true

[GeneralColors]
window.color={C("surface_container")}
base.color={C("surface")}
alt.base.color={C("surface_container_low")}
button.color={C("surface_container_high")}
light.color={C("surface_container_highest")}
mid.light.color={C("surface_container_high")}
dark.color={C("surface_container_lowest")}
mid.color={C("outline_variant")}
highlight.color={C("secondary_container")}
inactive.highlight.color={C("secondary_container")}
text.color={on_s}
window.text.color={on_s}
button.text.color={on_s}
disabled.text.color={C("outline")}
tooltip.text.color={C("inverse_on_surface")}
highlight.text.color={on_sc}
link.color={C("primary")}
link.visited.color={C("tertiary")}
progress.indicator.text.color={on_s}

[Hacks]
transparent_ktitle_label=true
transparent_dolphin_view=false
transparent_pcmanfm_sidepane=true
blur_translucent=false
transparent_menutitle=true
respect_darkness=true
kcapacitybar_as_progressbar=true
force_size_grip=false
iconless_pushbutton=false
iconless_menu=false
disabled_icon_opacity=50
lxqtmainmenu_iconsize=16
normal_default_pushbutton=true
single_top_toolbar=true
tint_on_mouseover=0
transparent_pcmanfm_view=false
no_selection_tint=true
transparent_arrow_button=true
middle_click_scroll=false
opaque_colors=false
kinetic_scrolling=false
scroll_jump_workaround=true
centered_forms=false
noninteger_translucency=false
style_vertical_toolbars=false
blur_only_active_window=false

[PanelButtonCommand]
frame=true
frame.element=button
frame.top=10
frame.bottom=10
frame.left=10
frame.right=10
frame.expansion=200
interior=true
interior.element=button
indicator.element=arrow
indicator.size=16
text.normal.color={on_sc}
text.focus.color={on_sc}
text.press.color={on_sc}
text.toggle.color={C("on_primary")}
text.disabled.color={C("outline")}
text.shadow=0
text.margin.top=0
text.margin.bottom=0
text.margin.left=6
text.margin.right=6
text.iconspacing=8
text.bold=false
min_height=+0.5font
min_width=+3font

[PanelButtonTool]
inherits=PanelButtonCommand
min_width=0

[ToolbarButton]
frame=true
frame.element=tbutton
interior.element=tbutton
frame.top=10
frame.bottom=10
frame.left=10
frame.right=10
frame.expansion=200
indicator.element=tarrow
indicator.size=16
text.normal.color={on_sv}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_sc}
text.bold=false
text.margin=2

[Dock]
inherits=PanelButtonCommand
interior=false
frame=false
text.normal.color={on_s}

[DockTitle]
inherits=PanelButtonCommand
frame=false
interior=false
text.normal.color={on_sv}
text.focus.color={on_s}
text.bold=true

[IndicatorSpinBox]
inherits=LineEdit
indicator.element=spin
indicator.size=16
text.normal.color={on_s}

[RadioButton]
inherits=PanelButtonCommand
frame=false
interior.element=radio
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_s}
min_width=0
min_height=0

[CheckBox]
inherits=PanelButtonCommand
frame=false
interior.element=checkbox
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_s}
min_width=0
min_height=0

[Focus]
frame=false

[GenericFrame]
inherits=PanelButtonCommand
frame=false
interior=false
frame.element=common
interior.element=common
frame.top=12
frame.bottom=12
frame.left=12
frame.right=12
frame.expansion=0
text.normal.color={on_s}

[LineEdit]
inherits=PanelButtonCommand
frame.element=lineedit
interior.element=lineedit
frame.top=12
frame.bottom=12
frame.left=12
frame.right=12
frame.expansion=200
text.margin.top=0
text.margin.bottom=0
text.margin.left=2
text.margin.right=2
text.normal.color={on_s}
text.focus.color={on_s}
min_height=0
min_width=0

[ToolbarLineEdit]
inherits=LineEdit

[DropDownButton]
inherits=PanelButtonCommand
indicator.element=arrow-down

[IndicatorArrow]
indicator.element=arrow
indicator.size=16

[ToolboxTab]
inherits=PanelButtonCommand
text.normal.color={on_s}
text.press.color={on_sc}
text.focus.color={on_s}

[Tab]
inherits=PanelButtonCommand
frame.element=tab
interior.element=tab
indicator.element=tab
indicator.size=16
frame.top=10
frame.bottom=10
frame.left=10
frame.right=10
frame.expansion=200
text.margin.left=10
text.margin.right=10
text.margin.top=0
text.margin.bottom=0
text.normal.color={on_sv}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_sc}
text.bold=false
min_width=0
min_height=0

[TabFrame]
inherits=PanelButtonCommand
frame.element=tabframe
interior.element=tabframe
frame.top=12
frame.bottom=12
frame.left=12
frame.right=12
frame.expansion=0

[TabBarFrame]
inherits=GenericFrame
frame=false
interior=false

[TreeExpander]
inherits=PanelButtonCommand
indicator.size=16
indicator.element=tree

[HeaderSection]
inherits=PanelButtonCommand
interior.element=header
frame.element=header
frame.top=0
frame.bottom=2
frame.left=0
frame.right=0
frame.expansion=0
text.margin.left=8
text.margin.right=8
text.normal.color={on_sv}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_s}
text.bold=false
min_width=0
min_height=0

[SizeGrip]
indicator.element=resize-grip

[Toolbar]
inherits=PanelButtonCommand
indicator.element=toolbar
indicator.size=0
text.margin=0
interior=false
frame=false
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_sc}
frame.expansion=0

[Slider]
inherits=PanelButtonCommand
frame.element=slider
interior.element=slider
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
frame.expansion=200
focusFrame=false

[SliderCursor]
inherits=PanelButtonCommand
frame=false
interior.element=slidercursor

[Progressbar]
inherits=PanelButtonCommand
frame.element=progress
interior.element=progress
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
frame.expansion=200
text.margin=0
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_s}
text.bold=false
min_width=0
min_height=0

[ProgressbarContents]
inherits=PanelButtonCommand
frame=true
frame.element=progress-pattern
interior.element=progress-pattern
frame.top=6
frame.bottom=6
frame.left=6
frame.right=6
frame.expansion=200

[ItemView]
inherits=PanelButtonCommand
frame.element=itemview
interior.element=itemview
frame.top=12
frame.bottom=12
frame.left=12
frame.right=12
frame.expansion=48
text.margin.top=0
text.margin.bottom=0
text.margin.left=6
text.margin.right=6
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_sc}
text.toggle.color={on_sc}
min_width=0
min_height=+0.6font

[Splitter]
interior=false
frame=false
indicator.size=0

[Scrollbar]
inherits=PanelButtonCommand
indicator.element=arrow
indicator.size=0

[ScrollbarSlider]
inherits=PanelButtonCommand
frame.element=scrollbarslider
interior.element=scrollbarslider
interior=true
frame.top=4
frame.bottom=4
frame.left=4
frame.right=4
frame.expansion=200
indicator.element=grip
indicator.size=0

[ScrollbarGroove]
inherits=PanelButtonCommand
interior=false
frame=false

[Menu]
inherits=PanelButtonCommand
frame.element=menu
interior.element=menu
frame.top=18
frame.bottom=18
frame.left=18
frame.right=18
frame.expansion=0
text.normal.color={on_s}
text.shadow=false
text.bold=false

[MenuItem]
inherits=PanelButtonCommand
frame=true
frame.element=menuitem
interior.element=menuitem
indicator.element=menuitem
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
frame.expansion=0
text.margin.top=0
text.margin.bottom=0
text.margin.left=6
text.margin.right=6
text.normal.color={on_s}
text.focus.color={on_sc}
text.press.color={on_sc}
text.toggle.color={on_sc}
text.bold=false
min_width=0
min_height=+0.4font

[MenuBar]
inherits=PanelButtonCommand
frame=false
interior=false
text.normal.color={on_s}
frame.expansion=0

[MenuBarItem]
inherits=PanelButtonCommand
interior=true
interior.element=menubaritem
frame.element=menubaritem
frame.top=8
frame.bottom=8
frame.left=8
frame.right=8
frame.expansion=200
text.margin.left=4
text.margin.right=4
text.margin.top=0
text.margin.bottom=0
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_sc}
text.toggle.color={on_sc}
min_width=0
min_height=0

[TitleBar]
inherits=PanelButtonCommand
frame=false
interior=false
indicator.size=16
indicator.element=mdi
text.normal.color={on_sv}
text.focus.color={on_s}
text.bold=true
text.italic=false

[ComboBox]
inherits=PanelButtonCommand
frame.element=combo
interior.element=combo
indicator.element=carrow
frame.top=10
frame.bottom=10
frame.left=12
frame.right=12
frame.expansion=200
text.margin.top=0
text.margin.bottom=0
text.margin.left=4
text.margin.right=4
text.normal.color={on_s}
text.focus.color={on_s}
text.press.color={on_s}
text.toggle.color={on_sc}
min_width=0

[GroupBox]
inherits=GenericFrame
frame=false
interior=false
text.shadow=0
text.margin=0
text.normal.color={C("primary")}
text.focus.color={C("primary")}
text.bold=true

[ToolTip]
inherits=GenericFrame
frame=true
interior=true
frame.element=tooltip
interior.element=tooltip
frame.top=14
frame.bottom=14
frame.left=14
frame.right=14
frame.expansion=0
text.shadow=0
text.margin=2
text.normal.color={C("inverse_on_surface")}

[StatusBar]
inherits=GenericFrame
frame=false
interior=false

[Window]
interior=false
frame=false
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, f"{NAME}.svg"), "w") as f:
        f.write(build_svg())
    with open(os.path.join(out, f"{NAME}.kvconfig"), "w") as f:
        f.write(build_kvconfig())


if __name__ == "__main__":
    main()
