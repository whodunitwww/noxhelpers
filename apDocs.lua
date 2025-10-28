return [[
Cerberus AutoParry Docs
==========================

Files:
  • AP_Config.json        : per-animation timings
  • AP_Config_Extra.json  : global hotkeys (parry / roll)

AP_Config.json schema:
  {
    "<animId>": {
      "name": "Readable Name",
      "startSec": 0.42,          // absolute seconds into the animation to parry
      "hold": 0.30,              // seconds to hold the parry key
      "rollOnFail": true         // if true, roll when parry conflicts inside the fail window
    }
  }

AP_Config_Extra.json schema:
  {
    "parryKey": "F",
    "rollKey":  "Q"
  }

UI Controls (in-game):
  • Enable Auto Parry            : toggles the system on/off
  • Detection Range              : only react to sources within this many studs
  • Debug Notifications          : show toast notes when scheduling/firing parries
  • Ping Compensation            : enable/disable one-way ping subtraction
  • Ping Scale (%)               : scale factor for ping (100 = use exact one-way ping)
  • Extra Bias (ms)              : manual timing offset; + = earlier, − = later
  • Roll on Parry Fail (global)  : roll when a parry would conflict (see below)
  • Parry Fail Window (s)        : time span in which overlapping parries count as a conflict

How timing works:
  • When a nearby enemy animation (by id) starts, we look up AP_Config and compute:
        t_press = startSec − currentAnimTime − oneWayPing − extraBias
    where:
      - currentAnimTime  = the track's TimePosition when detected
      - oneWayPing       = (LocalPlayer RTT * 0.5) * (PingScale / 100)  (0 if Ping Compensation off)
      - extraBias        = Extra Bias (ms) / 1000
  • If t_press ≤ ~0.005s we press immediately; otherwise we schedule the press.
  • The parry key is held for `hold` seconds, then released.

Conflict & Roll logic:
  • If two parries would land inside the Parry Fail Window, or a parry just fired and
    is still inside that window, the attempt is a conflict.
  • If Global "Roll on Parry Fail" is ON and this animation's "rollOnFail" is true,
    we press the roll key instead.

Recommended workflow:
  1) Click the button to generate AP_Config.json and AP_Config_Extra.json.
  2) Enable Debug + Ping Compensation; tune Ping Scale and Extra Bias.
  3) Add/tweak per-animation entries (startSec/hold/rollOnFail).
  4) Use "Refresh AutoParry Config" to hot-reload changes.

Notes:
  • Timings are client-seconds; ping and extra bias are applied at runtime.
  • startSec is absolute time into the enemy animation (not a percent).
  • rollOnFail is per-animation; the global Roll on Parry Fail must also be enabled.
  • Detection Range ignores far animations to avoid false triggers.
  • Keys are read from AP_Config_Extra.json at load; use letters (e.g. "F", "Q").

Troubleshooting:
  • Too early? Decrease Extra Bias (negative ms) or reduce Ping Scale.
  • Too late?  Increase Extra Bias (positive ms) or increase Ping Scale.
  • Rolling too often? Lower Parry Fail Window, or disable rollOnFail for noisy anims.
  • Nothing happens? Ensure the anim id exists in AP_Config.json and you’re in range.
]]
