pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- vector.p8 v2.3.1
-- by @thacuber2a03
-- https://www.lexaloffle.com/bbs/?tid=50410
-- licensed cc4-by-nc-sa (not cc0
-- like the rest of this repo).
-- modified from the original.

-- v2.3.1
-- made v_rot and v_rotby
-- more concise
--
-- (there probably is a
-- performance benefit to that,
-- but i'm not sure and i have
-- not measured it)

function vector(x,y) return {x=x or 0,y=y or 0} end

function v_eq(a,b) return a.x==b.x and a.y==b.y end
function v_polar(a,l) return vector(l*cos(a),l*sin(a)) end
function v_rnd()      return v_polar(rnd(),1)          end
function v_copy(v)    return vector(v.x,v.y) end
function v_unpack(v)  return v.x, v.y end
function v_tostr(v)   return "["..v.x..", "..v.y.."]" end

function v_add(a,b)   return vector(a.x+b.x, a.y+b.y) end
function v_sub(a,b)   return v_add(a, v_neg(b)) end
function v_scale(v,n) return vector(v.x*n, v.y*n) end
v_mul=v_scale
function v_div(v,n)   return v_scale(v, 1/n) end
function v_neg(v)     return v_scale(v, -1) end

function v_dot(a,b)    return a.x*b.x+a.y*b.y end
function v_magsq(v)    return v_dot(v,v) end
function v_mag(v)      return sqrt(v_magsq(v)) end
function v_distsq(a,b) return v_magsq(v_sub(b,a)) end
function v_dist(a,b)   return sqrt(v_distsq(a,b)) end
function v_norm(v)     return v_div(v,v_mag(v)) end
function v_perp(v)     return vector(v.y, -v.x) end
function v_dir(a,b)    return v_norm(v_sub(b,a)) end
function v_cross(a,b)  return a.x*b.y-a.y*b.x end

function v_proj(a,b)
	return v_scale(a, v_dot(a,b)/v_magsq(a))
end

function v_angle(v)   return atan2(v.x,v.y)        end
function v_rot(v,a)   return v_polar(a, v_mag(v))  end
function v_rotby(v,a) return v_rot(v,v_angle(v)+a) end

function v_lerp(a,b,t) return v_add(a,v_mul(v_sub(b,a),t)) end
function v_flr(v) return vector(flr(v.x),flr(v.y)) end

v_right = vector( 1, 0)
v_left  = vector(-1, 0)
v_down  = vector( 0, 1)
v_up    = vector( 0,-1)
