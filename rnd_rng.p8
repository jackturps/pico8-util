function rnd_rng(a,b)
	if a>b then a,b=b,a end
	return a+rnd(b-a)
end
