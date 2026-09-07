# A closed lid makes every authorisation prompt hang

With the laptop docked and the lid shut, the fingerprint reader is under the
closed lid and cannot be reached. `pam_fprintd` does not know that: it waits for
a finger that cannot arrive, thus `sudo` and every polkit prompt block for about
30 seconds before falling back to the password.

`hw-laptop-closed` exits 0 when the lid is closed. The PAM stack runs it before
`pam_fprintd` and skips the fingerprint step on a 0:

```
auth [success=1 default=ignore] pam_exec.so quiet quiet_log /usr/local/bin/hw-laptop-closed
auth sufficient                 pam_fprintd.so
auth include                    system-auth
```

`success=1` skips the next line — the fingerprint — and falls through to the
password. Anything else is `ignore`, thus an open lid, or a machine with no
`/proc/acpi/button/lid`, keeps fingerprint authentication.

It reads `/proc/acpi/button/lid/*/state`, not `loginctl`: **loginctl reports
only lid events it acted on**, thus a lid closed under a policy that ignores it
does not show up there. An unreadable or absent state counts as open, which
fails towards the fingerprint working rather than towards it being skipped.

Not specific to this model, and not a workaround for a bug — `pam_fprintd` is
serialised by design. It applies to any laptop where the reader is on the
keyboard deck.

**Install `lid/` before `fingerprint/`.** `pam.d-polkit-1` calls this binary by
absolute path, thus a polkit prompt with the file missing runs `pam_exec` against
nothing.

## Verify

```sh
/usr/local/bin/hw-laptop-closed; echo $?     # 1 with the lid open
sudo -k && sudo true                         # asks for a finger, lid open
```

Then close the lid on an external display and try `pkexec true`: it should ask
for the password without a pause.

## Not covered

`pam_fprintd` is serialised by design, thus a prompt raised *while the lid is
open* asks for a finger before it will look at a password. That is upstream
behaviour and this gate does not change it — it covers the lid-closed case only.
