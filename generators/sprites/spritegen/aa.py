"""Inner-corner anti-aliasing for staircase silhouettes.

The last word on a unit sprite, after the outline and the despeckle have
settled every plane. A voxel body projected 2:1 leaves its long diagonals as
staircases — four pixels across, two down, over and over — and at the joint
between two steps the outline turns a right angle and reads as a lump twice
as heavy as the run on either side of it. Softening is the pixel-art answer
and it is a narrow one:

* ONE pixel, at the INNER corner of the step — the pixel whose only exposure
  is diagonal, tucked in the crook where the two runs meet. Never the outer
  corner, which is the silhouette's own shape.
* Only where BOTH runs meeting there are long (`MIN_RUN`): a 45-degree line
  or a one-pixel notch is not a staircase, and smoothing it deletes detail.
* Never outside the original alpha. AA that grows outward is a halo, and at
  the 16px grid the board samples this art on a halo is a blur.
* An EXISTING colour off the sprite's own ramp — the slot halfway between the
  outline colour and the body it sits on — never a fresh blend. A blend costs
  a palette entry per corner and turns a six-step ramp into a gradient, which
  is exactly what the indexed renderer exists to prevent.

The result is a mid-tone in the crook: the corner stops being the heaviest
point of the edge and the eye reads the run through it. That pixel is a lone
one, which `_despeckle` would fold away as dirt — so this runs AFTER it, and
the exception is deliberate: a lone pixel in the middle of a plane is noise,
and a lone pixel in the crook of a step is the corner being read as round.

The outline this softens is the 1px selective one (`docs/outlines.md`): dark
away from the sun, LIGHT into it. That is why the mid is looked up rather
than assumed dark — the pass reads whatever the line actually is at that
corner and lands between it and the body, so a lit edge is softened downward
and a shaded one upward, and neither is ever painted a tone the edge does not
already run through. Where the two are one slot apart there is no slot
between them and the corner is left alone: a sunward line lifted by
`SEL_OUT_LIFT = 1` is usually exactly that case, which is the honest answer
and not a threshold to widen. On the two rows wearing `OUTLINE_HEAVY` that
sunward line is a contour wherever it cannot clear the ground, so this pass
softens their corners the way it softens a shaded edge — the lookup is what
makes that free. On the two wearing `OUTLINE_RIM` the same line is two slots
up instead of one, so there IS a rung between it and the body and those
corners take a mid the other rows' do not: the pass reads the line rather than
the grade, and that is why it needed no change when the grade landed.

Today's models are drawn 2:1, so most of their silhouette is runs of TWO and
this pass leaves it alone by design (a clean 2:1 diagonal is already the
smoothest line a grid can draw; softening every step of one would only grey
the outline down). What it catches is the shallower stretches — a wing root,
a hull front, the shoulders of a foot unit.

The property buildings come through the same seam (`terrain.property_sprite`)
and today it moves no pixel of any of them, on any faction row: a building is
its base-plate diamond and axis-aligned walls, which is runs of two end to
end, so `MIN_RUN` excludes every corner they have (measured 2026-08-29 — 0
corners found, against 17-34 pixels each at `min_run=2`; `test_aa.Buildings`
keeps both halves honest). That is the rule answering, not a gap: the day a
building is drawn with a shallower roof line, it is softened like a wing root
without anyone wiring it up again.
"""

from __future__ import annotations

from PIL import Image

from .palette import Faction, Ramp, ramp_for
from .voxel import Model

# The whole pass, gated: flip this off and the sheet is exactly what it was
# before the pass existed.
ENABLED = True

# Sprites shorter than this are left alone. Softening is a treatment for a
# long edge; on a small sprite one pixel is a feature, and spending it on a
# step corner costs more shape than the corner costs smoothness.
MIN_SPRITE_HEIGHT = 24

# How long each of the two runs meeting at a corner must be before the corner
# counts as a staircase step rather than a detail. Three keeps the 2:1 body
# diagonals (four across) and drops single-pixel notches and 45-degree lines.
MIN_RUN = 3

# How far inward a corner may look for the body the outline sits on. The
# outline is ONE pixel wide, so the body is normally the very next pixel in;
# two is the whole allowance, for the one place a stair corner doubles the
# line up on itself. Reaching further is how the pass used to read a far plane
# as the "body" behind a wide LIT face and soften a bright corner toward a
# dark tone three pixels away — a smudge, not an edge.
_INTERIOR_REACH = 2

# The two colours must be at least this far apart on the ramp, or there is no
# slot between them to land on.
_MIN_SLOT_GAP = 2

# How far a step may rise between two runs and still be a step. The bodies are
# projected 2:1, so a diagonal steps down two pixels every four across; a
# taller riser is a wall the model drew on purpose.
_MAX_RISE = 2

# Up, right, down, left — the four sides a pixel can face the background over,
# in a stated order, so a corner that qualifies two ways answers the same way
# every run.
_ORTHO = ((0, -1), (1, 0), (0, 1), (-1, 0))

# A ramp paired with its colour -> slot lookup.
_SlotIndex = list[tuple[Ramp, dict[tuple[int, int, int], int]]]


def ramps_for_model(model: Model, faction: Faction) -> tuple[Ramp, ...]:
    """Every ramp a model is painted out of, in a stated order.

    The order is the tie-break when one colour sits in two ramps, so it is
    sorted by material name rather than by dict order.
    """
    out: list[Ramp] = []
    for mat in sorted(set(model.vox.values())):
        ramp = ramp_for(mat, faction)
        if ramp not in out:
            out.append(ramp)
    return tuple(out)


def soften_sprite(sprite: Image.Image, model: Model, faction: Faction) -> Image.Image:
    """`soften_staircase` for a rendered model: the gate plus the ramp lookup.

    Units and property buildings both come through here. They are drawn out of
    the same indexed ramps one band apart (`voxel.BUILDING_TOP_SLOT`), so the
    lookup that lands a corner between its line and its body costs a building
    nothing extra.
    """
    if not ENABLED or sprite.height < MIN_SPRITE_HEIGHT:
        return sprite
    return soften_staircase(sprite, ramps_for_model(model, faction))


def soften_staircase(
    rgba: Image.Image, ramps: tuple[Ramp, ...], min_run: int = MIN_RUN
) -> Image.Image:
    """A copy of `rgba` with every qualifying staircase inner corner softened.

    Pure: the input is never touched, and every write is computed off the
    ORIGINAL pixels, so two corners that see each other cannot cascade and
    the result does not depend on scan order.

    One write may still strand a THIRD pixel that never qualified as a
    corner itself: since S8's contour band (`voxel._thicken_contour`) a
    boundary pixel more often matches a same-toned neighbour one step further
    in than a differently-toned one right beside it, and softening that
    neighbour toward the interior can be the boundary pixel's only match
    going away — read as newly isolated
    (`IndexedPalette.test_no_isolated_pixel_outside_the_dither`, measured on
    `rockets`' thin rack). `_safe` drops exactly the writes that do that,
    off the same original pixels every other write is computed from, so this
    stays pure and order-free too.
    """
    img = rgba.convert("RGBA")
    w, h = img.size
    src = img.load()
    solid = [src[x, y][3] == 255 for y in range(h) for x in range(w)]
    slots = _slot_index(ramps)

    def at(x: int, y: int) -> bool:
        return 0 <= x < w and 0 <= y < h and solid[y * w + x]

    writes: list[tuple[int, int, tuple[int, int, int, int]]] = []
    for y in range(h):
        for x in range(w):
            if not solid[y * w + x]:
                continue
            corner = _corner(at, x, y, min_run)
            if corner is None:
                continue
            mid = _mid_colour(src, at, slots, x, y, corner)
            if mid is not None:
                writes.append((x, y, mid))

    out = img.copy()
    px = out.load()
    for x, y, colour in _safe(src, at, writes):
        px[x, y] = colour
    return out


def _safe(
    src, at, writes: list[tuple[int, int, tuple[int, int, int, int]]]
) -> list[tuple[int, int, tuple[int, int, int, int]]]:
    """`writes`, minus any that would strand a NEIGHBOUR of the corner it
    softens — a pixel that matched the corner's ORIGINAL colour and has no
    other orthogonal match to fall back on.

    Read entirely off `src`, the untouched render: a neighbour also due to be
    written answers for itself in its own pass through this same check, so
    nothing here depends on which order `writes` is walked in.
    """
    rewritten = {(x, y) for x, y, _ in writes}
    safe: list[tuple[int, int, tuple[int, int, int, int]]] = []
    for x, y, colour in writes:
        edge = src[x, y][:3]
        stranded = False
        for dx, dy in _ORTHO:
            nx, ny = x + dx, y + dy
            if (nx, ny) in rewritten or not at(nx, ny) or src[nx, ny][:3] != edge:
                continue
            if not any(
                at(nx + ddx, ny + ddy) and src[nx + ddx, ny + ddy][:3] == edge
                for ddx, ddy in _ORTHO
                if (nx + ddx, ny + ddy) != (x, y)
            ):
                stranded = True
                break
        if not stranded:
            safe.append((x, y, colour))
    return safe


def _slot_index(ramps: tuple[Ramp, ...]) -> _SlotIndex:
    """Each ramp paired with its colour -> slot lookup. A ramp that repeats a
    colour keeps the lowest slot for it, so the lookup is one stated answer
    rather than the last one."""
    index: _SlotIndex = []
    for ramp in ramps:
        table: dict[tuple[int, int, int], int] = {}
        for slot, colour in enumerate(ramp):
            table.setdefault(tuple(colour), slot)
        index.append((ramp, table))
    return index


def _corner(at, x: int, y: int, min_run: int) -> tuple[int, int] | None:
    """Is (x, y) the inner corner of a staircase step, and which way is out?

    The inner corner is the FIRST pixel of a run, on the side the edge just
    stepped down from: the shape rises beside it, so the outline turns a right
    angle through it and doubles up in the crook. It answers with the outward
    normal `n` — the one side of it that faces the background — because that
    is the direction the softening reads across.

    Three things have to hold, and together they say `staircase step` rather
    than `notch` or `corner of the shape`:

    * exactly one of the four sides faces out, so a one-pixel spike or a
      diagonal thread is never a corner;
    * this pixel's own run and the run the step came down from are both at
      least `min_run` long — the long-diagonal condition;
    * the rise between those two runs is at most `_MAX_RISE`. A step taller
      than that is a wall meeting a floor, which is the silhouette's shape and
      not an artefact of drawing a diagonal on a grid.
    """
    for n in _ORTHO:
        if at(x + n[0], y + n[1]) or not at(x - n[0], y - n[1]):
            continue
        perp = (-n[1], n[0])
        for t in (perp, (-perp[0], -perp[1])):
            # -t is the step side: solid, and solid again one row out, which
            # is the shape standing higher there.
            if not (at(x + t[0], y + t[1]) and at(x - t[0], y - t[1])):
                continue
            if not at(x - t[0] + n[0], y - t[1] + n[1]):
                continue
            if _run(at, x, y, t, n, min_run) < min_run:
                continue
            top = _rise(at, x - t[0], y - t[1], n)
            if top is None:
                continue
            if _run(at, top[0], top[1], (-t[0], -t[1]), n, min_run) < min_run:
                continue
            return n
    return None


def _rise(at, x: int, y: int, n: tuple[int, int]) -> tuple[int, int] | None:
    """Climb the step's riser from (x, y) to the pixel that faces out, or None
    if it is taller than `_MAX_RISE` — a wall rather than a step."""
    for step in range(_MAX_RISE + 1):
        cx, cy = x + n[0] * step, y + n[1] * step
        if not at(cx, cy):
            return None
        if not at(cx + n[0], cy + n[1]):
            return (cx, cy)
    return None


def _run(
    at, x: int, y: int, step: tuple[int, int], out: tuple[int, int], limit: int
) -> int:
    """How many opaque pixels from (x, y) along `step` face the background
    toward `out`, counting no further than `limit` — the answer is only ever
    compared against it."""
    n = 0
    while n < limit:
        cx, cy = x + step[0] * n, y + step[1] * n
        if not at(cx, cy) or at(cx + out[0], cy + out[1]):
            break
        n += 1
    return n


def _mid_colour(
    src, at, slots: _SlotIndex, x: int, y: int, n: tuple[int, int]
) -> tuple[int, int, int, int] | None:
    """The ramp slot halfway between the corner's colour and the body just
    inside it, or None if the two are not far enough apart on one shared ramp.

    The body is read by walking inward at most `_INTERIOR_REACH`, which is the
    outline's own width plus the pixel a stair corner doubles it by. If the
    corner still matches its own colour that far in, the corner is not sitting
    on a line at all — it is the near end of a plane — and there is nothing
    here to soften.
    """
    edge = src[x, y][:3]
    inner: tuple[int, int, int] | None = None
    for step in range(1, _INTERIOR_REACH + 1):
        ix, iy = x - n[0] * step, y - n[1] * step
        if not at(ix, iy):
            break
        colour = src[ix, iy][:3]
        if colour != edge:
            inner = colour
            break
    if inner is None:
        return None
    for ramp, table in slots:
        a, b = table.get(edge), table.get(inner)
        if a is None or b is None or abs(a - b) < _MIN_SLOT_GAP:
            continue
        c = ramp[(a + b) // 2]
        return (c[0], c[1], c[2], 255)
    return None
