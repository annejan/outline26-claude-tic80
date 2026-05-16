# Prompts

A log of the main prompts that drove this demo from nothing to the
shipped version. Repetitions ("run it", "play it", etc.) are omitted.
Original wording (and typos) preserved.

## Phase 1 — discovery

> do you know TIC-80 lua ?

> yes a quick demo plz

> can you open and run it from commandline ?

(*launched, crashed — turned out the system TIC-80 dev build segfaults
on cart load; user installed the Flatpak stable build.*)

## Phase 2 — direction

> What kind of demo effects are you thinking ?

> s go *(let's go — picked the multi-scene demo route over a single
> polished effect)*

> do a char count

> do you know a bit about size coding on tic-80 ? plz make it smaller

(*resulted in the `minimal` branch — ~882 bytes, 38 lines.*)

## Phase 3 — repo + scale up

> let's git init first

> and branch for minimal version

> but from main or master let's add more to this demo

> more effects

> them voxels are damn ugly . . the music is boring as fuck

(*rewrote voxel rendering and replaced single-note music with multi-
track chiptune: triangle/square/saw/noise waveforms poked into
`0x0FFE4`, multi-SFX kick/snare/hihat/lead/bass.*)

> this is the way to go . . just more epic on all fronts

## Phase 4 — story

> this is epic . . but now it needs a bit of flow or story telling . .
> let's just make it claudes first atempt at tic80s and have it be a
> nice layererd story told by great and epic effects

(*the pivotal prompt. Added the awakening scene, per-scene captions
in Claude's POV, slide-in scene titles, music intensity that layers
in by phase, and an outro credits roll.*)

## Phase 5 — voxel iteration

> the voxels are a bit driving into a wall . . right now . . but
> almost perfect

> the voxels are still too tame / low .. high up overview . . this
> needs to be more epic

> the voxels are still the weakest part .. feels to linear .. not
> epic enough . . also we want to hang around a bit longer in the
> outro credits part . . also be sure to greet everyone etc

(*final voxel pass: banking S-curve camera path with matching yaw,
multi-frequency altitude bob, ridge term in the heightmap, snow caps
at h≥27. Outro expanded to 83 lines with full demoscene greetings.*)

> the credits etc get cut off before they are finished .. wait untill
> last line is at top of screen in vertical scroller before restarting

(*made `OUTRO_LEN` compute from credits length so the last line
always passes the top of the screen before looping.*)

## Phase 6 — release

> can we get it ready for release

> how many KBs ?

> or is it perfect as it is . .

> *(GitHub setup snippet pasted)*
> echo "# outline26-claude-tic80" >> README.md
> git init
> git add README.md
> git commit -m "first commit"
> git branch -M main
> git remote add origin git@github.com:annejan/outline26-claude-tic80.git
> git push -u origin main

(*wrote a real README instead of the stub, committed it, pushed both
`main` and `minimal` branches to GitHub.*)

> this is awesome sofar .. what to add ?

> let's keep it for today

## Meta

Total commits: 6 on `main`, 1 on `minimal`.
Final `demo.lua`: 744 lines / ~17.8 KB.
Final `demo.tic` cart: ~18.6 KB (well under the 256 KB Pro limit).

Model: Claude Opus 4.7. Harness: Claude Code.
