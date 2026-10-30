**DEAD AIR**

**CHANNEL ZERO**

**FULL ROBLOX GAME DESIGN + BUILD SPECIFICATION**

*A first-person analog-horror survival mystery for 1--4 players*

  -----------------------------------------------------------------------
  **CORE SELLING POINT\
  **Players can inspect recordings of the future and edit a limited
  number of events. Every edit changes what happens in the real world and
  can create a new danger elsewhere.
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

Working title • Original concept • Roblox Studio / Luau implementation
target

# HOW TO USE THIS DOCUMENT

Send this entire document to the AI coding agent that will build the
Roblox game. Ask it to follow the implementation stages in order, create
a real playable project rather than only giving advice, and report
clearly which files, instances and systems it actually created. The
image links and search phrases are visual research references, not
assets that the developer has permission to copy.

## Contents

-   1\. Inspiration and originality boundaries

-   2\. Game pitch, premise and objectives

-   3\. The unique future-editing mechanic

-   4\. Core loop and a sample mission

-   5\. Horror, tension and scare design

-   6\. Entity design and anomaly types

-   7\. Map, rooms and level design

-   8\. Visual direction, lighting and model specifications

-   9\. Full UI and controls

-   10\. Progression, endgame and replayability

-   11\. Monetisation: passes, products and fair revives

-   12\. Roblox architecture and data model

-   13\. Audio, accessibility, optimisation and security

-   14\. Build stages and acceptance tests

-   15\. Visual-reference pack and external links

-   16\. Copy-and-paste AI implementation prompt

# 1. INSPIRATION AND ORIGINALITY BOUNDARIES

The inspiration is the Roblox analog-horror game ANALOG by Kioverse
Games, especially the premise of an organisation investigating anomalous
sites and the \'record, report, survive\' fantasy. Its public
description mentions recording, classified telemetry, entities, signal
quality and clearance. This project should borrow broad genre
appeal---surveillance, uncertainty, eerie broadcasts and evidence
gathering---not copy its maps, characters, names, UI, story, dialogue,
assets or exact mechanics.

Reference game: https://www.roblox.com/games/105916934349181/ANALOG

The core concept here is DEAD AIR: CHANNEL ZERO. It takes place in an
abandoned regional television station in 1997. Every night, the station
broadcasts events before they happen. Players can alter selected events
in the footage, but the change produces linked consequences in the
world.

  -----------------------------------------------------------------------
  **ORIGINALITY NOTE\
  **No one can guarantee that no other Roblox game uses a related idea.
  The intended differentiator is the exact combination of editable
  predictive surveillance, linked event consequences, shared co-op
  decisions and a long-form broadcast mystery. Search Roblox and YouTube
  before release to check for close competitors.
  -----------------------------------------------------------------------

  -----------------------------------------------------------------------

## Genre principles to preserve

-   Ordinary spaces become threatening when small details change.

-   Uncertainty and anticipation matter more than constant jumpscares.

-   Players discover the story from tapes, environmental clues and
    contradictory instructions.

-   The monster has learnable rules, but the player does not know every
    consequence immediately.

-   The experience should be scary through sound, timing and
    context---not only darkness or loud noises.

# 2. GAME PITCH, PREMISE AND OBJECTIVES

## Title and format

DEAD AIR: CHANNEL ZERO (working title). First-person co-op horror
mystery for 1--4 players. Aim for 12--18 minutes per standard case. The
game should also be completable solo.

## Tagline

"The recording isn\'t showing you the past. It\'s showing you what
happens next."

## Premise

In 1997, a regional television station mysteriously shut down. Nineteen
years later, it begins transmitting a programme at 00:00 every night.
The broadcast shows events inside the building before they happen. A
fictional government recovery division sends investigators to recover
the station's final broadcast and shut it down. Early tapes show
harmless events; later tapes show the investigators themselves,
including events in which they may die.

## Objectives at three scales

-   Every run: recover three transmission components, survive the active
    broadcast cycle and reach extraction with evidence.

-   Each case: reconstruct a missing part of the broadcast, identify the
    local anomaly rules and unlock the next part of the station.

-   Campaign: collect seven master recordings, discover the source and
    purpose of the predictions, reach the original transmitter and
    decide whether to destroy, preserve or broadcast the final tape.

## Audience and tone

Target a broad Roblox audience, including younger players. Use suspense,
uncanny imagery, mild chase peril and non-graphic failure. Avoid gore,
disturbing realistic injury and unavoidable surprise deaths. Include a
low-intensity option for visual/audio effects.

# 3. THE UNIQUE FUTURE-EDITING MECHANIC

The Time-Shift Deck lets players inspect future footage, scrub through a
timeline and change a small number of defined event conditions. Players
do not edit arbitrary pixels; each video is a representation of real
scripted game events.

## Three rules

1.  The footage is a genuine prediction unless players interfere. It may
    be incomplete, so investigate before editing.

2.  Players edit conditions, not reality directly. Valid edits can
    change a light, door, sound, object\'s state or scripted route. They
    cannot delete the monster or skip the entire mission.

3.  Every edit has a defined consequence. A change can redirect the
    Presenter or make a different route dangerous. Consequences are
    hinted at by clues and are deterministic within the current case
    seed.

## Example event chain

Lights ON → Presenter avoids the east corridor → Presenter enters the
control room → the control room becomes unsafe. The team may instead
leave the lights OFF and risk the corridor. This creates a decision
rather than a random punishment.

## Editing interaction

4.  Interact with a tape deck, camera terminal or portable monitor.

5.  Choose a camera and scrub through the future footage.

6.  Pause and inspect individual frames or event markers.

7.  Select a scripted event and see its original state and allowed
    alternatives.

8.  Read clues and a warning if a linked event is detected.

9.  Commit the edit by spending one charge, or cancel without cost.

10. The server validates and commits the edit, then updates linked
    events and all clients.

## Fairness rules

-   Every event has a unique ID, a timestamp, a location and explicit
    allowed states.

-   Consequences are authored and tested; do not randomly punish players
    for experimenting.

-   Invalid edits never spend charges.

-   No event can be edited twice unless its configuration explicitly
    allows it.

-   Prevent infinite chains and contradictory event schedules.

-   Clues should make a consequence understandable in hindsight, and
    often predictable before the edit.

# 4. CORE LOOP AND SAMPLE MISSION

## Core loop

11. Accept a case, select equipment and hear the briefing.

12. Enter the station and explore.

13. Restore power and locate the first tape.

14. Analyse the footage and identify the predicted event.

15. Discuss whether to edit the event and commit a limited charge.

16. Survive the event and any linked consequence.

17. Recover three transmission components and optional evidence.

18. Reach extraction; choose whether to leave or risk an optional room
    for a valuable tape.

19. Receive a case report, rewards and new clues; return to the
    headquarters/lobby.

## Sample 14-minute run

  -----------------------------------------------------------------------
  **Time**                **Phase**               **Example**
  ----------------------- ----------------------- -----------------------
  00:00                   Briefing                The team is told that a
                                                  transmission failed at
                                                  00:17 even though the
                                                  station was supposedly
                                                  empty.

  02:00                   First tape              Footage shows the team
                                                  in the lobby, but one
                                                  player\'s avatar faces
                                                  the wall while the real
                                                  player faces the group.

  04:00                   First edit              The tape predicts the
                                                  lobby lights will go
                                                  out and a figure will
                                                  enter. The team notices
                                                  the figure waiting
                                                  outside the control
                                                  room in a later frame.

  07:00                   Consequence             The team keeps the
                                                  lights on. The figure
                                                  avoids the lobby, but a
                                                  monitor shows it behind
                                                  the player who made the
                                                  edit. The team uses
                                                  footage to choose a
                                                  safe route.

  10:00                   Recovery                Players restore the
                                                  transmitter, retrieve a
                                                  reel and open an
                                                  archive. The station
                                                  begins broadcasting
                                                  their own voices from
                                                  earlier in the run.

  14:00                   Extraction              The team can escape
                                                  with current evidence
                                                  or risk one more room
                                                  to recover a tape that
                                                  reveals more about the
                                                  station.
  -----------------------------------------------------------------------

These are pacing targets, not fixed minute-by-minute triggers. Adjust
event timing to player progress so the game does not punish slower
investigators unfairly.

# 5. HORROR, TENSION AND SCARE DESIGN

## Explain it like the player is nine

Imagine you and your friends find a video of a hallway. In the video,
the lights go out and a tall man appears. You look at the real hallway
and it is empty. You can leave the video alone, or change it so the
lights stay on. If you change it, the man may not enter the
hallway---but he might appear somewhere else. You do not know if you
made things safer or worse. That is the main scare.

## Five ways to create tension

20. Something feels wrong: a figure appears on a monitor, but when the
    player turns around the room is empty.

21. Hear before seeing: distant footsteps, a radio click or a chair
    scrape comes from a room the player thought was empty.

22. A meaningful choice: changing a recording might save one teammate
    but make another route unsafe.

23. The discovery/chase: the lights dip, the camera feed updates, a
    sound cue signals danger and the player must break line of sight and
    escape.

24. False safety: the player reaches extraction, the sound stops, then a
    monitor shows a recording of the player still inside.

## A fair fright sequence

25. Foreshadow: a tape shows the Presenter at the end of a corridor.

26. Uncertainty: the real corridor is empty, but the signal meter
    flickers.

27. Confirmation: a distant light switches off in the same order as the
    tape.

28. Near discovery: the player sees a silhouette briefly through glass.

29. Pursuit: the Presenter enters a hunting state with an audible cue
    and a route to escape.

30. Release: the player reaches a safe area; reduce sound and visual
    distortion so the next scare has contrast.

## Rules for good scares

-   Do not use a jumpscare every few seconds; it becomes predictable and
    tiring.

-   Give players cues they can learn: footsteps, monitor static,
    fluorescent buzz changes and tape timestamps.

-   Use silence and normal-looking empty rooms between scary moments.

-   Never make mandatory survival depend on an invisible, untelegraphed
    instant kill.

-   Allow players to learn, recover and feel clever when they correctly
    predict an event.

-   Provide reduced camera shake, lower distortion, adjustable sound and
    subtitle options.

# 6. ENTITY DESIGN AND ANOMALIES

## The Presenter

An original tall figure wearing an outdated formal suit. Its face is
obscured by a shifting television image. It is rarely visible for long.
Its defining rule: it follows the last valid version of an event, not
always the current world state.

  -----------------------------------------------------------------------
  **State**               **Behaviour**           **Player response**
  ----------------------- ----------------------- -----------------------
  Dormant                 Appears only in footage Observe and document.
                          or reflections.         

  Observing               Watches from a          Avoid repeated edits
                          distance.               nearby.

  Displaced               Appears at a location   Check monitors and
                          affected by an edit.    reroute.

  Hunting                 Pursues a player after  Break line of sight,
                          a dangerous event       use safe route, shut
                          chain.                  down a nearby monitor
                                                  when appropriate.

  Rewinding               A room briefly replays  Use the updated route
                          its previous state.     rather than blindly
                                                  following the old one.
  -----------------------------------------------------------------------

## Survival rules

-   Players cannot kill the Presenter.

-   Line of sight matters; it does not always know every player\'s
    position.

-   Monitors reveal its position but prolonged use may increase its
    awareness.

-   Players can use learned event rules to redirect it.

-   A solo player can complete every mandatory objective.

-   Movement and target changes are server-authoritative; client effects
    only add presentation.

## Two supporting anomalies for the first release

THE LOOP: repeats a short sequence in a room. Players identify one
detail that differs between repetitions to unlock the exit.

THE CALLER: broadcasts false instructions through radios and speakers.
Players compare timestamps and source IDs to distinguish it from
legitimate mission instructions.

Build only the Presenter and these two simpler anomalies after the core
prototype works.

# 7. MAP AND LEVEL DESIGN

Create one compact, connected map: Broadcast Station 04. Use locked
doors, maintenance passages and loops that gradually become shortcuts.
The player should learn the layout while the Presenter makes familiar
routes feel unsafe.

**1. Reception lobby ---** Spawn, mission briefing terminal, first tape
and safe tutorial. Main doors lock when the broadcast starts.

**2. Control room ---** Main hub. Time-Shift Deck and several camera
feeds.

**3. Tape archive ---** Story evidence, optional tapes and key to the
transmitter room.

**4. Editing suite ---** Teaches timeline inspection, event editing and
linked consequences.

**5. Generator room ---** Restore power; open routes and activate
cameras.

**6. East corridor ---** First major Presenter encounter. Alternate
routes unlocked by interpreting footage.

**7. Transmitter chamber ---** Final objective, climax and extraction
route.

## Map layout rules

-   Keep the first map compact enough to learn within one run.

-   Provide at least two route choices during the major chase.

-   Make doors, cameras, fuses, tape decks and objective components
    clearly interactable.

-   Use landmarks and room labels so players can communicate under
    pressure.

-   Do not hide essential objective items behind pixel-perfect
    searching.

-   Use collision and pathfinding geometry that works for Roblox
    avatars, including mobile players.

# 8. VISUAL DIRECTION, LIGHTING AND MODEL SPECIFICATIONS

## Art direction

-   Palette: muted green, dirty cream, warm grey, dusty brown and faded
    industrial blue; reserve red for exceptional warnings.

-   Materials: painted metal, stained concrete, vinyl flooring, dusty
    plastic, old glass, fabric office chairs and aged paper labels.

-   Era: believable late-1990s broadcast workplace---CRT monitors, tape
    decks, bulky beige computers, physical switches and fluorescent
    ceiling panels.

-   Shape language: practical, boxy, readable forms; use silhouettes and
    simple geometry rather than visual clutter.

-   Surface detail: grime and wear at corners, handprints near switches,
    faded labels, cable bundles, subtle water stains and dust near
    unused equipment.

-   Avoid copying distinctive models, creature designs, logos or maps
    from ANALOG or any other game.

## Lighting starting values

These are starting points to test in Roblox Studio, not universal final
values. Use Lighting, Atmosphere, ColorCorrectionEffect, BloomEffect
sparingly, and local PointLight/SpotLight/SurfaceLight sources. Prefer a
coherent dark scene over making the whole map unreadable.

  -----------------------------------------------------------------------
  **Element**                         **Specification**
  ----------------------------------- -----------------------------------
  Global Lighting                     Technology: ShadowMap or Future
                                      after performance testing;
                                      ClockTime 0--2; Brightness roughly
                                      1--1.5; ExposureCompensation around
                                      -0.15 to -0.4; Ambient and
                                      OutdoorAmbient muted grey-green.

  Atmosphere                          Low density, modest haze and
                                      restrained colour. Do not fill
                                      small indoor rooms with thick fog.

  ColorCorrection                     Saturation around -0.2 to -0.45;
                                      modest contrast increase; slight
                                      green/grey tint. Avoid extreme
                                      monochrome unless a special camera
                                      mode is active.

  Bloom                               Very subtle, mainly on bright CRTs
                                      and emergency lights. Avoid large
                                      glowing halos.

  Fluorescent fixtures                Cool, slightly green-white light;
                                      mostly soft/limited range;
                                      occasional authored flicker
                                      sequence.

  Emergency lighting                  Muted amber/red, used for important
                                      story beats and power failures.

  CRT screens                         SurfaceGui or screen material plus
                                      a small local light where useful.
                                      Keep light range low so screens do
                                      not illuminate entire rooms.

  Flashlight                          Readable cone and moderate range;
                                      must help navigation rather than
                                      wash out the whole map.

  Shadows                             Keep corners and long corridors
                                      atmospheric, but ensure key doors
                                      and objective items remain visible.

  Performance                         Limit overlapping dynamic lights,
                                      shadow-casting lights and expensive
                                      post-processing; test on low-end
                                      mobile.
  -----------------------------------------------------------------------

## Model and asset specifications

  -----------------------------------------------------------------------
  **Asset**                           **Specification**
  ----------------------------------- -----------------------------------
  Environment modules                 Build reusable wall, corner,
                                      doorframe, floor, ceiling, pipe and
                                      cable modules. Use consistent grid
                                      increments, e.g. 4-stud or 2-stud
                                      snapping. Avoid tiny decorative
                                      geometry that does not affect the
                                      silhouette.

  Room dimensions                     Typical corridor width 8--12 studs;
                                      standard door opening about 4--5
                                      studs wide and 7--9 studs high;
                                      ceiling height about 10--14 studs.
                                      Tune to the chosen avatar scale and
                                      pathfinding.

  Doors                               Use a clear pivot/hinge, defined
                                      open/closed states, interaction
                                      prompt, sound and server-side lock
                                      state. Do not make door collision
                                      inconsistent with animation.

  CRT monitors                        Simple box casing, bevelled screen
                                      rim, dark glass, screen SurfaceGui
                                      or material, optional knobs and
                                      vents. Keep knobs decorative unless
                                      gameplay needs them.

  Tape decks                          Readable slot, buttons, reels or
                                      cassette slot, interaction prompt
                                      and state indicators. Only add
                                      moving parts that communicate
                                      state.

  VHS tapes                           Small reusable prop with label,
                                      unique tape ID and optional icon.
                                      Tapes should be distinguishable by
                                      label/colour without relying on
                                      colour alone.

  Cameras                             Static cameras with unique camera
                                      IDs, location IDs and authored
                                      event timelines. Show a brief
                                      signal loss when a camera is
                                      disabled.

  Generator                           Modular industrial body, control
                                      panel, cables and status lights.
                                      One main interaction with clear
                                      stages: unpowered, repairing,
                                      powered.

  Presenter                           One readable silhouette: tall
                                      humanoid, formal jacket, narrow
                                      shoulders/long limbs within Roblox
                                      rig constraints, face area with
                                      animated static texture or UI.
                                      Avoid high part counts and gore.

  Materials and textures              Use tiling textures where possible.
                                      Keep most surfaces low-to-medium
                                      detail. Reserve custom high-detail
                                      textures for hero props and key
                                      evidence.

  Collision                           Use simple collision proxies for
                                      clutter and decorative assets.
                                      Ensure doors, props and pathfinding
                                      agents do not snag.

  Asset provenance                    Use original assets, properly
                                      licensed assets or Roblox Creator
                                      Store assets whose terms permit
                                      use. Never rip models, images,
                                      audio or textures from another
                                      game/video.
  -----------------------------------------------------------------------

## Suggested modelling workflow

31. Greybox the entire map with simple Parts first; test movement, room
    scale and routes.

32. Create modular environment pieces and reusable props.

33. Build hero props (Time-Shift Deck, CRTs, tape decks and generator)
    as separate models with named interaction points.

34. Use a low-poly, clean silhouette for the Presenter; animate with a
    simple rig and limited movements.

35. Add materials and lighting only after gameplay paths are readable.

36. Add subtle decals and wear after performance testing.

# 9. FULL UI AND CONTROLS

## Main menu

-   Background: slow camera pan across a dead broadcast control room.
    CRTs show fragments of footage.

-   Header: NATIONAL BROADCAST RECOVERY DIVISION; title DEAD AIR;
    subtitle CHANNEL ZERO // SIGNAL DETECTED.

-   Buttons: Case Select, Evidence Archive, Equipment, Settings,
    Credits.

-   Show a short status line such as SIGNAL RECEIVED: 00:00:00.

-   Use readable text, strong contrast, controller focus and
    mobile-friendly touch targets.

## In-game HUD

-   Top left: case name and one main objective plus optional clue.

-   Top right: signal quality 0--100%.

-   Centre: crosshair and contextual prompt only when useful.

-   Bottom left: edit charges remaining.

-   Bottom centre: active tool and control hint.

-   Bottom right: REC indicator, tape time and recording state.

-   Danger effects: signal flicker, timestamp jump, unexpected REC
    indicator, subtle distortion; do not rely on red screen flashes
    alone.

## Time-Shift Deck screen

-   Camera selection and camera/location name.

-   Footage viewport with timestamp and frame number.

-   Timeline scrubber with event markers; pause, play and frame-step
    controls.

-   Selected event details: original state, proposed state and allowed
    alternatives.

-   Linked-event warning with a clue hint when available.

-   Commit Edit button showing charge cost, plus Cancel and Close.

-   Display remaining edit charges and block invalid actions with clear
    explanations.

## Case report

Display result (successful extraction, partial extraction or failed
case), recovered components, tapes discovered, predictions interpreted,
edits made, team survival, case grade D--S, rewards and newly unlocked
evidence.

## Proposed controls

  -----------------------------------------------------------------------
  **Action**        **PC**            **Mobile**        **Controller**
  ----------------- ----------------- ----------------- -----------------
  Interact          E                 On-screen tap     Context button
                                      prompt            

  Equip camcorder   1                 Tool button       D-pad shortcut

  Open deck         R                 Deck button       Y / Triangle

  Sprint            Shift             Sprint button     Left-stick click

  Inspect           Hold right mouse  Hold inspect      Hold context
                                      button            

  Pause             Esc               Menu button       Start
  -----------------------------------------------------------------------

These are proposed bindings. Check for conflicts with Roblox defaults.
Support desktop and mobile first; add controller support where
practical. Provide a settings screen for sensitivity, subtitles, camera
shake, distortion intensity and audio levels.

# 10. PROGRESSION, ENDGAME AND REPLAYABILITY

## Progression systems

-   Evidence archive: recovered tapes remain unlocked permanently and
    can be replayed in the lobby.

-   Recovery credits: earned through successful cases; spend on
    cosmetics and non-essential equipment variations.

-   Research points: earned for identifying anomalies and recovering
    optional evidence.

-   Clearance: earned from story milestones and unlocks cases/areas, not
    combat strength.

-   Equipment: alternate camcorders, portable signal analyser, audio
    recorder and handheld monitor. Equipment changes evidence-gathering
    options, not whether the player can win.

-   Case variants: repeat runs change selected tape locations, clues and
    event chains while preserving story logic.

-   Grades D--S: reward survival, optional evidence, correct predictions
    and smart use of edits, not speed alone.

## What players do after finishing the main story

-   Unlock the seven master recordings and replay tapes to find hidden
    frames and new details.

-   Earn alternate endings by meeting evidence thresholds and making
    different major choices.

-   Play case variants with different but authored event chains.

-   Try Restricted mode and Archive Challenge with fixed seeds and
    leaderboards.

-   Complete optional investigator challenges, such as finishing with
    unused edit charges or recovering all evidence.

-   Collect non-power-affecting uniforms, camcorder skins, lobby
    decorations and CRT menu themes.

-   Play weekly or seasonal case modifiers that remix the existing event
    graph without making the mystery incoherent.

-   Join friends as a helper/investigator and fill missing team slots;
    preserve solo completion as a valid route.

Endgame should not become an endless grind. The main story should have a
satisfying stopping point, with optional mastery challenges and new case
updates for players who want more.

# 11. MONETISATION: PASSES, PRODUCTS AND FAIR REVIVES

Use monetisation that supports development without selling story access
or making paid players much stronger. All example prices are starting
hypotheses in Robux, not guaranteed optimal prices. Test pricing and
check current Roblox policies before release.

## Recommended gamepasses

  -----------------------------------------------------------------------
  **Pass**                **Test price**          **Benefit**
  ----------------------- ----------------------- -----------------------
  Investigator\'s Locker  79--129 Robux           Extra cosmetic loadout
                                                  slots, uniform variants
                                                  and saved equipment
                                                  presets. No mandatory
                                                  gameplay advantage.

  Classic Broadcast Pack  99--149 Robux           Cosmetic CRT menu
                                                  themes, camcorder shell
                                                  skins and alternate REC
                                                  overlay. All gameplay
                                                  information stays
                                                  equally readable.

  Personal Quarters       79--149 Robux           Decorate a private
                                                  investigator room with
                                                  posters, desk items and
                                                  collectible tape
                                                  displays.

  Supporter Pass          149--249 Robux          Supporter badge,
                                                  nameplate and cosmetic
                                                  set. No exclusive story
                                                  clues or stronger
                                                  survival tools.

  Extra Loadout Presets   49--79 Robux            Convenience feature for
                                                  saving several tool
                                                  presets, if loadout
                                                  complexity justifies
                                                  it.
  -----------------------------------------------------------------------

## Developer products (repeat purchases)

  -----------------------------------------------------------------------
  **Product**             **Test price**          **Rules**
  ----------------------- ----------------------- -----------------------
  One Emergency Re-entry  15--29 Robux            If eliminated, return
  / Revive                                        once per mission at a
                                                  safe checkpoint with a
                                                  short re-entry delay.
                                                  Does not restore
                                                  consumed edit charges
                                                  or skip objectives.

  Team Recovery Token     39--59 Robux            One team-wide recovery
                                                  vote per case. Requires
                                                  the remaining team to
                                                  agree; once used, no
                                                  further revive
                                                  purchases in that run.

  Cosmetic Evidence       19--49 Robux            A themed set of
  Bundle                                          cosmetic labels, badges
                                                  or tape skins; no
                                                  exclusive lore.

  Lobby Decoration Bundle 29--79 Robux            Optional decor for
                                                  personal quarters or
                                                  team lobby, if
                                                  implemented.
  -----------------------------------------------------------------------

## Revive design rules

-   The game must remain fully completable without spending Robux.

-   Offer one optional revive per player per mission at most; consider
    one team recovery per run, not repeated paid retries.

-   Revive at a safe checkpoint with a brief invulnerability window and
    clear rules. Do not revive directly inside the monster\'s attack.

-   Do not sell guaranteed escape, invulnerability, unlimited edits or a
    skip to the ending.

-   Make it obvious what the purchase does before the player confirms
    it.

-   Do not use deceptive countdowns, guilt messages or pressure
    language, especially because Roblox includes younger players.

-   If players do not buy a revive, they may spectate until extraction
    or return to the lobby; do not force a purchase prompt.

-   All Developer Product purchases must be processed server-side with
    MarketplaceService.ProcessReceipt and safely granted once.

## Other monetisation rules

-   Do not paywall the seven main recordings, mandatory equipment or
    essential clues.

-   Do not sell loot boxes or random paid rewards as a core monetisation
    strategy.

-   Do not make paid players faster or harder for the entity to detect
    in a way that harms co-op balance.

-   Use MarketplaceService for passes/products, validate ownership and
    receipts server-side, and test purchase cancellation/failure.

-   Keep a free, fair core game and use cosmetic updates as the main
    long-term revenue path.

# 12. ROBLOX ARCHITECTURE AND DATA MODEL

## Recommended Explorer structure

-   ReplicatedStorage: Shared configuration/modules, RemoteEvents and
    RemoteFunctions.

-   ServerScriptService: MissionService, TimelineService, EntityService,
    EvidenceService, SignalService, InteractionService and DataService.

-   ServerStorage: entity models, mission templates and server-only
    assets.

-   StarterPlayer: client controllers and input handling.

-   StarterGui: HUD, main menu, case report and Time-Shift Deck.

-   Workspace: map, interactables, cameras, triggers and entity spawn
    points.

## Module responsibilities

  -----------------------------------------------------------------------
  **Module**                          **Responsibility**
  ----------------------------------- -----------------------------------
  MissionService                      Starts cases, tracks objectives,
                                      handles extraction/failure and
                                      cleans up the mission.

  TimelineService                     Stores events, validates edits,
                                      schedules consequences and
                                      replicates state.

  EvidenceService                     Handles tape discovery, evidence
                                      metadata and permanent unlocks.

  EntityService                       Controls Presenter state machine,
                                      pathfinding and target logic.

  SignalService                       Calculates signal quality and
                                      triggers presentation effects.

  InteractionService                  Validates range, object
                                      availability and player actions.

  DataService                         Loads/saves player progression with
                                      DataStoreService.

  UIController                        Updates client HUD and menus from
                                      replicated state.
  -----------------------------------------------------------------------

## Example event data

{

\"eventId\": \"east_corridor_lights\",

\"timestamp\": 172,

\"locationId\": \"EastCorridor\",

\"eventType\": \"LightingChange\",

\"originalState\": \"OFF\",

\"allowedStates\": \[\"OFF\", \"ON\"\],

\"defaultState\": \"OFF\",

\"editCost\": 1,

\"prerequisites\": \[\"generator_restored\"\],

\"consequenceEventIds\": \[\"presenter_route_change\"\],

\"clueId\": \"tape_04_frame_412\",

\"isEditable\": true,

\"committed\": false

}

This is illustrative JSON, not a complete Roblox implementation. Use
ModuleScripts or validated tables for production configuration.

## Timeline execution rules

37. Client sends event ID and requested state to the server.

38. Server checks mission, permissions, interaction range and deck
    access.

39. Server verifies event exists, is editable, has not been committed
    and satisfies prerequisites.

40. Server checks and deducts edit charges atomically.

41. Server records the selected state, updates linked event parameters
    and schedules consequences.

42. Server replicates updated timeline state to all players.

43. Invalid requests are rejected without charge loss. Log edits for
    debugging and case scoring.

44. Use explicit mission states: Lobby → Briefing → Active →
    ExtractionAvailable → Completed, with a Failure state and cleanup
    path.

## Signal system

Signal quality is a deterministic 0--100 value influenced by powered
relays, distance, room interference and anomaly effects. High quality
shows clear timestamps/event markers; medium quality obscures some
details; low quality may require repairing a relay or using another
camera. Signal quality must not randomly kill players.

## Multiplayer rules

-   Support 1--4 players per mission; all share the same timeline and
    edit-charge pool.

-   Prevent two players from committing conflicting edits to the same
    event at once.

-   Validate all interactions, objectives, extraction and rewards on the
    server.

-   If a player disconnects, remaining players can continue.

-   If everyone is eliminated, the mission fails.

-   Spectators may observe but cannot edit the timeline.

-   Rewards depend on mission result and each player\'s evidence
    contribution.

## Saving and security

-   Save unlocked cases, recovered evidence IDs, research points,
    credits, clearance, settings and owned cosmetics.

-   Use DataStoreService and UpdateAsync where appropriate; handle
    failed requests and avoid saving after every tiny interaction.

-   Autosave and save on departure, with safe retry/failure handling.

-   Never trust the client for currency, purchases, edit charges,
    unlocks or completion.

-   Use MarketplaceService.ProcessReceipt for Developer Products and
    safely grant each receipt once.

-   Use server-side distance checks and rate limits on remote requests.

-   Do not collect sensitive real-world information or use real
    surveillance footage.

# 13. AUDIO, ACCESSIBILITY AND OPTIMISATION

## Audio design

-   Use a quiet ambient bed: ventilation hum, electrical buzz, distant
    machinery and room tone.

-   Give each anomaly a recognisable audio language. The Presenter might
    be preceded by tape flutter, a low-frequency tone or a brief loss of
    ambience.

-   Use spatial audio and distance falloff so players can judge
    direction.

-   Make footsteps and chase cues readable; do not mask all important
    sounds with music.

-   Use silence before and after major scares. Avoid constant loud
    stingers.

-   Provide separate master, music, ambience and effects sliders plus
    subtitles for important audio cues.

## Accessibility

-   Subtitles for dialogue, radio instructions and critical audio cues.

-   Adjustable camera shake, distortion, flicker and motion effects.

-   Do not use rapid full-screen flashing as the only warning.

-   Clear text contrast, scalable text where practical, and
    non-colour-only indicators.

-   Large mobile touch controls and controller focus states.

-   A reduced-intensity setting that preserves gameplay information.

## Performance

-   Target stable performance on mid-range mobile devices as well as PC.

-   Use modular geometry, simple collision proxies and limited dynamic
    lights.

-   Avoid excessive transparent overlays and full-screen effects.

-   Use StreamingEnabled if the final map size benefits from it; keep
    mission-critical objects loaded or handled carefully.

-   Test pathfinding, doors and interaction prompts with actual Roblox
    avatar movement.

-   Use original or licensed assets; keep asset IDs organised and
    document dependencies.

# 14. BUILD STAGES AND ACCEPTANCE TESTS

**Stage 1 --- Core prototype:** One room, one monitor, one tape, one
editable event, one linked consequence and a working UI. Confirm the
mechanic is fun before adding content.

**Stage 2 --- First case:** Complete map, generator, three components,
extraction, Presenter AI and case report.

**Stage 3 --- Multiplayer:** Shared timeline, shared charges, conflict
handling, disconnect handling and solo compatibility.

**Stage 4 --- Persistence and economy:** Evidence archive, progression,
DataStore saves, gamepasses, Developer Products and receipt handling.

**Stage 5 --- Polish:** Lighting, audio, animation, accessibility,
mobile UI, performance and playtesting.

**Stage 6 --- Expansion:** Add other cases and the remaining master
recordings only after Case 01 is stable.

## Acceptance checklist

-   [ ] A player can start and finish Case 01.

-   [ ] The tutorial teaches movement, interaction, footage inspection,
    editing and escape.

-   [ ] Footage accurately predicts configured events.

-   [ ] A valid edit changes the real event and its linked consequence.

-   [ ] Invalid edits do not consume charges.

-   [ ] The Presenter can detect, pursue and lose players fairly.

-   [ ] Every mandatory objective is completable solo.

-   [ ] Two to four players share the same mission and timeline.

-   [ ] Extraction, failure and cleanup work.

-   [ ] Case report values are correct.

-   [ ] Progression and evidence persist across rejoining.

-   [ ] Desktop and mobile UI work; controller support is added where
    practical.

-   [ ] Monetisation works securely and the game is still completable
    without purchases.

-   [ ] No major feature is described as complete unless it has been
    tested.

# 15. VISUAL-REFERENCE PACK AND EXTERNAL LINKS

The earlier concept images were visual-search examples, not a unified
asset pack. Use the following references to study mood and broad visual
language. Do not copy another game\'s distinctive assets. The AI should
generate original models and use properly licensed material.

## Reference links

-   [[ANALOG on Roblox --- inspiration for genre and
    premise]{.underline}](https://www.roblox.com/games/105916934349181/ANALOG)

-   [[Roblox Creator Hub --- Light
    sources]{.underline}](https://create.roblox.com/docs/effects/light-sources)

-   [[Roblox DevForum --- How can I make an analog horror
    game?]{.underline}](https://devforum.roblox.com/t/how-can-i-make-an-analog-horror-game/1664979)

-   [[Roblox DevForum --- Analog horror graphics
    discussion]{.underline}](https://devforum.roblox.com/t/analog-horror-graphics/2836674)

-   [[YouTube search --- ANALOG Roblox horror
    gameplay]{.underline}](https://www.youtube.com/results?search_query=ANALOG+Roblox+horror+gameplay+Kioverse+Games)

-   [[YouTube search --- ANALOG Roblox full gameplay and
    reaction]{.underline}](https://www.youtube.com/results?search_query=Roblox+ANALOG+horror+full+gameplay)

-   [[YouTube search --- analog horror CRT/VHS
    atmosphere]{.underline}](https://www.youtube.com/results?search_query=analog+horror+CRT+VHS+surveillance+visuals)

-   [[Roblox Creator Store --- search for licensed/usable
    props]{.underline}](https://create.roblox.com/store/models?keyword=CRT%20monitor)

-   [[Roblox Creator Hub --- general
    documentation]{.underline}](https://create.roblox.com/docs)

## Image-search prompts for the art team

These are image-search links or prompt phrases for gathering mood
references. If the coding agent supports image attachments, attach
selected reference images separately. If it cannot access images, use
the descriptions as text prompts.

**01. Main menu / dead control room:** Abandoned 1990s television
broadcast control room at night, multiple CRT monitors, dusty mixing
console, dim fluorescent lights, dark green-grey palette, subtle VHS
grain, no visible monster, cinematic horror game environment.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Abandoned+1990s+television+broadcast+control+room+at+night,+multiple+CRT+monitors,+dusty+mixing+console,+dim+fluorescent+lights,+dark+green-grey+palette,+subtle+VHS+grain,+no+visible+monster,+cinematic+horror+game+environment.)

**02. Surveillance footage:** Grainy monochrome CCTV still of an empty
institutional corridor, timestamp overlay, mild tracking distortion,
fluorescent ceiling lights, distant doorway, restrained analog noise.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Grainy+monochrome+CCTV+still+of+an+empty+institutional+corridor,+timestamp+overlay,+mild+tracking+distortion,+fluorescent+ceiling+lights,+distant+doorway,+restrained+analog+noise.)

**03. Presenter silhouette:** Original analog horror creature concept:
tall featureless humanoid silhouette in an outdated formal 1990s suit,
face obscured by television static, standing at the end of a corridor,
no gore, readable silhouette.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Original+analog+horror+creature+concept:+tall+featureless+humanoid+silhouette+in+an+outdated+formal+1990s+suit,+face+obscured+by+television+static,+standing+at+the+end+of+a+corridor,+no+gore,+readable+silhouette.)

**04. Time-Shift Deck prop:** Original 1990s broadcast editing
workstation, VHS deck, chunky buttons, CRT screen, labels, worn plastic
and metal, functional industrial prop design, front three-quarter view.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Original+1990s+broadcast+editing+workstation,+VHS+deck,+chunky+buttons,+CRT+screen,+labels,+worn+plastic+and+metal,+functional+industrial+prop+design,+front+three-quarter+view.)

**05. Lobby:** Abandoned television station reception lobby, old chairs,
reception desk, wall clock, faded signage, dirty cream and grey
materials, dim fluorescent lighting.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Abandoned+television+station+reception+lobby,+old+chairs,+reception+desk,+wall+clock,+faded+signage,+dirty+cream+and+grey+materials,+dim+fluorescent+lighting.)

**06. Tape archive:** Small archive room with shelves of labelled VHS
tapes, metal filing cabinets, dusty paper folders, narrow overhead
lighting, realistic but game-friendly geometry.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Small+archive+room+with+shelves+of+labelled+VHS+tapes,+metal+filing+cabinets,+dusty+paper+folders,+narrow+overhead+lighting,+realistic+but+game-friendly+geometry.)

**07. Generator room:** Industrial basement generator room with old
electrical cabinets, bundled cables, pipes, breaker panel and emergency
amber lighting, clear navigable walkways.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Industrial+basement+generator+room+with+old+electrical+cabinets,+bundled+cables,+pipes,+breaker+panel+and+emergency+amber+lighting,+clear+navigable+walkways.)

**08. East corridor:** Long institutional corridor with fluorescent
lights, security camera, glass side window, muted green-grey colour,
deep but readable shadows, analog horror mood.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Long+institutional+corridor+with+fluorescent+lights,+security+camera,+glass+side+window,+muted+green-grey+colour,+deep+but+readable+shadows,+analog+horror+mood.)

**09. Transmitter chamber:** Large vintage television transmitter
chamber, industrial metal framework, old broadcast equipment, CRT
monitors, cables and a single red status lamp, cinematic climax room.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Large+vintage+television+transmitter+chamber,+industrial+metal+framework,+old+broadcast+equipment,+CRT+monitors,+cables+and+a+single+red+status+lamp,+cinematic+climax+room.)

**10. Time-Shift Deck UI:** Retro engineering interface on dark
green-black background, camera viewport, timeline with frame markers,
event state controls, amber linked-event warning, readable typography,
restrained borders.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Retro+engineering+interface+on+dark+green-black+background,+camera+viewport,+timeline+with+frame+markers,+event+state+controls,+amber+linked-event+warning,+readable+typography,+restrained+borders.)

**11. Main HUD:** Minimal first-person horror HUD mock-up, objective top
left, signal percentage top right, edit charges bottom left, REC and
tape timer bottom right, dark green monochrome terminal aesthetic.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=Minimal+first-person+horror+HUD+mock-up,+objective+top+left,+signal+percentage+top+right,+edit+charges+bottom+left,+REC+and+tape+timer+bottom+right,+dark+green+monochrome+terminal+aesthetic.)

**12. Case report:** 1990s government case report interface, evidence
checklist, recovered tape icons, case grade, green monochrome text on
dark background, minimal readable design.

> [[Open image
> search]{.underline}](https://www.google.com/search?tbm=isch&q=1990s+government+case+report+interface,+evidence+checklist,+recovered+tape+icons,+case+grade,+green+monochrome+text+on+dark+background,+minimal+readable+design.)

## Suggested visual assets to create

-   One 16:9 main-menu background concept.

-   One 16:9 surveillance corridor frame.

-   One character concept sheet for the Presenter: front, side, back and
    face/static close-up.

-   One model sheet for the Time-Shift Deck, CRT monitor and VHS tape.

-   One top-down map layout for Broadcast Station 04.

-   One HUD mock-up and one Time-Shift Deck UI mock-up.

-   One lighting reference per room, including normal power and
    emergency power variants.

# 16. COPY-AND-PASTE AI IMPLEMENTATION PROMPT

ROLE\
Act as a senior Roblox game developer, Luau programmer, multiplayer
systems engineer, UI/UX designer and horror game designer. Build a
playable Roblox Studio game named DEAD AIR: CHANNEL ZERO. Do not merely
provide a design document or disconnected example scripts. Create the
actual project if your environment supports it. Otherwise provide every
required script, exact Explorer location, required instance, asset
specification and setup step. Be honest about what you have and have not
implemented.

GAME\
A first-person analog-horror survival mystery for 1--4 players, with a
target case length of 12--18 minutes. It takes place in an abandoned
1997 television station. Every night the station broadcasts events
before they happen. Players work for a fictional recovery organisation
to recover three transmission components and extract. The campaign has
seven master recordings and a final choice to destroy, preserve or
broadcast the final tape.

CORE MECHANIC\
The Time-Shift Deck lets players inspect future footage and change a
limited number of scripted event conditions. Example: footage predicts a
corridor light turns OFF; the player edits it to ON; the Presenter
avoids the corridor and enters the control room instead. Each edit has
an authored consequence and clues should hint at it. Do not let players
edit arbitrary pixels or delete the monster. All event edits are
validated and committed by the server. Invalid edits do not consume
charges.

MAP\
Build one connected, compact first map named Broadcast Station 04 with
reception lobby, control room, tape archive, editing suite, generator
room, east corridor and transmitter chamber. Add locked doors,
maintenance passages, alternate routes, cameras, VHS tapes, computers,
switches, generator and three transmission components. Greybox and test
navigation before adding detail.

ENTITY\
Create the original Presenter: tall human silhouette in an outdated
formal suit, face obscured by TV static. States: Dormant, Observing,
Displaced, Hunting and Rewinding. Use server-side state transitions,
pathfinding, line-of-sight and fair warnings. Players cannot kill it.
The game must be completable solo.

HORROR\
Use foreshadowing, silence, monitor anomalies, distant sounds,
footsteps, changing timestamps and fair chases. Avoid constant
jumpscares and unfair instant kills. A scare should be foreshadowed,
become uncertain, then confirmed, create danger and finally release
tension. Support reduced distortion and camera shake.

ART, LIGHTING AND MODELS\
Use muted green, dirty cream, grey and brown; reserve red for important
warnings. Build reusable wall/floor/ceiling/door/pipe/cable modules,
practical 1990s CRTs, tape decks, VHS tapes, generator, cameras and
clear interaction points. Use simple collision proxies and moderate
detail. Suggested starting map dimensions: corridors 8--12 studs wide,
doors 4--5 studs wide and 7--9 studs high, ceilings 10--14 studs high;
tune to avatar scale. Start with Lighting ClockTime 0--2, Brightness
1--1.5, ExposureCompensation about -0.15 to -0.4, restrained green-grey
ambient, modest Atmosphere, subtle ColorCorrection and very subtle
Bloom. Use PointLight/SpotLight/SurfaceLight locally; limit dynamic
shadow lights and post-processing for mobile performance. Keep objective
items readable. All assets must be original or properly licensed.

UI\
Main menu: Case Select, Evidence Archive, Equipment, Settings and
Credits. In-game HUD: objective top left, signal quality top right,
crosshair/context prompt, edit charges bottom left, active tool hint and
REC/tape timer bottom right. Time-Shift Deck: camera selector, footage
viewport, timestamp/frame number, timeline scrubber, frame stepping,
selected event, original/proposed state, allowed states, linked-event
warning, charge cost, Commit, Cancel and Close. Case report: mission
result, components, tapes, predictions, edits, survival, grade, rewards
and unlocks. Support PC and mobile; controller where practical. Include
subtitles and settings for audio, sensitivity, camera shake and
distortion.

CORE LOOP\
Briefing → enter station → restore power/find tape → inspect future →
edit event → survive consequences → collect three components → extract
or risk optional evidence → case report and progression. First run
should teach every mandatory mechanic.

PROGRESSION / ENDGAME\
Save evidence archive, credits, research points, clearance, cosmetics
and unlocked cases. Players can replay tapes, find hidden frames, unlock
alternate endings, play case variants, attempt Restricted mode and
Archive Challenge, complete optional investigator challenges, decorate
personal quarters and collect cosmetics. Keep the main story satisfying
without endless grinding. Do not paywall story clues or essential
equipment.

MONETISATION\
Use fair optional monetisation. Suggested gamepasses: Investigator\'s
Locker (79--129 Robux) for cosmetic loadout slots/uniforms; Classic
Broadcast Pack (99--149) for cosmetic CRT/camcorder themes; Personal
Quarters (79--149) for room decorations; Supporter Pass (149--249) for
badge/nameplate/cosmetics; Extra Loadout Presets (49--79) if useful.
Suggested Developer Products: one emergency re-entry/revive (15--29
Robux, at most once per player per mission, safe checkpoint, no restored
edit charges); one team recovery token (39--59, one team vote per run);
cosmetic evidence bundle (19--49); lobby decoration bundle (29--79).
These prices are hypotheses to test. Never require Robux to finish the
game. No paid invulnerability, unlimited edits, guaranteed escape,
ending skip or exclusive story clues. Avoid deceptive prompts or
pressure. Use MarketplaceService, server-side ownership validation and
ProcessReceipt with safe one-time grants.

TECHNICAL ARCHITECTURE\
Use modules: MissionService, TimelineService, EntityService,
EvidenceService, SignalService, InteractionService, DataService and
UIController. Server controls mission state, timeline, entity,
objectives, rewards and saving. Client controls input, UI, camera
effects and presentation. Suggested Explorer: ReplicatedStorage (shared
modules/remotes), ServerScriptService (authoritative services),
ServerStorage (server-only assets/templates), StarterPlayer (client
controllers), StarterGui (UI), Workspace (map/interactables). Save
progression with DataStoreService; validate all remote calls, distances,
charges, unlocks and purchases. Handle failed saves, disconnects,
invalid requests and mission cleanup. Use deterministic signal quality
from 0--100 based on relays, distance, interference and anomalies. Use
staged camera footage tied to the same event config rather than trying
to record the whole 3D world.

BUILD ORDER\
Stage 1: one room, one tape, one editable event and one linked
consequence.\
Stage 2: full first map, three components, generator, extraction and
Presenter.\
Stage 3: multiplayer sync, shared charges, disconnect handling and solo
support.\
Stage 4: UI, progression, persistence and monetisation.\
Stage 5: audio, lighting, accessibility, optimisation and playtesting.\
Stage 6: add more cases only after Case 01 is stable.

ACCEPTANCE TESTS\
A player can start and finish Case 01; tutorial teaches mandatory
mechanics; footage predicts configured events; valid edit changes event
and consequence; invalid edit costs nothing; Presenter can detect, chase
and lose players fairly; all mandatory tasks work solo; 2--4 players
share timeline; extraction/failure/cleanup work; case report is correct;
progression persists; UI works on desktop/mobile; purchases are secure;
the game remains completable for free. Do not claim a feature is
complete until tested.

VISUAL REFERENCES\
Use the reference links and image-search prompts in Section 15 of the
attached design document. Treat them as mood references only. Do not
copy another game\'s maps, characters, logos, UI or assets. Generate
original models and use properly licensed assets.

DELIVERY\
Build in stages. After each stage, list scripts and instances created,
explain how to test them, list known bugs and wait for approval before
expanding if your environment supports iterative work. If you cannot
edit Roblox Studio directly, provide complete scripts and precise
installation steps rather than claiming to have created a place file.

# FINAL NOTE FOR THE DEVELOPER

Prioritise the playable future-editing mechanic, a fair and memorable
Presenter encounter, and a complete first case. A small finished game
with one excellent twist is more valuable than a large map full of
unfinished systems.
