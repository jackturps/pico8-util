# PICO-8 Utility Library
This is a suite of utilities that I use in my PICO-8 projects. Utilities can be included with `#include <utility>.p8`. If a utility is included all of its dependencies must be included too.

### vector.p8
`vector.p8` is a 2 component vector library [created by @thacuber2a03](https://www.lexaloffle.com/bbs/?tid=50410).

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
`hcntr_print(str,y)` prints the string `str` to y position `y`, horizontally centered at `x=0`. This should support all special characters and control codes.

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
to the screen starting y position `y` and horizontally centered at `x=0`. The option `prefix` parameter is a string that will be prepended to every menu option and can be used to add outlines, etc. The currently selected menu option will be highlighted.

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

`update_anim(anims,anim_t)` executes the animation stages and should be called in `_update()`. `anims` is an array of animation stages created by `new_anim()` and `anim_t` is the current tick (you decide the unit e.g. frames, seconds, etc). Once an animation stage completes `update_anims()` will remove it from `anims`.

depends on `swap_del.p8` and `remap.p8`.

### leaderboard.p8
`leaderboard.p8` implements an online leaderboard system that built on top of the itch.io OAuth system. It depends on some extra infrastructure which is currently under construction, but will be added to this repo soon.
