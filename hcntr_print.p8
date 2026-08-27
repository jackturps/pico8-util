function hcntr_print(str,y)
	--measure text width offscreen
	local w=print(str,0,0x7fff.ffff)
	local x=63.5-0.5*w
	print(str,x,y)
end
