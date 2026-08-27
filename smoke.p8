function add_smoke(pos,sz,col)
	add(smokes,{
			pos=v_copy(pos),
			rad=sz,
			col=col
		})
end

function update_smokes()
 for idx=#smokes,1,-1 do
		local smoke=smokes[idx]
		smoke.rad*=0.8
		if smoke.rad<0.5 then
		 swap_del(smokes,idx)
		end
	end
end

function draw_smokes(smokes)
	for smoke in all(smokes) do
		circfill(
			smoke.pos.x,smoke.pos.y,
			smoke.rad,smoke.col
		)
	end
end
