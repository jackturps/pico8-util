function remap(in_a,in_b,out_a,out_b,val)
	return lerp(out_a,out_b,(val-in_a)/(in_b-in_a))
end
