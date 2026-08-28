"""The atlas cell a rendered sprite is composed onto, and the water it sits in.

`voxel.py` renders a model to a tight sprite; this module places that sprite in
a cell — the vertical landmarks measured up from the cell's bottom edge, the
cast shadow, and the foam, wake and bow wave a hull needs to read as being in
the water rather than on it. It imports no renderer: composition is a pass over
a finished image, so nothing here can be a second opinion about how a voxel is
shaded.
"""

from __future__ import annotations

from PIL import Image

from .palette import RGB
from .sun import SHADOW, SHADOW_OFFSET


# The cell's vertical landmarks, each stated as a height ABOVE its bottom
# edge: the ground line a land or sea unit stands on, the higher line an
# aircraft hovers at, and the ground its shadow falls on.
GROUND_BOTTOM = 9
AIR_BOTTOM = 20
AIR_SHADOW_BOTTOM = 6


def compose_cell(
    sprite: Image.Image,
    kind: str = "land",
    cell: tuple[int, int] = (64, 64),
    bottom: int | None = None,
    dx: int = 0,
    wake: bool = False,
    shadow: bool = True,
    origin: tuple[int, int] | None = None,
    footprint_w: int | None = None,
    ground: int | None = None,
    centred_shadow: bool = False,
    under_way: bool = False,
) -> Image.Image:
    """Center a rendered sprite on a transparent atlas cell with its shadow.

    `cell` is (width, height), and every vertical landmark is measured up
    from the cell's BOTTOM edge — the ground line is the bottom of the tile
    the unit occupies. A taller cell therefore adds sky above the sprite and
    moves nothing, which is what lets a silhouette overflow its tile upward.

    Shadow policy (sprite review round 3): land units get a tight hard
    CONTACT shadow — without one they float over the tile — and the airborne
    cue is the shadow's offset and the sky between unit and shadow, not its
    presence: 'air' hovers over a larger ellipse displaced down-right.
    'sea' sits in the water on a displacement shadow with waterline foam;
    `wake` adds the running foam a hull that is mostly under water needs to
    separate from open sea at all (see `_wake`).
    'prop' composes with no shadow (terrain tiles draw their own grounding).

    Altitude is read off the shadow's SIZE and OFFSET, never off its density
    (the round-3 quarter-tone/half-tone pair is superseded — see
    `_shadow_ellipse`): a land unit's hugs the hull, an airborne one is
    larger and displaced down-right with ground showing between. Nothing
    here is semi-transparent — the shadow and every fleck of foam are opaque,
    because partial alpha is a blurred halo at cut-in scale.

    `shadow=False` leaves that cast shadow off, for a surface that draws its
    own ground and its own shadow rather than standing the cell on a tile.

    It SUBTRACTS rather than skips, so the cell is the tile's cell with those
    pixels taken back out and can never be a second opinion on the art. The
    waterline foam is why that matters: it is placed against the composed
    cell's own spans, so a shadow that was never drawn would move the foam.

    The last three arguments are what lets a SECOND pose of the same unit be
    the same unit moving rather than a second composition. `origin` places the
    sprite's top-left corner outright, so a caller can pin two crops by their
    model origin (`sprite_origin`) instead of centring each one's own box.
    `footprint_w` is the width every shadow radius is taken from — the unit's
    footprint on the ground, which a raised rotor or a swung barrel does not
    change. `ground` is the SURFACE the unit is over, which is not the row it
    rides at once it bobs: the shadow, the displacement ellipse, the running
    wake and the waterline foam all stay here, so a ship that rises a board
    texel rides a swell instead of dragging the sea up with it. All three
    default to the single-pose behaviour: centred crop, the sprite's own
    width, and the surface right under the unit.

    `centred_shadow` drops the shadow's HORIZONTAL offset (the full vertical
    drop stays) and straddles the ellipse across the cell's mirror axis, so
    flipping the cell leaves the shadow exactly where it was. It is for a
    frame the consumer MIRRORS: the game plays the move clip with
    `Sprite2D.flip_h` for rightward travel, which would otherwise swing the
    shadow 5px (land) or 9px (air) to the wrong side of a sun every terrain
    tile agrees on. Straddling costs the ellipse one column of width (see
    `_shadow_ellipse`'s `mirrored`) and costs the unit a 2px — 4px for air —
    shadow recentre at the instant it starts or stops moving, which lands on
    the frame the position tween starts or ends on. See docs/move_clip.md.

    A ship does NOT ask for this even under way: its ellipse is displacement
    rather than a cast shadow, and `_waterline_foam` is placed against the
    composed cell's own spans, so recentring it would carry the foam line
    with it — see `atlas.unit_cell`.

    `under_way` is what a ship's move frames ask for instead: white water at
    the bow (`_bow_wave`), which is the one thing a running hull has that a
    moored one does not.
    """
    cell_w, cell_h = cell
    out = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    w, h = sprite.size
    if bottom is None:
        bottom = cell_h - (AIR_BOTTOM if kind == "air" else GROUND_BOTTOM)
    x0, y0 = origin if origin is not None else ((cell_w - w) // 2 + dx, bottom - h)
    if ground is None:
        ground = bottom
    fw = w if footprint_w is None else footprint_w

    cast: list[tuple[int, int]] = []
    sx, sy = SHADOW_OFFSET
    if centred_shadow:
        # The sun's x is what the mirror would negate, so a mirrored frame
        # gives it up: no lateral throw, and the ellipse is drawn symmetric
        # about the cell's flip axis rather than about one column of it.
        sx = 0
    if kind == "sea":
        # Ships sit IN the water: a flat displacement shading right under
        # the hull instead of a floating blob, then foam at the waterline.
        rx = max(6, int(fw * 0.42))
        cast = _shadow_ellipse(
            out,
            cell_w // 2 + dx + sx,
            ground - 1 + sy,
            rx,
            max(2, rx // 5),
            mirrored=centred_shadow,
        )
    elif kind == "air":
        rx = max(6, int(fw * 0.30))
        cast = _shadow_ellipse(
            out,
            cell_w // 2 + dx + sx * 2,
            cell_h - AIR_SHADOW_BOTTOM,
            rx,
            max(2, rx // 3),
            mirrored=centred_shadow,
        )
    elif kind == "land":
        rx = max(4, int(fw * 0.34))
        cast = _shadow_ellipse(
            out,
            cell_w // 2 + dx + sx,
            ground - 1 + sy,
            rx,
            max(2, rx // 4),
            mirrored=centred_shadow,
        )
    place_in_cell(out, sprite, x0, y0)
    if kind == "sea":
        if wake:
            # Running foam is the WATER's, not the hull's, so it is left on
            # the surface: a bobbed hull rises out of its own wake rather than
            # carrying it up. Measured on the sub, whose wake is a third of
            # its silhouette, that is the difference between a frame B that
            # reads as itself and one that reads as the battleship.
            _wake(out, sprite, x0, ground - h)
        _waterline_foam(out, ground)
        if under_way:
            # After the waterline foam, never before: `_waterline_foam` reads
            # the composed cell's own opaque spans, so a crest laid down first
            # would widen them and carry the ambient foam line off the water.
            _bow_wave(out)
    if not shadow:
        _erase_shadow(out, cast)
    return out


def _erase_shadow(img: Image.Image, cast: list[tuple[int, int]]) -> None:
    """Clear the shadow the cell was composed with, leaving all else alone.

    A cast pixel the sprite, the wake or the foam has since painted over is
    no longer shadow and is kept: what comes out is only what is still the
    tone the ellipse wrote there.
    """
    px = img.load()
    for xx, yy in cast:
        if px[xx, yy] == CAST:
            px[xx, yy] = EMPTY


def place_in_cell(cell_img: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Composite a sprite into a fixed-size cell, refusing to crop it.

    Pillow clips a paste at the destination edge without complaining, which
    turns a sprite that outgrew its cell into a silently trimmed barrel or
    roof. Overflow is an authoring error, so it stops the build instead.
    """
    cw, ch = cell_img.size
    sw, sh = sprite.size
    if x0 < 0 or y0 < 0 or x0 + sw > cw or y0 + sh > ch:
        raise ValueError(
            f"sprite {sw}x{sh} placed at ({x0}, {y0}) does not fit the "
            f"{cw}x{ch} cell — shorten the model or move it inward"
        )
    cell_img.alpha_composite(sprite, (x0, y0))


FOAM_ROWS = 4
FOAM: RGB = (226, 240, 250)
# What a composed shadow pixel and an untouched one look like. One statement,
# because three passes ask: the ellipse writes CAST, the wake may take a CAST
# pixel back, and `_erase_shadow` turns whatever is still CAST into EMPTY.
CAST = (*SHADOW, 255)
EMPTY = (0, 0, 0, 0)
# How far the wake runs on past the stern, in cell columns.
WAKE_TRAIL = 6

# The bow wave: how far aft along the displacement patch's leading rim the
# crest runs (in water-plane voxels, 2 cell columns each) and how deep into
# the patch it breaks (in px). Eight and eight put white water over the
# leading third of the longest patch and stop well short of amidships on all
# four — a white run that reaches the middle of a hull stops reading as a wave
# and starts reading as a scratch across the shadow. See `_bow_wave`.
BOW_REACH = 8
BOW_CREST = 8


def _wake(img: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Running foam along an awash hull's whole length, trailing off the stern.

    A ship reads against open sea by its freeboard; a submarine has none, so
    the round-4 legibility measure put the sub last on the sheet. The foam is
    what the water does about the hull it is breaking over, so it follows the
    hull's own underside — the bottom-most sprite pixel of every column —
    rather than a fixed row, and then keeps going up-right past the stern
    along the dimetric hull axis (2 columns per row).

    Opaque, never partial alpha, and drawn ON the water rather than beside it:
    it takes empty pixels and shadow pixels alike, because the foam is what
    the surface does over the displacement shading, not a stipple interleaved
    with it. It ran on the shadow's own parity while the shadow was a 1px
    checkerboard; a solid shadow (see `_shadow_ellipse`) would otherwise have
    swallowed the whole length of it and left the hull nothing but its stern
    trail. `_erase_shadow` keeps a shadow pixel the wake has taken, so the
    figure sheet is unmoved by this.

    `y0` is where the hull sits ON THE WATER, which is not always where it is
    drawn: a bobbed hull passes the row it rose from, because the foam it
    broke stays on the surface (see compose_cell's `ground`).
    """
    px = img.load()
    sp = sprite.load()
    w, h = img.size
    sw, sh = sprite.size

    def fleck(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h and px[x, y] in (EMPTY, CAST):
            px[x, y] = (*FOAM, 255)

    keel = []
    for sx in range(sw):
        column = [sy for sy in range(sh) if sp[sx, sy][3] == 255]
        if column:
            keel.append((x0 + sx, y0 + max(column)))
    if not keel:
        return
    for i, (x, y) in enumerate(keel):
        fleck(x, y + 1)
        if i % 2 == 0:
            fleck(x, y + 2)
    stern_x, stern_y = keel[-1]
    for k in range(1, WAKE_TRAIL + 1):
        y = stern_y - (k + 1) // 2
        fleck(stern_x + k, y)
        fleck(stern_x + k, y + 1)


def _bow_wave(img: Image.Image) -> None:
    """White water at the bow: the foam a hull only makes under way.

    A parked hull and a running one were the same picture plus a trim — 15
    changed and 2 rung-1 silhouette texels between the lander's pose A and its
    MOVE_A, 18/3 for the cruiser — so a ship on passage read as moored. What a
    ship under way has and a ship at anchor does not is white water, and this
    is where the sheet puts it.

    It is drawn on the LEADING EDGE OF THE DISPLACEMENT PATCH, not against the
    hull: `_shadow_ellipse` lays that patch on `compose_cell`'s `ground` and
    the hull is composed over it, so its leading rim is both the water the
    stem is pushing and a shape that cannot heave when the hull bobs. Reading
    it off the composed cell also means the crest never covers freeboard —
    only CAST is repainted, so wherever the hull overhangs its own
    displacement the foam simply is not there.

    The crest is white-on-near-black rather than white-on-sea, which is the
    strongest contrast on the cell and the reason a wave two texels tall
    survives the board's 4:1 sample at zoom rung 1 (see `tests/measure_motion`).
    It costs almost nothing to draw for the same reason: repainting shadow
    adds no pixel, and the four hulls' move poses sit within 9 px of
    `MoveFrames.MAX_MASS_DRIFT` already. Only the one-pixel LIP outside the
    rim is new water — the wave breaking clear of the patch — and that px is
    what the drift budget affords.

    The wave is the same on both move frames on purpose. Ticking it with the
    beat was tried and is unbuildable here: at `BOW_REACH` 8 the crest already
    covers every row of every hull's patch — the widest is nine rows tall — so
    carrying it two voxels further aft on the off-beat repainted nothing at
    all. The beat stays where the four hulls already carry it, in the trim and
    the guns; the water just runs.
    """
    px = img.load()
    w, h = img.size

    def fleck(x: int, y: int) -> None:
        if 0 <= x < w and 0 <= y < h and px[x, y] in (EMPTY, CAST):
            px[x, y] = (*FOAM, 255)

    lead = {}
    for yy in range(h):
        run = [xx for xx in range(w) if px[xx, yy] == CAST]
        # A row with less patch in it than the crest is deep is the ellipse's
        # own top or bottom cap, a couple of pixels wide amidships: breaking
        # foam there is a fleck floating over the middle of the ship, not a
        # wave, so those rows are left to the ambient waterline foam.
        if len(run) > BOW_CREST:
            lead[yy] = min(run)
    if not lead:
        return
    # The leading tip: models face +y, which the projection puts at screen
    # lower-LEFT, so the bow end of the patch is its smallest column.
    tip = min(lead.values())
    for yy, lo in lead.items():
        if lo > tip + 2 * BOW_REACH:
            continue
        # One pixel of the wave breaking clear of the patch, and one only:
        # this is the crest's whole cost in new water, and a second column of
        # it puts the battleship over `MoveFrames.MAX_MASS_DRIFT`.
        fleck(lo - 1, yy)
        for k in range(BOW_CREST):
            if px[lo + k, yy] != CAST:
                break
            fleck(lo + k, yy)


def _waterline_foam(img: Image.Image, ground: int) -> None:
    """Foam flecks just outside the hull along its waterline rows.

    The rows come from the composed pixels rather than from a fixed offset:
    `render` reserves a trailing empty row, and the dimetric hull tapers to a
    narrow tip, so an offset measured off the sprite misses the wide part of
    the wake. Measured on the 64x96 cell, the last four opaque rows of a ship
    (battleship 90-93, cruiser 88-91, sub 89-92, lander 88-91) are the
    displacement ellipse's own — the shape the hull cuts in the water, which
    is exactly what the foam breaks around.

    Only rows at or below `ground` are read, because only they are the water:
    a hull bobbing a board texel above the surface is not a waterline however
    low its own pixels reach, and skipping it is what leaves the foam line
    where the still pose put it while the ship rides the swell. Flecks trail
    outward along the last few rows, widest at the bottom.
    """
    px = img.load()
    w, h = img.size
    foam = FOAM
    spans = []
    for yy in range(max(0, ground), h):
        xs = [xx for xx in range(w) if px[xx, yy][3] == 255]
        if xs:
            spans.append((yy, min(xs), max(xs)))
    if not spans:
        return
    # The outer fleck used to fade on alpha; it now thins out as a dither
    # instead, because a semi-transparent pixel is a halo at cut-in scale.
    for i, (yy, lo, hi) in enumerate(reversed(spans[-FOAM_ROWS:])):
        n = 2 if i < 2 else 1
        for k in range(1, n + 1):
            if k > 1 and yy % 2:
                continue
            if lo - k >= 0:
                px[lo - k, yy] = (*foam, 255)
            if hi + k < w:
                px[hi + k, yy] = (*foam, 255)


def _shadow_ellipse(
    img: Image.Image, cx: int, cy: int, rx: int, ry: int, mirrored: bool = False
) -> list[tuple[int, int]]:
    """A hard SOLID shadow: opaque dark pixels, filled, no partial alpha.

    It used to be a 1px checkerboard, on the argument that the gaps let the
    terrain through so the shadow tinted without smearing. That argument only
    ever held at one sampling ratio. The board draws this 64px cell onto a
    16px grid with nearest filtering at whole zoom rungs 1..5, so it keeps one
    source pixel in 4/z — and a 1px parity read differently at every rung it
    was sampled at: solid at rung 1 (the kept phase is the shadow's own),
    nearly absent at rung 2 for the land grid and simultaneously solid for the
    air one, and at rung 4, where the art is 1:1, individual black dots. Two
    players reported those dots on the board. A filled ellipse is the one
    shape whose read cannot move with the ratio — it is the same shadow at
    every rung, which is what "one logical pixel" buys the contour, bought
    here by having no sub-pixel structure to lose at all.

    A logical-pixel checker (4px blocks) and a solid core with a dithered
    fringe were both rendered against this at rungs 1, 2 and 4: the checker
    reads as a chequered flag under an aircraft at 1:1 and as a dashed line at
    rung 2, and the fringe reads as debris. Solid was the only one that read
    as shade at all three.

    `mirrored` intersects the ellipse with its own reflection in the image's
    vertical mirror axis, which is what makes a shape that survives
    `Sprite2D.flip_h` unchanged: the axis of an even-width cell runs BETWEEN
    two columns, so no odd-width ellipse centred on a column can be symmetric
    about it, but keeping only the ground both readings agree is in shade
    gives an even-width one that is. It costs the ellipse a single column —
    intersecting rather than unioning, so a mirror-safe shadow is never
    larger than the shadow it replaces. See compose_cell's `centred_shadow`.

    Returns the pixels it wrote, so a caller composing a shadowless cell can
    take exactly those back out again — see compose_cell's `shadow`.
    """
    px = img.load()
    w, h = img.size
    written = []

    def inside(xx: int, yy: int) -> bool:
        return ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0

    for yy in range(cy - ry, cy + ry + 1):
        for xx in range(cx - rx, cx + rx + 1):
            if not (0 <= xx < w and 0 <= yy < h):
                continue
            if not inside(xx, yy):
                continue
            if mirrored and not inside(w - 1 - xx, yy):
                continue
            if px[xx, yy][3] == 0:
                px[xx, yy] = CAST
                written.append((xx, yy))
    return written
