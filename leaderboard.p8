--pin map, see readme
lb_base=0x5f80
lb_p_req=lb_base+0
lb_p_status=lb_base+1
lb_p_arg=lb_base+2
lb_p_count=lb_base+3
lb_p_namelen=lb_base+4
lb_p_name=lb_base+5
lb_p_score=lb_base+21
lb_p_magic=lb_base+28
lb_p_ver=lb_base+29
lb_p_sort=lb_base+30

lb_magic_val=0x8b
lb_ver_val=1

--requests, lua writes
lb_rq_none=0
lb_rq_submit=1
lb_rq_fetch=2
lb_rq_row=3
lb_rq_whoami=4

lb_req_of={
	submit=lb_rq_submit,
	fetch=lb_rq_fetch,
	whoami=lb_rq_whoami,
	row=lb_rq_row,
}

--status, shell writes
lb_sv_idle=0
lb_sv_ok=2
lb_sv_err=3

function lb_init()
	lb_board={}
	lb_next={}
	lb_name=nil
	lb_msg=""
	lb_job=""
	lb_busy=false
	lb_pending={}
	lb_wait=0
	lb_row=0
	lb_rows=0

	lb_magic=peek(lb_p_magic)
	lb_ver=peek(lb_p_ver)
	--1=descending -1=ascending.
	lb_sign=sgn(1-2*peek(lb_p_sort))

	if lb_magic!=lb_magic_val then
  --not in harness
		lb_state="disabled"
		return
	end
	if lb_ver!=lb_ver_val then
		lb_state="disabled"
		lb_msg="shell v"..lb_ver..", cart v"..lb_ver_val
		return
	end

	poke(lb_p_req,lb_rq_none)
	poke(lb_p_status,lb_sv_idle)

	lb_state="loading"
	lb_whoami()
end

function lb_enqueue(job,score)
	if lb_state=="disabled" then
		return false
	end
	add(lb_pending,{job=job,score=score})
	return true
end

function lb_submit(score)
	return lb_enqueue("submit",score)
end

function lb_fetch()
	return lb_enqueue("fetch")
end

function lb_whoami()
	return lb_enqueue("whoami")
end

function lb_start(job)
	poke(lb_p_status,lb_sv_idle)
	poke(lb_p_req,lb_req_of[job])
	lb_job=job
	lb_busy=true
	lb_wait=0
end

function lb_send(p)
	if p.job=="submit" then
		poke4(lb_p_score,p.score)
		--kept so the reply can place it
		lb_sent_score=p.score
	end
	if p.job=="fetch" and lb_state=="error" then
		lb_state="loading"
	end
	lb_start(p.job)
end

function lb_ask_row()
	lb_row+=1
	poke(lb_p_arg,lb_row)
	lb_start("row")
end

function lb_read_name()
	local n=min(peek(lb_p_namelen),16)
	local s=""
	for idx=0,n-1 do
		s=s..chr(peek(lb_p_name+idx))
	end
	if s=="" then
		return nil
	end
	return s
end

--ack shell and free line
function lb_free()
	poke(lb_p_status,lb_sv_idle)
	lb_busy=false
end

--a request died. we only fall back to
--"error" if we have never had a board:
--once ready we keep showing the old one.
function lb_failed(why)
	lb_msg=why
	lb_free()
	if lb_state!="ready" then
		lb_state="error"
	end
end

function lb_update()
	if lb_state=="disabled" then
		return
	end

	if not lb_busy then
		if #lb_pending>0 then
			lb_send(deli(lb_pending,1))
		end
		return
	end

	lb_wait+=1
	if lb_wait>300 then
		poke(lb_p_req,lb_rq_none)
		lb_failed("timed out")
		return
	end

	local st=peek(lb_p_status)
	if st==lb_sv_err then
		lb_failed("request failed")
		return
	end
	if st!=lb_sv_ok then
		return
	end

	--job landed, process it
	lb_free()
	if lb_job=="whoami" then
		lb_name=lb_read_name()
	elseif lb_job=="submit" then
  --submit may pickup updated username
		lb_name=lb_read_name()
		lb_insert(lb_name,lb_sent_score)
	elseif lb_job=="fetch" then
		lb_rows=peek(lb_p_count)
  --rows arrive one by one, double buffer
		lb_next={}
		lb_row=0
		if lb_rows>0 then
			lb_ask_row()
		else
			lb_board={}
			lb_state="ready"
		end
	elseif lb_job=="row" then
		add(lb_next,{
			name=lb_read_name() or "???",
			score=peek4(lb_p_score),
		})
		if lb_row<lb_rows then
			lb_ask_row()
		else
   --done, swap double buffer
			lb_board=lb_next
			lb_state="ready"
		end
	end
end

function lb_ready()
	return lb_state=="ready"
end

function lb_insert(name,score)
	if lb_state!="ready" or not name then
		return false
	end

	local s=score*lb_sign
	local pos

	for idx=1,#lb_board do
		local row=lb_board[idx]
		if not pos and s>row.score*lb_sign then
			pos=idx
		end
		if row.name==name then
			if not pos then
				return false
			end
			deli(lb_board,idx)
			break
		end
	end

	pos=pos or #lb_board+1
	if pos>10 then
		return false
	end

	add(lb_board,{name=name,score=score},pos)
	if #lb_board>10 then
		deli(lb_board)
	end
	return true
end
