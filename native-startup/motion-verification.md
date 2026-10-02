# Motion verification (2026-10-01)

Installed wallpaper bridge revision 23 / motion revision 5.

- Right file pane: 300ms translateX(100%) to 0, easeOutCubic. Actual startup.mp4 open incremented previewIn once.
- Close: 190ms reverse slide using an inert, aria-hidden frozen snapshot. Actual close produced an animation with translateX(0) to 100%; snapshot had zero video elements and was removed afterward. No click delay, duplicate media playback, or intercepted application state.
- Composer: 320ms translateY(22px) to 0, cubic-bezier(.215,.61,.355,1). Switching chats incremented once and exposed this actual animation timing. Twelve successive composer child mutations did not increase the count.
- Reduced motion: browser media emulation during an actual chat switch produced zero composer animations and zero ghosts; restored system media preferences afterward.
- Preview retained opacity 1 / filter none for video, blur(8px) saturate(1.3) behind it. Existing media playback verified in the preceding glass change.
- Real mouse/keyboard interaction verified for 添加文件等内容 and 更改权限: 160ms entry, 110ms inert exit snapshot, clickable hit regions, ArrowDown navigation, Escape closure, focus restored to 随心输入 or 更改权限, no residual popup. Both paths tested again with reduced motion: zero animations/ghosts. See test-menu-motion.mjs and menu-motion-results.json. No menu action or permission setting was selected.
- Signed installed app verified with codesign --verify --deep --strict. Temporary test video tab closed; original chat restored.

Limitations: pane geometry changes still use the app's layout behavior; the exit layer is visual only. System file pickers and other OS-native menus are outside this web skin and retain their original effects. Generic dialogs were not opened just for testing; no blanket DOM animation was added. Performance uses transform/opacity animations, one batched mutation callback per frame, ResizeObserver for preview bounds, no polling timer; no dedicated GPU/frame-time benchmark was run.


## Slower timing revision
Bridge 25 / motion 7: preview enters in 1200ms, exits in 800ms; composer rises 42px over 1100ms with easeOutCubic; menus enter in 650ms over 14px and exit in 450ms. Preview/menu easing now accelerates gradually before settling (cubic-bezier(.32,0,.2,1)), avoiding the previous fast initial jump. The interaction regression script uses the new timing.

## 2026-10-02: slower immersion revision
Bridge 27 / motion 8. Preview entry 2200ms / exit 1400ms; composer entry 2000ms; menu entry 1100ms / exit 800ms. Shared cubic-bezier(.42,0,.25,1) removes the composer's fast initial jump. Glass settings remain at their existing values. Installed resource signature verified.

## Account quota reliability (2026-10-02)
Source confirmed against account/rateLimits/read: weekly Codex bucket, not project tokens. Old bridge had stopped and renderer retained 31 indefinitely. Bridge now stays alive across app/debug disconnects; reconnect retries continue. Read interval ~60–75s, EPIPE handled, stale lock PID identity checked. Renderer enhancement 5 expires data after 180s and clears to “—” on unavailable responses. Verified live transitions 13 → 12, stale → “—”, null → “—”, real account value restored; motion 8 and wallpaper 27 preserved. App signature verified. Extended overnight sleep recovery has not yet been observed.
