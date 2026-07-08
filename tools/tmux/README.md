# tmux

## Description
Management of multiple windows and split panes.
If you are in the CLI often, you want this.

## Commands
> tmux
Opens tmux.

### Commands inside tmux
Those commands are based on my personal binding in the tmux.conf.

`<Prefix>` = CTRL+Y

| Key             | Action                  |
|-----------------|-------------------------|
| `<Prefix> ?`    | Show all keybindings    |
| `<Prefix> c`    | Create new window       |
| `<Prefix> 1-9`  | Switch to window by index |
| `<Prefix> v`    | Split pane vertically   |
| `<Prefix> s`    | Split pane horizontally |
| `<Prefix> h`    | Move to pane left       |
| `<Prefix> j`    | Move to pane down       |
| `<Prefix> k`    | Move to pane up         |
| `<Prefix> l`    | Move to pane right      |
| `<Prefix> q`    | Close current pane      |

## Config
Config lives at `$HOME/.tmux.conf`.
See example config in this folder.
