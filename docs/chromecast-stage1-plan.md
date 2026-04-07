# Chromecast Stage 1 Plan

## Goal

Prepare Listen SDR for Chromecast as an optional second playback path, without replacing current local playback and without blocking current release work.

## Stage 1 scope (this cycle)

1. Define a stable "cast handoff" contract per backend:
- FM-DX: stream URL format and required headers.
- KiwiSDR: constraints for websocket/audio path and whether direct cast is possible.
- OpenWebRX: stream URL and codec/container expectations.

2. Add technical diagnostics fields for future cast support:
- active backend
- active endpoint
- tuned frequency/mode
- audio sample rate and channel mode
- candidate cast stream source (if available)

3. Add safety requirements before SDK integration:
- no regression in VoiceOver/TalkBack flow
- no regression in background/local audio behavior
- no interruption of existing reconnect logic

## Out of scope in Stage 1

- No Google Cast SDK integration yet.
- No new user-facing cast button yet.
- No TestFlight/Play release notes promising cast playback in this stage.

## Stage 1 done criteria

- Backend-by-backend cast feasibility matrix is documented.
- Diagnostics export contains fields needed to debug cast handoff.
- Follow-up Stage 2 task list is ready (SDK wiring, UI, accessibility announcements, reconnect behavior).

## Stage 2 preview (next)

1. Integrate Google Cast SDK.
2. Add user-facing Cast control in receiver screen.
3. Add accessibility announcements for connect/disconnect and route changes.
4. Add backend-specific fallback messaging when cast is unavailable.
