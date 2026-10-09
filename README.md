# wtm

Numbered git worktree slots, one menu.

```
my-app   1   fix-login-bug     2 modified   ▶ ruby
my-app   2   free
my-app   3   new-settings      1 unpushed
```

Put a branch in a slot. Work. Free it. Branches are never deleted.

```
wtm init 5   make five slots in this repo
wtm          open the menu

enter  open    ^b  branch    ^f  free    ^x  remove
```

Needs `fzf`. Opens slots in `tmux` windows.

```bash
ln -s "$PWD/bin/wtm" ~/.local/bin/wtm
```

MIT
