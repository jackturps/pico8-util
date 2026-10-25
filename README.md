# PICO-8 Utility Library
This is a suite of utilities that I use in my PICO-8 projects. Utilities can be included with `#include <utility>.p8`. If a utility is included all of its dependencies must be included too.

### vector.p8
`vector.p8` is a 2 component vector library adapted from [@thacuber2a03 vector cart](https://www.lexaloffle.com/bbs/?tid=50410).

### lerp.p8
`lerp(a,b,t)` returns a value that is linearly scaled between `a` and `b` by a factor of `t`.

### remap.p8
`remap(in_a,in_b,out_a,out_b,val)` returns a value in the range `out_a`-`out_b` mapped to the equivalent value `val` in the range `in_a`-`in_b`.

Depends on `lerp.p8`.

### rnd_rng.p8
`rnd_rng(a,b)` returns a random float between a and b.

### swap_del.p8
`swap_del(arr,idx)` deletes the item at index `idx` from an array. It changes the order of the array. This is safe to call while iterating the array **only if** the array is being iterated backwards. Useful for removing particles from a particle system, etc.

### hcntr_print.p8
`hcntr_print(str,y)` prints the string `str` to y position `y`, horizontally centered at `x=64`. This should support all special characters and control codes.

### menu.p8
`menu.p8` implements a selection menu system. In all cases, the `menu` parameter is a table of the following format:
```
menu={
 idx=1,
 items={
  {
   txt="menu option 1",
   func=function()
    --do menu option 1
   end
  },
  {
   txt="menu option 2",
   func=function()
    --do menu option 2
   end
  }
 }
}
```

`draw_menu(menu,y,prefix)` draws the given menu options
to the screen starting y position `y` and horizontally centered at `x=64`. The option `prefix` parameter is a string that will be prepended to every menu option and can be used to add outlines, etc. The currently selected menu option will be highlighted.

`update_menu(menu)` should be called from `_update()` and will process input for the menu. The up and down arrows navigate up and down the menu items. The X and O buttons will call the `func` of the selected menu item.

Depends on `hcntr_print.p8`.

**TODO: Generalize SFX in menu**

### smoke.p8
`smoke.p8` implements a smoke particle system. `smokes={}` must exist in global scope before these functions are called.

`add_smoke(pos,sz,col)` creates a smoke particle at position `pos` with size `sz` and colour `col`.

`update_smokes()` should be called in `_update()`. It will shrink smoke particles over time and remove them once they're too small.

`draw_smokes()` should be called in `_draw()`. It draws all smoke particles to their positions.

Depends on `vector.p8`.

### anim.p8
`anim.p8` implements an animation timeline, useful for creating scripted cutscenes or transitions.

`new_anim(start,fin,func)` creates an animation stage which starts at tick `start` and finishes at tick `fin`. `func` is a callback of type `func(t)`. `func(t)` is called on each tick between `start` and `fin`. `t` is a value that starts and `0` on tick `start` and scales linearly up to `1` on tick `fin`.

`update_anims(anims,anim_t)` executes the animation stages and should be called in `_update()`. `anims` is an array of animation stages created by `new_anim()` and `anim_t` is the current tick (you decide the unit e.g. frames, seconds, etc). Once an animation stage completes `update_anims()` will remove it from `anims`.

depends on `swap_del.p8` and `remap.p8`.

### leaderboard.p8

#### Leaderboard Infrastructure

`leaderboard.p8` implements an online leaderboard system. itch.io OAuth is used  to authenticate and provide names for the leaderboard (this means the leaderboard will only function in itch.io web exports). By default a cloudflare worker is used as a backend to serve the leaderboard.

The leaderboard setup scripts has a handful of dependencies. Before running `./leaderboard/setup.sh` for the first time, run the appropriate setup script for your OS:
```
./leaderboard/deps/<OS>
```

The leaderboard infrastructure must be configured before the API can be used. This can be done by running:
```
./leaderboard/setup.sh --game-id <game-id>
```
where `game-id` is an arbitrary ID for your game. 

On windows this requires a bash runtime, such as git-bash (should be installed by the deps script):
```
& "C:\Program Files\Git\bin\bash.exe" ./leaderboard/setup.sh --game-id <game-id>
```

The setup script will walk you through the entire deployment of the leaderboard infrstructure. This includes:
* Authorizing the wrangler CLI with a cloudflare account.
* Creating a cloudflare worker.
* Deploying the leaderboard DB to the cloudflare worker.
* Deploying the leaderboard backend API to the cloudflare worker.
* Creating an itch OAuth client.
* Assigning the cloudflare URL to the itch client.

The setup script will automatically create and install a custom PICO-8 export template that includes the javascript harness for running the leaderboard. Leaderboards will only work if the PICO-8 web exports use this template. This can be done by running `export index.html -p <game-id>` when exporting the game from PICO-8. The output (`index.html` and `index.js`) can then be zipped and uploaded to itch as usual.

#### Leaderboard PICO-8 API

`lb_init()` should be called once at the start of the program to initialise the leaderboard system.

`lb_fetch()` should be called once at the start of the program to fetch the leaderbaord, and then again anytime the leaderboard needs to be refreshed (e.g. to get up to date scores at the end of each run). `lb_ready()` will only return true once the fetch has completed asyncronously.

`lb_update()` should be called frequently to run the leaderboard poll loop.

`lb_ready()` should be called to check whether the leaderboard has been fetched.

`lb_board` is a variable that can be read once `lb_ready()` returns true. It contains the top 10 leaderboard entries in a table.
The table is in the format `{{name="example_name", score=67}, ...}`. The table is ordered from highest score to lowest.

`lb_name` is a variable that can be read once `lb_ready()` returns true. It is the player's itch user name. This can be used for
highlighting the player's scores within the leaderboard. Name will be `nil` if unset (player is unauthorized, fetch hasn't completed, etc).

`lb_submit(score)` should be called to post a score for the current user. The new score will overwrite the existing score if the new score is greater. For games with ascending leaderboards (e.g. time attack games) the scores can be negated.

`lb_msg` is a variable that stores an error message in the case of an error.

`lb_whoami()` can be called to refresh the current user's itch username (this should only be necessary if they've changed their username during a play session).

An minimal example program might look like this:

```
function _init()
 lb_init()
 lb_fetch()
 score=0
end

function _update()
 lb_update()
 if lb_ready() and btnp()!=0 then
  score+=1
  lb_submit(score)
 end
end

function draw()
 if not lb_ready() then
  return
 end

 for i=1,#lb_board do
  local entry=lb_board[i]
  print(entry.name..": "..entry.score,8,i*8)
 end
end
```

## License
Everything in this repo is released into the public domain under [CC0 1.0](LICENSE), **except `vector.p8`**.

`vector.p8` is adapted from [@thacuber2a03's vector cart](https://www.lexaloffle.com/bbs/?tid=50410) and keeps its original [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) license. If you use it (or `smoke.p8`, which depends on it) you must credit the author, not use it commercially, and share any changes under the same license.
