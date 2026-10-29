# Claude Code mods

Nine small add-ons for Claude Code. Each one changes what you see or adds a helper while you work.

## What each mod does

The list is in video order. The number is the mod's number in the video.

1. **brain-dump**: catches a long, loose prompt before it is sent, asks 2 or 3 questions on gaps or clashes, then fills the prompt box with a four-part prompt (the job, the why, the guardrails, done means).
2. **helper-desk**: a purple task bar above the prompt that fills as Claude ticks off its to-do list, plus a side pane with one live card and one progress bar per subagent.
3. **cache-clock**: counts down above the prompt until the chat's cache goes cold, says how long the cache is (as Anthropic's last reply set it), and has a Keep warm button.
4. **handoff**: when a chat gets very long, writes a handoff prompt and starts a fresh chat with it.
5. **reflect**: when you correct Claude, offers to save the fix as a lasting rule.
6. **chat-inventory**: a side pane, In this chat, listing the to-do list, connectors and calls per connector, files and skills this chat used.
7. **screen-share**: `/screen-share` hides names, emails, phone numbers and money amounts on screen while you record.
8. **replay-theater**: `/replay` steps through the file edits Claude made in the last turn, one diff at a time. This is Anthropic's sample mod from [anthropics/claude-code-playground](https://github.com/anthropics/claude-code-playground/tree/main/claude-code/mods/replay-theater), shared under the Apache 2.0 license (see its `LICENSE`). We only added `/mods` switch support.
9. **mods**: `/mods` opens a pane to turn each mod on or off. It also finds mods you installed from any other marketplace.

Tip: install mods with the steps below so they load in every chat. A mod that is only built inside one chat loads in that chat only.

## Install

You need Claude Code 2.1.287 or newer in the terminal, or 2.1.286 or newer in the desktop Code tab. Check with `claude --version`. Update with `claude update`.

Easiest way: unzip the folder, open a Claude Code chat, drop the folder in and say "Install these mods for me." Claude runs the steps below for you.

To do it by hand, unzip the folder first, then type these at the Claude Code prompt in a terminal:

1. Add the folder as a marketplace, using the path to the unzipped `benai-mods` folder:

   ```
   /plugin marketplace add ~/Downloads/benai-mods
   ```

2. Install the mods you want, one line each. The names are the ones in the list above. To install all 9, paste this block:

   ```
   /plugin install brain-dump@benai-mods
   /plugin install helper-desk@benai-mods
   /plugin install cache-clock@benai-mods
   /plugin install handoff@benai-mods
   /plugin install reflect@benai-mods
   /plugin install chat-inventory@benai-mods
   /plugin install screen-share@benai-mods
   /plugin install replay-theater@benai-mods
   /plugin install mods@benai-mods
   ```

3. In any chat that was already open, run:

   ```
   /reload-plugins
   ```

## Turning mods on or off

Type `/mods` to open the Mods pane and switch each mod on or off in every chat.

## Reflect setting

Reflect saves a rule either to `~/.claude/CLAUDE.md` (Save everywhere) or as its own note in a folder you choose (Save to vault). Set that folder as `rules_folder` when you install reflect, or later for reflect in `/config`. If it is empty, reflect asks for the folder the first time you press Save to vault.
