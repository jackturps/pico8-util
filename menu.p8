function draw_menu(menu,y,prefix)
 prefix=prefix or ""
	for i=1,#menu.items do
		local txt=menu.items[i].txt
		if i==menu.idx then
			txt="> "..txt.." <"
		end
		hcntr_print(prefix..txt,y+7*i)
	end
end

function update_menu(menu)
	if btnp(❎) or btnp(🅾️) then
		menu.items[menu.idx].func()
		sfx(10)
	end
	if btnp(⬇️) then
	 menu.idx+=1
		sfx(2)
	end
	if btnp(⬆️) then
		menu.idx-=1
		sfx(2)
	end
	menu.idx=1+(menu.idx-1)%#menu.items
end
