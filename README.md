# Bombies: Dead Zone

A squad-based first/third-person wave shooter in Summer Engine (Godot 4.6).
You are the rogue hazmat engineer, holding a flooded underground parking
garage against mutating Bombies — then pushing through a collapsed factory
with your squad. Three garage rounds, then three factory rooms, then the
exit opens.

## Milestone 1 — flooded garage (done)

- Flooded parking garage: murky standing water (slows you, not the runners),
  pillar grid, rusted parked cars, ramp to a mezzanine, amber tube lights and
  a flickering red emergency light, fog and haze.
- Hazmat engineer: hitscan rifle (30-round mag, R to reload), toxic grenades
  (G, area-denial acid cloud), two trap types (1 = proximity mine, 2 = acid
  trap, Q = place selected).
- 3 rounds: shamblers, then runners, then runners + tank brutes. After 40
  seconds in a round the surviving Bombies mutate (faster, tougher, redder).
- Win at round 3 (exit stairwell opens). Lose when downed. R restarts.
- Procedural sound: shots, booms, groans, drips, splashes — no audio files.

## Milestone 2 — collapsed factory + squad (done, verified 2026-10-28)

- **Collapsed factory, forward-only, room by room.** Three rooms along a
  derelict production floor: rusted machines, conveyors, collapsed beams,
  barrels, hanging cables, toxic puddles, amber tube lights and a flickering
  red light. Each room must be cleared before its door opens; doors seal
  behind the squad. Clear room 3 and the exit opens.
- **Squad switching (Tab).** The full squad assembles at the factory door:
  - **Hazmat engineer** — rifle, toxic grenades, mines + acid traps (her kit
    stays exclusive), 100 HP.
  - **Scarred military veteran** — shotgun (6 pellets), frag grenades,
    150 HP, revives downed squadmates faster (50% HP, 75% if he is standing).
  - **Fast street survivor** — SMG (40-round mag), 70 HP, fastest on foot,
    sprint + Ctrl to slide, best at kiting runners.
  - Tab cycles to the next living member; switching is automatic when the
    controlled member is downed. Downed members revive at the next room
    clear; all three recover between locations. Lose only when the whole
    squad is down at once.
- **New special infected: the exploder.** A bloated, glowing-orange Bombie
  that charges the player and detonates (35 damage AoE within 3.5 m). First
  one at 45 s into round/room 2, then one per round/room. Shooting it dead
  before its 0.9 s fuse ends stops the blast.
- **Realistic-proportioned characters (not blocky).** Heroes and Bombies are
  built as multi-part humanoids (`scripts/humanoid.gd`): jointed cylinder
  limbs with elbow/knee pivots, sphere heads with helmets, hair, hoods and
  visors, worn jackets, backpacks with pouches and straps, belts, boots, and
  held weapons. Clothing and skin use procedural grime textures (noise,
  stains, scratches, wear) instead of flat colors — no single-box bodies.
  The TPS camera now pulls in when a wall is behind the player instead of
  clipping through it, and the player collision sits at foot level so the
  hero stands on the floor and the garage water actually slows wading.
- V toggles first / third person. Right mouse aims down sights. F toggles
  the flashlight. HUD shows the location, room/round, Bombies left, and the
  squad panel (controlled member + status of the others).
- Concept art for the game is in `assets/concept/`; the design brief is in
  `.summer/GameSoul.md`.

Verified with stock Godot 4.6.3 under Xvfb (Summer Engine has no Linux
build): self-play run cleared garage rounds 1–3 and factory rooms 1–3 and
**WON at t=170.0 s with zero script errors** (log `/tmp/godot-m2-run4.log`;
frames `/tmp/dz2-*.png`, `/tmp/dz-shot-*.png`).

## Exact-replication pass — hero + garage match the concept art (done, verified 2026-10-28)

The hazmat hero and the flooded garage now match their concept pictures
(`assets/concept/hazmat-engineer.png`,
`assets/concept/flooded-parking-garage.png`) as closely as procedural
models allow — layout, silhouette, palette, props and lighting, judged by
side-by-side screenshots. Honest limit: these are models built in code,
not the 2D pictures, so pixel-perfect identity is impossible.

- **Hero, exactly as the picture.** Acid-yellow hooded suit, heavily
  grimed (filthiest at the lower legs), with grey duct-tape patches on the
  hood, chest, arms and legs. The suit is fitted, not boxy: tapered
  torso (shoulders wider than waist), tapered limbs, round shoulder caps,
  rounded hood, rounded glove mitts and booted toes. Green-tinted visor
  as a curved wraparound band with a thin frame, crack lines, and the face
  faintly visible behind it. Gas mask below: rounded respirator body,
  central mouthpiece, two big round cheek filters with dark intake caps,
  taped straps. Coiled ribbed hose looped around the neck and shoulders
  down to the chest rig. Chest rig with belt buckle, twin metal
  canisters, hip pouches and diagonal straps. Dark knee pads, grey rubber
  gauntlet gloves, dirty work boots. The weapon is the picture's
  improvised gun — bulky, built from pipes and canisters with tubes, a
  red wire and a pressure gauge — held angled across the thigh in the
  portrait, and the FPS viewmodel is the same gun, same parts, same
  proportions. Portrait: `/tmp/hero-exact.png`.
- **Garage, exactly as the picture.** Two levels: the lower floor flooded
  with murky green-brown water (ripple shader, warm light sparkle) that
  reflects the lights. Sixteen rusted cars half-submerged at angles
  (sedans, vans, a wagon, three rust variants, two with doors hanging
  open), one stalled on the central ramp, two parked up on the mezzanine.
  A wide concrete ramp in the middle, with curbs, descending from the
  mezzanine's south edge into the water — walkable, top surface flush
  with the platform and the floor. Upper mezzanine (10 x 6 m) with
  chain-link fencing along its west edge and both south-edge segments
  either side of the ramp opening. A staircase along the north wall,
  rising to the mezzanine's east edge, lit red at the top (plus the
  west flickering red emergency light). One long amber tube light on the
  ceiling, two fill tubes, haze-glow billboards around the lights,
  stained concrete walls with damp streaks, pillar grid in lighter
  stained concrete, and scattered rubble: 42 debris chunks, planks,
  tyres, barrels, broken pillar stubs. Gameplay is intact: player spawn,
  8 Bombie spawn points (the mezzanine spawn moved onto the platform),
  3 rounds, water slowing, Bombie pathing, mezzanine reachable by the
  ramp and the stairs, win/lose flow. Shot: `/tmp/garage-exact.png`.
- **Bombies read as people in torn clothes.** The humanoid rebuild also
  covers the infected: tapered limbs, torn shirts with exposed skin,
  a hanging torn flap at the waist, heavier grime, and bigger, brighter
  glowing eyes (energy 8) that read in the dark garage — the reference
  gameplay screenshot's "two glowing eyes by a rusted car." Staged TPS
  shot (hero from behind, Bombie ahead, red light, HUD on):
  `/tmp/tps-exact.png`, judged against the reference gameplay screenshot.
- **Look and Feel quality bar (GameSoul.md).** Gritty photoreal: worn
  concrete, rusted metal, surfaces wet and drying for years; desaturated
  charcoal/olive palette broken by amber, red and acid-yellow emergency
  lighting; volumetric haze, flickering practicals, harsh directional
  shadows; quiet moments carry drips, groans and radio static from the
  existing procedural audio.

## Character-realism pass — the Nano Banana hyper-realism bar (done, verified 2026-10-28)

Every character now holds to the hyper-realistic portrait bar Danny set
with two prompts (the character prompt + the Ultra-Realistic Face
Prompt, used together) plus a macro-detail criterion from four
close-up references (bee-face macro, compound-eye zoom, a photorealistic
woman's portrait, a lip close-up). Translation, not literal copy: "no
CGI / no 3D render" cannot literally apply to a game — the goal is faces
that read as photographs, not renders.

- **Skin texture (all characters).** A dedicated 256 px procedural skin
  texture replaces flat skin: fine pore speckle, short fine lines and
  micro-wrinkle lines, freckle clusters, soft uneven pigmentation,
  subtle acne dots and a few moles — never a single flat color, never
  smoothed plastic. Skin roughness 0.55 gives a realistic oil sheen:
  soft specular response under the garage lights, not matte plastic and
  not glossy. Each character has their own skin tone, freckle density
  and texture seed, so no two characters share a face.
- **Real faces (all characters).** Eye whites + radial-fiber iris discs
  + pupils, brows with slight asymmetry and short hair strands along
  the brow line, nose bridge + tip + nostrils, lips with fine lip-line
  texture, ears, under-eye shadow. Proportions are true to life: eyes
  one eye-width apart, nose centred, mouth below the nose — no slimming,
  no exaggeration, neutral expressions. Heroes get catchlights (tiny
  bright reflections on each iris), upper lash lines, crow's feet and
  sparse vellus fuzz on cheeks and temples. Bombies get sunken dark
  sockets with glowing iris discs and dark pupil cores, so the eyes
  still burn in the dark garage but read as eyes, not headlight discs.
- **Hero behind the visor.** The face faintly visible through the green
  pane is now a real dim face (skin texture, normal eyes, faint glints)
  instead of a flat dark fill, and the hood was pulled back so the face
  sits in its opening rather than buried inside it. Suit, mask,
  filters, hose, chest rig and improvised gun are unchanged from the
  exact-replication pass.
- **Veteran and survivor.** The veteran's helmet was a full sphere that
  enclosed his whole head — it is now a high cap with the brim above
  the brows, so his face (blue-grey eyes, scar, stubble, ruddy skin)
  is visible. The survivor keeps her strand hair and gains freckles,
  hazel-green eyes and the full face bar.
- **Hair as strands, not a helmet.** Hair caps carry a fine combed-strand
  texture, and the fringe is separate strand boxes at varied lengths
  and tilts across the forehead, plus side strands. Zombie hair is
  patchy: fewer, shorter, uneven strands. Torn Bombie clothing is
  frayed: rotated skin patches with fray strips at the hem and cuffs,
  not clean cutouts or pasted rectangles.
- **Macro detail, honestly stated.** Close-ups hold up under zoom at
  portrait distance (0.5 m): skin grain, lip creases, separate hair
  strands and eye reflections resolve in the macro shot
  (`/tmp/macro-real.png`, survivor face). True per-hair geometry is not
  feasible in this real-time Godot project — hair detail is fine
  procedural strand texture, which reads as separate strands at close
  range but is not individually modeled hairs. Likewise micro-detail
  resolves at portrait/close-up distance; at normal gameplay distance
  (several metres) it correctly reads as texture, not as individually
  visible pores — the TPS gameplay shot is judged at its own distance.
  The hero's face micro-detail is additionally limited by the visor
  itself: the picture's face is faint behind green glass by design.
- **Staged shots.** Hero portrait `/tmp/hero-real.png`, hero-face
  close-up `/tmp/hero-face-real.png`, Bombie close-up
  `/tmp/bombie-real.png`, survivor bare-face `/tmp/survivor-face-real.png`,
  macro `/tmp/macro-real.png`, TPS gameplay `/tmp/tps-real.png`.
- **Verification.** Full self-play run after this pass: garage rounds
  1-3 then factory rooms 1-3, WON at t=125.5 s, zero script errors
  (log `/tmp/godot-real-run.log`). No gameplay, weapon, HUD, garage,
  factory, squad or exploder behavior was changed — only character
  appearance and the staged capture modes in `dead_zone.gd`.

## Baked photographic face textures (done, verified 2026-10-28)

The procedural faces from the character-realism pass still read as
stylized game characters at macro distance, so the faces are now baked
AI-generated photorealistic portraits mapped onto the head models.
The four portraits (in `assets/faces/`, WebP, with Godot `.import`
files) are front-facing, evenly lit, plain-background studio portraits
with the face filling the frame:

- Survivor: young woman, freckles, hazel-green eyes, dark hair pulled
  back.
- Veteran: older man, grey hair, cheek scar, stubble, blue-grey eyes.
- Hero: man early 30s, short dark hair, light stubble.
- Bombie: gaunt pallid man, grey-green skin, sores, sunken eyes,
  patchy hair — shared by shambler, runner, tank and exploder with
  per-type tint/scale variation (pallor, size) so they do not read as
  clones at a glance.

**How each face is mapped (`scripts/humanoid.gd`).** A spherical face
plate — a curved patch (azimuth ±50°, polar −75° to +30°) sitting on a
sphere of radius 0.128 × scale, just proud of the 0.115 × scale skull so
it never z-fights — carries the portrait, cropped to the face oval
(forehead to chin, cheek to cheek) so the studio background never
shows. The plate is a child of the head pivot, so it tracks the head
through walk cycles and body turns. The old procedural face geometry
(eye discs, nose boxes, mouth boxes, painted brows) is removed wherever
a plate is present — otherwise the character gets a double face — and
is kept only as a fallback if a texture fails to load. Features the
photos do not carry are kept: the hero's green visor + gas mask +
filters + hood (his plate is dimmed ×0.62 and sits behind the visor
pane, so his face stays dim behind green glass by design), the
veteran's helmet cap, the survivor's hair mass and fringe around the
plate, Bombie hair. Geometry ears stay just outside the plate edges.
Two mapping gotchas found by screenshot and fixed: the plate's
triangle winding had to be flipped (the original order was
backface-culled and the plate was invisible), and Godot UV v=0 is the
top of the imported image (v=1 − v_top renders the face upside down).

**Bombie eyes still glow.** The Bombie photo's eyes are dark and
normal, so a subtle emissive overlay is layered back on: a glowing
iris disc with a dark pupil core over each photographic iris, aligned
with the photo's eye positions. The glow still burns in the dark
garage — a gameplay readability feature, not decoration.

**Judged honestly.** At portrait distance the survivor, veteran and
Bombie faces read as photographs: real pores, freckles, lip lines and
eyes, not painted doll faces (staged shots: survivor
`/tmp/survivor-face-real.png`, veteran `/tmp/veteran-face-real.png`,
Bombie `/tmp/bombie-real.png`, hero through visor
`/tmp/hero-face-real.png`, TPS gameplay `/tmp/tps-real.png`). Two
limits remain: the hero's face through the visor is dim and green by
design, so pore-level detail does not resolve there — you get a real
face with eyes and brows behind glass, not a macro portrait; and at
normal TPS gameplay distance the faces correctly read as texture
rather than individually visible pores. No gameplay, weapon, HUD,
garage, factory, squad or exploder behavior was changed — only faces
and the staged capture modes in `dead_zone.gd` (a `DZ_VETERAN_FACE`
portrait mode was added).

**Verification.** Full self-play run after this pass: garage rounds
1-3 then factory rooms 1-3, WON at t=91.8 s (log
`/tmp/godot-face-run.log`), zero script errors.

## Whole-game photographic texture pass (done, verified 2026-10-28)

The face method applied to the whole game: baked photographic textures
(in `assets/textures/`, WebP, with Godot `.import` files) on bodies,
limbs, heads, hats, weapons, cars, walls, sky and trees — the same
standard as the faces ("it looks amazing" is the bar Danny set).

- **Bodies + limbs (`scripts/humanoid.gd`).** Forearms, hands and all
  bare skin use the veiny-forearm photograph (rotated 90° so the veins
  run along the limb — on a cylinder, U wraps around and V runs along,
  so the unrotated photo wraps the veins around the arm; the rotated
  copy `veiny-arm-skin-vertical.webp` is derived from the same photo
  with PIL). Clothing — jackets, shirts, pants, hoods, backpacks —
  uses the torn-fabric photograph, tinted per character (the tint is
  lifted toward white so the dark photo's weave and fray detail does
  not crush to black). The hero's hands stay gloved (rubber gauntlets
  are part of the concept picture); everyone else's bare hands get the
  veiny skin.
- **Whole heads.** Ears are now built for EVERY character with the
  photographic skin — the old code only built them inside the
  face-plate branch, so the hazmat hero (whose plate is built later,
  under the visor) had no ears at all. Skull sides/back use the same
  photographic skin instead of flat procedural colour, so no part of
  the head reads as flat colour. The veteran's helmet cap uses the
  worn-olive-helmet photograph (scratches, chips, dirt); hoods use the
  torn-fabric photograph. Hair keeps its strand texture. Any hat or
  helmet added later must use a photographic texture the same way —
  no flat headgear.
- **Guns + weapons.** Every weapon — TPS held weapons AND FPS
  viewmodels (rifle, shotgun, SMG, improvised gun) — uses the worn
  gunmetal photograph (scratched dark steel, oil sheen, lifted
  slightly so it still reads in the dark garage). Grips and stocks get
  dark worn fabric instead of flat black.
- **Cars (`scripts/garage.gd`).** The rusted-car photograph on all
  garage cars (three tint variants so they do not read as copies),
  PLUS geometry the old cars lacked: four wheels with hubs, dark
  reflective window glass (side glass, windshield, rear window) and
  door seams on the body sides. Collision stays the single box, so
  pathing and spawn points are untouched.
- **Environment (`scripts/garage.gd`, `scripts/factory.gd`,
  `scripts/level_base.gd`).** The stained-concrete photograph on
  garage + factory walls, pillars and floors, triplanar-mapped so it
  never stretches absurdly; the rust photograph on machines, debris
  and barrels. The floor gets the same photo dimmed (×0.45) — untinted
  it blew out to near-white under the garage lights and killed the
  dark mood. Amber/red emergency lighting, haze and water behavior
  are unchanged. All photo loads fall back to the old procedural
  textures if a file fails, so a missing photo never breaks a level.
- **Sky + clouds (`scripts/dead_zone.gd`).** The cloudy-sky panorama
  is wired into the environment as a `PanoramaSkyMaterial`, so any
  open-air view (including the future overpass) shows overcast clouds.
  Indoor locations are enclosed boxes, so it never shows inside the
  garage or factory. Gotcha found by screenshot: with the scene's fog
  at its default `fog_sky_affect` of 1.0, the sky — at infinite
  distance — fogs 100% toward the near-black fog colour and renders
  black, so the pass sets `fog_sky_affect = 0.0`. The panorama's own
  left/right edges do not match, so a faint vertical seam shows where
  the panorama wraps — a property of the source photo, not the game.
- **Trees (`scripts/tree.gd`).** Reusable tree models for the future
  overpass (NOT placed in the garage/factory flow, and the overpass
  location itself is NOT built): tapered trunk + branches with the
  bark photograph (grooves, moss, lichen), canopy blobs with the
  foliage photograph (dense leaves, dappled light), varied tints per
  blob. `TreeModel.build(height, seed)` returns a Node3D ready to
  place in an outdoor location.
- **Icon (`assets/icon.png`, `project.godot`).** The project icon is
  now a photorealistic hazmat hero in the same photographic style as
  the face textures — acid-yellow hood, green visor with a real face
  faintly behind it, gas mask with dual round filters, dark
  background with red emergency glow, no text — set as
  `application/config/icon` so Godot and Summer Engine use it as the
  game's icon. It still reads at 64 px: yellow hood, green visor and
  black mask silhouette. The 1024 × 1024 PNG (downscaled from the
  1600 × 1600 generation) ships in the Library zip.

**Judged honestly.** What reads as photographic now: the concrete
walls and pillars at close range (cracks, damp streaks, stains);
the rust on cars; the gunmetal on weapons; the cloudy sky; the
vein-streaked forearms at close range; the face plates (unchanged).
What still reads as textured geometry: the cars (wheels, glass and
rust help a lot, but the slab silhouette is still a box car); the
trees (photographic bark and leaf textures on obviously spherical
canopy blobs and cylinder trunks — they read as game trees with photo
textures, not photographs); the hero's helmet-cap photo reads dark
and its scratches do not resolve at gameplay distance; at normal TPS
distance all of it correctly reads as texture, not individually
visible detail. Textures do not change geometry — a cylinder limb
stays a cylinder. Staged shots: arm `/tmp/arm-veins.png`, weapon
`/tmp/weapon-gunmetal.png`, whole head `/tmp/head-whole.png`, car
`/tmp/car-photo.png`, wall `/tmp/wall-photo.png`, sky
`/tmp/sky-photo.png`, tree `/tmp/tree-photo.png`, TPS gameplay
`/tmp/tps-real.png`.

## Whole-game pass, second batch (done, verified 2026-10-28)

Everything Danny added after the first batch, same photo-real method:

- **One-piece real skin (no-mask rule).** The old curved face plates
  read as a mask stuck on the head (Danny circled the doubled face
  on the head's side). Heads are now ONE continuous photographic
  skin: a full head sphere (azimuth −180..+180) UV-mapped to a
  patched face photo whose outer strips were replaced with
  featureless side skin (the portrait's grey background sliver had
  shown as a light seam line), so there is no plate rim, no seam
  and no doubled side face anywhere — edges hide under the
  helmet/ears/jaw. Verified front AND side for the veteran and for
  Bombies. Bombie glow eyes are now discrete emissive spheres
  aligned to the photo's irises (the old full-head emission map
  made the whole head glow), deliberately oversized so they read
  in the dark garage.
- **Hands with fingers, foot-shaped feet.** Geometry, not texture:
  merged-box hands (palm + four fingers with proximal/knuckle/
  middle/knuckle/distal segments + thumb, mirrored per arm) and
  feet (ankle/heel/foot-body/toe + sole, toe-out pivot), skinned
  with the veiny photographic skin, built against Danny's weathered
  hands photos (knuckles, veins, palm lines, wrinkles). No more
  blob hands or square wedge feet, on heroes or Bombies.
- **Windswept trees (`scripts/tree.gd`).** Built to Danny's coastal
  tree photo: thin bent trunk, sparse branches, and a crown of
  crossed alpha-cutout planes using the photo's OWN crown
  silhouette (sky cut out in PIL, 24% opaque so real gaps show
  through) — never a cone, blob or disc. The first two attempts
  read as flying saucers (squashed spheres seen from below) and
  were thrown out. Still staged outdoors only; the overpass
  location itself is NOT built.
- **Reshaped cars.** Sedan/van/wagon body profiles with sloped
  glass, bumpers, grilles, chrome, mirrors, detailed wheels and
  emissive headlights/taillights, in five faded-paint tints; wrecks
  read as aged paint breaking into rust spots and peeling (the
  rusted-classic reference), not uniform rust. Paint and chrome
  catch the amber/red emergency light. Honest limit: still
  box-built underneath — flat sides, no true curved panels.
- **Water like the kingfisher photos.** Animated ripple shader,
  planar reflection (SubViewport mirror camera, 3rd-frame refresh)
  so the water mirrors pillars, lights and cars, murky depth
  colour, and wading splashes: opaque droplets frozen mid-air plus
  an expanding ripple ring at the splash point, verified in
  `/tmp/water-splash.png`. The ring reads slightly solid up close;
  at gameplay speed it reads as a ripple pulse.
- **Wreckage piles (`scripts/level_base.gd`).** Garage (12 piles)
  and factory (10 piles, visual only) built to the scrap photos:
  crushed bodies, tilted/twisted panels, cable loops, and distinct
  rusted mechanical parts (ribbed motor, toothed gear, wound
  rotor). The first staged shot read as a flat printed panel, so
  the piles were re-heaped (tilted slabs, ~0.9 m silhouette) and
  the big panels switched to the generated rust surface, with
  Danny's scrap-part crop kept for the small parts.
- **Storm + aurora skies.** Danny's clean storm-sea and aurora
  photos as panoramas. Two gotchas found by screenshot: the
  mirror-wrap made the aurora a symmetric tent (rebuilt as a
  single asymmetric curtain), and the staged sky camera faces pano
  longitude x≈0, so pastes placed at the pano centre never showed
  (rebuilt full-width, rolled so the subject sits at x=0). The
  cloudy panorama's wrap seam was also blended out (edge
  difference 46 → 1.5).
- **Reflections (RTX-on look, not path tracing).** Planar
  reflection for the garage water, reflection probes in both
  levels (UPDATE_ONCE), glossy low-roughness materials on wet
  floors and car paint, environment reflections. True RTX path
  tracing is NOT available in the GL Compatibility renderer —
  the goal is the RTX-on look via reflections, stated plainly.
- **Tactical weapons.** Veteran shotgun rebuilt to the tactical
  reference (single barrel, extended tube, vented shroud, ghost
  ring, pistol grip); tan SMG with curved mag, rail and emissive
  red dot; M16 rifle with carry handle; improvised gun keeps its
  chunky concept shape (twin pipes, tank, wire, gauge, brake)
  with worn gunmetal + wood furniture. FPS viewmodels pulled
  back and yawed so side details read instead of one big receiver
  box; the neon accent block was darkened. No sidearm exists in
  the game, so that part of the standard has nothing to apply to.
- **Sound from Danny's own recordings.** Gunshots cut from his
  two voice notes (his gunshot recordings, not speech) — rifle
  15.39–15.80 s, shotgun 33.68–34.35 s (lowpassed for depth), SMG
  32.15–32.42 s of voice note 2, all peak-normalized — replacing
  the earlier video cuts as the primary source. The explosion
  boom stays a video-cut supplement (the voice notes have no
  explosion). No reload click exists in either recording, so
  reload stays procedural. Audible judging happens on Danny's
  machine: this VM has only a dummy audio driver, so the run
  verifies sample loads and triggers, not sound quality.
- **Framed photo.** One whole clean lake photo hangs framed on
  the garage north wall (a survivor's keepsake) — implemented in
  `scripts/garage.gd`, code-verified; no screenshot confirms it
  yet (it sits 30 m from the TPS camera and the wall shot frames
  a different wall).
- **Anatomy layers (new).** Every person is built skeleton-inside,
  muscle-over-it, one continuous skin over that, clothes on top.
  The skeleton (skull with eye sockets + nasal cavity + jaw,
  spine, ribcage, pelvis, limb bones, finger/toe bones) and the
  muscle layer (photographic striated fibre: pecs, abs, deltoids,
  biceps/triceps, quads, calves) are built inside every body and
  hidden in normal play (no draw cost); they show in the anatomy
  staged shots and through Bombie decay wounds (a stripped
  forearm section with radius/ulna + muscle, exposed ribs through
  a torn wound). Limbs are reshaped to muscle volumes (quad/calf/
  bicep/forearm bulges), not plain cylinders. Eyes: the bare skull
  has true holes with eyeballs recessed in the sockets; photo
  heads keep their painted eyes (cutting holes + inserting 3D
  balls was tried and reverted — square holes and doll eyes read
  far worse), and the Bombie glow sits nearly flush (0.003 proud)
  in the photo's dark socket area instead of the old 0.020-proud
  discs. One continuous skin, honestly: one-piece head sphere,
  one skin material family on all bare parts, overlapped joints —
  a literal single whole-body mesh is not feasible with code
  primitives, and is not claimed.
- **Watermark rule kept.** Watermarked photos (Alamy crowd,
  Shutterstock selfie, Vecteezy friends, Pngtree palms, 123RF
  hands, Dreamstime storm) stayed references only and were never
  baked in. Clean photos were cropped to surface detail only,
  except the framed lake photo above.

**Judged honestly, second batch.** What reads as photographic
now: one-piece head skins front and side; fingered hands and
foot-shaped feet at close range; the windswept tree crown
silhouette; rusted wreckage piles; storm and aurora skies; the
tactical shotgun's ghost ring and the SMG's red dot. What still
reads as textured geometry: cars (flat sides under the rust);
the hero's face dim/green behind the visor; the TPS hero's back
nearly a silhouette in the dark garage (detail resolves in FPS
and front views); the water ripple ring slightly solid up close;
the storm panorama soft (small source photo). Anatomy, judged
honestly: the bare skull + ribcage + muscle read as anatomy at
full body and close range; finger bones read with knuckle
joints; the skull's eyes sit in sockets; the muscle masses read
as muscle, but the limbs are still primitive volumes, not
scanned anatomy. Staged shots:
`/tmp/anatomy-full.png`, `/tmp/skull-sockets.png`,
`/tmp/anatomy-hand.png`, `/tmp/head-whole.png`,
`/tmp/head-side.png`, `/tmp/bombie-side.png`,
`/tmp/hands-fingers.png`, `/tmp/feet-shape.png`,
`/tmp/wreckage-pile.png`, `/tmp/tree-photo.png`,
`/tmp/sky-storm.png`, `/tmp/sky-aurora.png`,
`/tmp/weapon-gunmetal.png`, `/tmp/weapon-shotgun.png`,
`/tmp/weapon-smg.png`, `/tmp/water-splash.png`,
`/tmp/arm-veins.png`, `/tmp/car-photo.png`,
`/tmp/wall-photo.png`, `/tmp/tps-real.png`. Full self-play: WON at t=200.5 (garage rounds 1–3 → factory rooms 1–3) with ZERO script errors on the final code; test-driver wall-follow fired once (final room), stillness-unstick zero times. (An intermediate run stalled on the last garage Bombie — a pre-existing simple-steering pocket, not a regression — which the wall-follow seek addresses; pre-anatomy code had also won at t=189.5.)

## Open it in Summer Engine

Summer Engine (macOS / Windows) → open this folder as a project. The main
scene is `main.tscn`.

> Note: Summer Engine has no Linux build yet, so this project was built and
> verified on Linux with stock Godot 4.6.3 instead of the Summer editor.

## Verify without the editor (stock Godot 4.6+)

```bash
# Import once (builds .godot/ caches):
godot --headless --import --path .
# Boot + self-play: garage rounds 1-3, then factory rooms 1-3, win screen.
# Saves frames to /tmp/dz-shot-*.png and /tmp/dz2-*.png:
DZ_SELFTEST=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720
# Portrait shoot (factory, third person, one of each Bombie type in frame):
DZ_SELFTEST=1 DZ_PORTRAIT=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720
```

The template's own probe also works once Summer Engine is available:

```bash
bash tests/autopilot/run.sh
```

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look (Shift sprint, Space jump) |
| Left click | Fire |
| Right click (hold) | Aim down sights |
| R | Reload |
| G | Throw grenade (toxic for hazmat, frag for veteran; survivor has none) |
| 1 / 2 / Q | Place mine / acid trap / selected trap (hazmat only) |
| Tab | Switch squad member (factory onwards) |
| Ctrl (while sprinting, survivor) | Slide |
| V | First / third person |
| F | Flashlight |
| Esc | Release mouse |
