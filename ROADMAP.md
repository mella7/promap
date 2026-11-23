# Roadmap

My plan for getting promap from a hardware test to something I can put on the store. Steps 0 to 5 are the actual product. Everything after that can wait until the first version works.

Steps go in order, each one needs the one before it. Two exceptions: step 1 needs no hardware so it runs alongside step 0, and the backend half of step 4 can start any time after step 1.

Every step has to end with something I can run and show. If I can't demo it, it's not done.

Stack: Flutter app, Android first. Calibration and scene logic as plain Dart packages. A small FastAPI service for the AI models.

Where things run: all the AI (segmentation, depth, generating animations, the assistant) runs in the cloud. Rendering to the projector always stays on the phone, it has to hit 60 fps and can't wait on the network. Generated animations get downloaded once and the phone warps and plays them. Decoding the scan stays on the phone for now, I'll move it to the cloud only if it's too slow on a real phone (check in step 2).

CI runs analyze and tests for every Dart package plus the schema check on each push (`.github/workflows/ci.yml`).

## Checkpoints

Three points where I stop and decide if it's worth going on:

1. **After step 0:** does my phone actually drive the projector as a separate display? If not, the fallback is a small receiver app on the projector itself, with the phone talking to it over Wi-Fi.
2. **After step 2:** does a mapped object in my room look good enough that I'd show it to a friend? If not, fix the scan quality or try a brighter projector before building anything else.
3. **After step 5:** show it to five people who aren't engineers. Do they want to try it themselves? If not, rethink who it's for and the themes before I spend money on AI generation.

## Where things are

| Step | Status |
| --- | --- |
| 0. Hardware check | Waiting on hardware |
| 1. Calibration core | Done, 25 tests passing |
| 2. Scan app | App shell runs on the laptop with the simulator. Phone part waiting on hardware |
| 3. Scene and renderer | Scene core done, 37 tests passing. Renderer not started |
| 4. Cloud service and auto surfaces | Mask to surface code done (mapping_core, 23 tests passing). Backend not started |
| 5. Effect library | Not started |
| 6. AI generation | Not started |
| 7. Release polish | Not started |
| 8. Later | Not started |

## Step 0 - Hardware check

Throwaway test app to make sure the phone can drive the projector and that I can control the camera. This goes first because if it fails, half the plan changes.

- [ ] Phone connected to the projector shows up in Android as a second display, not a mirror
- [ ] Different image on the projector than on the phone screen
- [ ] Read the projector's real resolution and output at exactly that
- [ ] Auto-keystone and any picture "enhancement" turned off on the projector
- [ ] Camera opens with exposure, focus and white balance locked, and they stay locked
- [ ] Project white, then black, and check the camera sees a clear difference
- [ ] Roughly measure how long a new frame takes to show up on the wall

Demo: camera preview on the phone while the projector shows a test grid at its native resolution, with sharp single-pixel lines.

Needs: phone and projector, nothing else.

## Step 1 - Calibration core (done)

Plain Dart package in `packages/calib_core`. Takes the captured frames of a scan and works out which projector pixel lights each camera pixel. No Flutter in it, so I can test it on the laptop.

- [x] Gray code patterns for x and y, each with its inverse, plus a white and a black frame
- [x] Finest stripe is 4 px, since a blurry projector can't show 1 px stripes
- [x] Decoder that compares each pattern with its inverse per pixel
- [x] Mask from the white and black frames, so dark or shadowed pixels get thrown out
- [x] Camera to projector map, and the reverse with small holes filled
- [x] Quality report with a plain reason when a scan fails
- [x] Save and load the map as a file
- [x] Simulator with a known answer: tilted wall, lens distortion, a box, blur, noise, room light
- [x] Tests

Demo: `dart run example/simulated_scan.dart`. In the simulated scene a tap lands about 0.3 px from the right spot.

Still open: the thresholds are only tuned on the simulator. Decode time at full camera resolution on a phone hasn't been measured. Both get done in step 2.

## Step 2 - Scan app

The real app running a full scan on the phone. Tap a spot in the camera view and it lights up on the object. First demo worth filming.

The app shell already runs on the laptop (`app/`, `flutter run -d linux`) with the simulator standing in for the camera and projector. What's left here is the phone side: real camera, external display, real timing.

- [x] Flutter app with two parts: the phone UI and the projector output (on the laptop for now, with the simulator)
- [ ] Message channel between the two (they don't share memory)
- [ ] Scan wizard: phone on a stand, frame the scene, check brightness, start
- [x] Scan loop: show a pattern, wait for it to settle, capture, next
- [ ] Pick exposure automatically from the white frame before starting
- [x] Run the calib_core decoder on the frames and show the quality report
- [ ] Clear messages when a scan fails: room too bright, camera overexposed, projector out of view
- [x] Tap to light: tap in the camera view, a dot shows up at that spot (simulator)
- [ ] Check pass: project a dot grid through the map and measure how far off it lands
- [ ] Record 2 or 3 real capture sets and add them to the calib_core tests
- [ ] Tune the thresholds on real frames
- [ ] Measure decode time on the phone

Demo: tap the corner of a box in the camera view and a dot lands on that corner in the room.

Needs: steps 0 and 1.

## Step 3 - Scene and renderer

The data model plus a real renderer, so shapes I draw on the phone show up on the object with a colour or outline.

The scene core is done in `packages/scene_core`: scene graph, 13 typed operations, undo, JSON save and load, and the shared schema in `schema/scene.schema.json`. All 37 tests pass.

- [x] Scene graph: surfaces as polygons in projector space, content per surface, pointer to the calibration file
- [x] Typed operations for every change (add, move corner, set content, rename, delete and so on)
- [x] Undo and redo on top of the operation log
- [x] Save and load a scene as one JSON file, with a schema the backend can use too
- [x] Run the scene_core tests
- [ ] Draw a polygon by tapping points in the camera view, mapped into projector space
- [ ] Renderer in the output window: solid fills, outlines, images, soft edges
- [ ] Drag corner handles to fine-tune a surface, projection updating live
- [ ] Steady frame rate on the projector, shown on screen

Demo: outline two faces of a box by hand, give each a different colour, nudge a corner, undo it.

Needs: step 2 for the renderer and drawing. The scene core needed nothing.

## Step 4 - Cloud service and auto surfaces

Small backend that finds the surfaces so nobody has to draw polygons. The backend half can start any time after step 1.

- [ ] FastAPI service with one job endpoint: image in, results out, nothing stored
- [ ] Segmentation behind an interface so I can swap models later
- [ ] Depth estimation behind the same kind of interface
- [ ] Fake versions of both that return canned results, so the app can be tested offline
- [ ] API keys and model settings in `.env`, never in code
- [ ] App side: take one photo under flat white projector light and send it
- [x] Map the returned masks from camera space into projector space using the calibration (`packages/mapping_core`)
- [x] Clean up each mask into a surface: simplify the outline, drop tiny bits
- [x] Run the mapping_core tests
- [ ] Use depth to split a mask into flat faces where it bends
- [ ] Merge, split, rename and delete surfaces in the phone UI

Demo: scan two boxes and a wall, each face shows up as its own named surface and lights up when I tap it.

Needs: step 2 for the app half. Check model licences and costs before picking anything.

## Step 5 - Effect library

Effects are small programs that read each surface's shape, depth and photo, so one effect looks made for every surface. This is where it starts feeling like a product and not a tech demo.

- [ ] Effect format: a shader plus a short list of settings (colour, speed, intensity)
- [ ] Same inputs for every effect: mask, outline, depth, the surface photo, time, sound level
- [ ] Outline effects: neon trace, edges drawing themselves in
- [ ] Fill effects: colour flood, a sweep that follows depth
- [ ] Texture effects: the surface's own photo rippling or flowing
- [ ] One particle effect that bounces off the real edges
- [ ] Sound reactivity from the phone mic, usable by any effect
- [ ] Effect picker with live preview on the projector and a few sliders
- [ ] Themes: one tap assigns effects to all surfaces by role (big planes, edges, small objects)
- [ ] 3 or 4 themes for whoever the first user ends up being

Demo: after a scan, one tap on a theme and the whole scene comes alive. Changing one surface's effect takes two taps.

Needs: steps 3 and 4. I have to decide the first user (home, creators or small venues) before making themes.

## Step 6 - AI generation

Type a prompt, get a texture shaped to a surface, and play it through the effects from step 5. Still images first, they're way cheaper than video.

- [ ] Generation endpoint in the backend, behind an interface like the others
- [ ] Send the surface outline and depth with the prompt so the image follows the real edges
- [ ] Prompt box per surface and one for the whole scene
- [ ] Cache results on the phone so each texture is paid for once
- [ ] Mix generated textures with effects: depth parallax, sweeps, sound pulse
- [ ] Usage limits and a credit counter, since every generation costs money
- [ ] Short looping animation, but only if stills work well

Demo: type "brick wall cracking open with lava" for one surface and it lines up with the real edges.

Needs: step 5. Pick a model or paid API and a budget before starting.

## Step 7 - Release polish

Make it something a stranger can install and use without me there. Mostly small stuff, but it decides whether anyone comes back.

- [ ] First-run guide: how to connect, where to put the phone, how dark the room needs to be
- [ ] Scan tips based on the quality report ("dim the lights", "move the phone back")
- [ ] Save, name and reopen scenes
- [ ] One-tap re-align: quick rescan that keeps the design when the projector got bumped
- [ ] Record the result with the phone camera and share it
- [ ] Show mode: hide the UI and play a list of looks in order
- [ ] Test on at least 3 phones and 2 projectors, and keep a list of what works
- [ ] Privacy note for camera images sent to the cloud, plus crash reporting
- [ ] Store listing, icon, short demo video

Demo: someone who's never seen the app goes from install to a recorded video without asking me anything.

Needs: step 5. Step 6 is optional for the first release.

## Step 8 - Later

Big features that aren't needed for the core idea. In this order once the release works:

- [ ] **AI assistant.** Chat panel where the model can only change the scene through the scene_core operations, so every AI edit can be undone. It can look at a camera snapshot to understand things like "the stuff on the left".
- [ ] **Real depth from the scan.** Estimate the projector's lens and position from the scan and triangulate real depth. Opens up 3D effects like virtual lights and proper shadows.
- [ ] **Live tracking.** Notice when the projector shifts and fix it in the background, then follow slow-moving objects. Measure and show the delay. Fast movement isn't realistic on this hardware.
- [ ] **Walk-around 3D scan.** Optional advanced mode for full 3D scenes.
- [ ] **iOS.** Only the device layer needs rewriting: camera, second display, mic.

Needs: step 7.
