long_name = "Automatic Transmission"
short_name = "automatic_transmission"
for_module = "tome"
version = {1,7,6}
addon_version = {1,1,1}
weight = 100
author = { "Gleesus", "admin@gleesus.net" }
homepage = "https://github.com/MrAwesome/tome-automatic-transmission"
description = [[
Greatly improved auto-use, giving you fine-grained control over when talents are used.

''(New players should be cautious about using this addon, as it can encourage bad habits that will get you killed when you graduate to playing Insane. My suggestion is to get your first win on Normal Adventure before trying this out, or just use it to auto-restart your sustains when safe.)''

Features:
* Auto-use for all talents, even ones with 0 cooldown (like Shoot!)
* Smarter sustain re-enables
* Precise range and HP thresholds
* Support for ranges over 10
* Rest will wait for cooldown on auto-use talents too (in any case where it wouldn't cause a loop)
* Talent priority list you can edit live

Per-talent rules (right-click a talent to configure):
* Trigger: auto each turn or only on left-click
* Enemies: require hostiles, forbid (safe only), or ignore
* HP: fire when health is above/below a threshold
* Debuff: require specific detrimental effect type (physical/mental/magical/any)
* Elite filter: skip when any visible enemy is elite+
* Range: talent_max, not_adjacent, two_tiles, or melee
* Distance band: custom min/max to nearest enemy
* Resting: only while resting or only while not resting
* Sustained: turn on when safe or off when enemies appear ("when safe" means "when out of combat", not "no enemies visible")

Default hotkeys:
* Toggle auto-accept-target ALT+F1
* Toggle auto-use on/off CTRL+P (or ALT+SHIFT+P for a separate additional disable)
* Change auto-use-custom-priority ALT+SHIFT+O
* Toggle auto-use-custom-priority ALT+SHIFT+X

Adds game options:
* "No auto-use during speed talents" - enabled by default, prevents auto-use during movement infusions, Lightning Speed, Step Up, Escape, etc.
* "Skip auto-use when EQ fail chance >= threshold" - threshold from 0-100%, defaults to 0% (skip whenever any failure chance exists).
* "Skip auto-use when debuff fail chance >= threshold" - threshold from 0-100%, defaults to 0% (skip whenever any applicable debuff failure chance exists).

Based originally on this very sweet addon:
https://te4.org/games/addons/tome/auto_use_tweaks

NOTE: I am a software engineer, but as an experiment this was heavily vibecoded, so do not be surprised if your character turns into a pumpkin
NOTE 2: the author has now beaten Insane/RL twice with this addon enabled, so maybe the robots are good at coding now
]]
tags = {'auto-use', 'tweaks', 'auto', 'talent', 'use', 'custom'}
overload = true
superload = true
hooks = true
data = true
