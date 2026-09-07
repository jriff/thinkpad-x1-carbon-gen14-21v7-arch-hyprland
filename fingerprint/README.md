# Fingerprint

Synaptics `06cb:019f`, driven by `fprintd`/`libfprint`. The sensor is under the
power button. It works out of the box for `fprintd-verify` and needs help
everywhere else.

Nothing here is specific to the Gen 14 — it applies to any ThinkPad with a
Synaptics reader. The USB id is read at runtime, not hardcoded.

| File | Installs to | For |
|---|---|---|
| `fingerprint-pam` | `/usr/local/bin/` | wires `pam_fprintd` into `sudo`; `install.sh` also runs it |
| `pam.d-polkit-1` | `/etc/pam.d/polkit-1` | the same for polkit prompts |
| `faillock.conf` | `/etc/security/` | stops fingerprint unlocks locking you out |
| `25-fprintd-stabilize` | `/usr/lib/systemd/system-sleep/` | resets the reader on resume |

## Enrol, then check

```sh
fprintd-enroll
fprintd-verify                 # the sensor and the enrolment, without PAM
sudo -k && sudo true           # PAM wiring
pkexec true                    # polkit wiring
```

`fprintd-verify` failing is a hardware or enrolment problem. `fprintd-verify`
passing while `sudo` asks for a password is a PAM problem.

`/etc/pam.d/sudo` is package-owned and has no drop-in directory, thus
`fingerprint-pam` edits it in place. It is idempotent and safe to re-run, and a
`sudo` upgrade will leave a `.pacnew` beside it — merge it and run the script
again. `polkit-1` is different: `/etc/pam.d/polkit-1` overrides the vendor file
in `/usr/lib/pam.d`, thus that one is a whole-file override with no `.pacnew`.

**`lid/` must be installed first.** Both PAM stacks call
`/usr/local/bin/hw-laptop-closed` by absolute path — see
[`../lid/README.md`](../lid/README.md) for why the gate is there.

## Upstream bugs you will meet

### The reader is dead after a resume — `hyprlock#531`, `#577`

Suspend with the screen locked and the reader armed, and the reader is dead for
the rest of that lock. The password still works, thus it reads as flakiness
rather than as a bug. `#531` is open; `#577` is the noisy variant of the same
defect, closed by PR #586, which did not fix this path.

```cpp
uponSignal("PrepareForSleep").onInterface(LOGIN_MANAGER).call([this](bool start) {
    m_sDBUSState.sleeping = start;
    if (!m_sDBUSState.sleeping && !m_sDBUSState.verifying)
        startVerify();
});
```

hyprlock does try to re-arm on resume, but guards it on `!verifying`, and
`verifying` is cleared only in `stopVerify()`, which runs when a scan produces a
status. Suspend with the reader armed and no scan pending, and nothing clears
it: the guard is false on resume and `startVerify()` never runs — no warning, no
error. hyprlock has no `NameOwnerChanged` handling either, thus it never
notices fprintd restarting underneath it.

`25-fprintd-stabilize` is part of this picture from both sides. It resets the
USB device and restarts fprintd on resume, which is right for a lock screen that
starts *after* a resume, and it is the fix usually recommended for a stale
device handle. It also desynchronises a lock screen that held a claim *across*
the resume. Both halves are needed; they need sequencing, not removing.

**The only reliable repair is to replace the lock client.** No IPC makes a
running hyprlock re-arm, and its stale `verifying` cannot be reached from
outside. A fresh hyprlock claims the device and calls `startVerify()` itself.
Two things make that safe, both verified here:

- **Killing the lock client does not unlock the session.** The compositor holds
  the `ext-session-lock`; `misc:allow_session_lock_restore` lets a replacement
  attach.
- **Swap while the outputs are still off.** Replacing the client on a lit screen
  makes Hyprland paint its "lock screen has crashed, open a TTY and restart it"
  frame on every wake — alarming and false. **Raising
  `misc:lockdead_screen_delay` does not help.** In `SessionLockManager.cpp`,
  `shallConsiderLockMissing()` returns `true` immediately when `m_sessionLock` is
  null, and killing the client nulls it through the `destroyed` listener; the
  delay only gates a lock whose client is slow to draw. Measured 426 ms of
  exposure on a real resume against a 1000 ms delay that never applied.
  `onNewSessionLock()` sends `locked` straight away when no outputs are active,
  thus swapping in the dark is supported. Restore the display from a trap, so no
  early return can leave the screen black.

**Fixed when:** suspend with the screen locked, resume, and the reader still
unlocks, with a second `fprint: started verifying` after
`PrepareForSleep (start: false)` in hyprlock's log.

### Two fingerprint unlocks refuse your password — `hyprlock#258`

hyprlock races PAM against fprintd. When the finger wins, the password
conversation is torn down: `pam_faillock` records a failure, and the success
never reaches PAM, thus `authsucc` never clears it. With the stock `deny=3`, two
fingerprint unlocks in fifteen minutes refuse password authentication for ten —
`sudo`, login and the lock screen alike.

`faillock.conf` sets `deny=10 unlock_time=120`. It treats the symptom; there is
no way to make the race not count.

**Fixed when:** `faillock --user "$USER"` stays empty across a lock, fingerprint
unlock, lock cycle.

### The reader stays claimed until reboot — `hyprlock#768`

Open since 2025-05-08. The release fails, and every later claim fails with it:

```
fprint: could not release device, [org.freedesktop.DBus.Error.Timeout] Connection timed out
fprint: could not claim device, [net.reactivated.Fprint.Error.Internal]
        Open failed with error: Device 06cb:00fc is already open
```

hyprlock hangs instead of exiting, and that process holds the reader. Every
later lock request then does nothing — **the screen goes dark over a live
session**, which is worse than it sounds. Clear the corpse before starting a new
lock (`pkill -x hyprlock`).

**Fixed when:** lock, unlock by fingerprint, lock again, and the second lock
claims the device. **Not** `pgrep -x hyprlock` returning nothing: that test
passes on 0.9.6 while the issue is open, because it tests the hang and not the
claim.

### The power button unlocks the lock it just started — `hyprlock#538`, `#543`

The power button *is* the reader, and locking with it needs a hold of about
1.5 s. A finger is on the sensor when the lock starts; hyprlock begins
verifying at once and unlocks before the lock surface is up. There is no delay
option and no prompt-first mode, thus the wait has to live in whatever invokes
the lock.

## Reading the log

Start hyprlock with its output redirected to a file. The first fingerprint lines
tell the failures apart:

| Log ends at | Meaning |
|---|---|
| no `fprint: using device path` | `init()` stopped before `Manager.GetDefaultDevice` |
| `claimed device`, then quiet | armed and never re-armed — the suspend bug above |
| `could not claim device` | a wedged corpse — `#768` |

The first row is a failure seen once here, 2026-09-04, with **no suspend
involved** and nothing in the journal for the hour around it, and not again in
the 22 locks logged since. Ruled out at the time: the sensor, the driver and the
enrolment (`fprintd-verify` matched during the failing lock), polkit and VT
state (a `Claim` succeeded later in the same lock), and a `#768` corpse (none
was running). No upstream issue matches it — `#531` and `#577` are
suspend-triggered and belong above. Recorded here so the next person to see it
has a starting point.
