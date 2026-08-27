function new_anim(start,fin,func)
	return {
		start=start,
		fin=fin,
		func=func
	}
end

function update_anims(anims,anim_t)
	for i=#anims,1,-1 do
		local anim=anims[i]
		if anim_t>=anim.start do
			anim.func(remap(anim.start,anim.fin,0,1,anim_t))
		end
		if anim_t>=anim.fin do
			swap_del(anims,i)
		end
	end
end
