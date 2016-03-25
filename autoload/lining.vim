" vim: set foldmethod=marker:
"
" Author: Adrián Pérez de Castro <aperez@igalia.com>
" License: GPLv3

if exists('g:loaded_lining_autoload')
  finish
endif
let g:loaded_lining_autoload = 1

let s:save_cpo = &cpo
set cpo&vim

" Cache type codes. {{{1
"
" A Funcref attached directly to a dictionary may have a different type code
" than an unattached function. Defining a dummy function in a Dict and using
" it to obtain the type code is the safest way that works for Vim and NeoVim.
"
let s:dummy = {}
function s:dummy.dummier()
	return ''
endfunction

let s:TYPE_FREF = type(s:dummy.dummier)
let s:TYPE_DICT = type({})
let s:TYPE_NUM  = type(0)

unlet s:dummy  " Remove the dummy dictionary 1}}}

let s:lining_items = [ 0 ]
let s:splitter_pos = 0

let s:lining_alt_items = [ 0 ]
let s:splitter_alt_pos = 0


function s:add_item(list, pos, item, hlgroup)
	let hlg = 'LiningItem'
	let fmt = {}
	if type(a:item) == s:TYPE_DICT
		let fmt = a:item
		if has_key(fmt, 'color')
			let hlg = 'Lining' . fmt.color
		endif
		if a:hlgroup != ''
			let hlg = a:hlgroup
		endif
		let fmt.hlgroup = hlg
		call insert(a:list, fmt, a:pos)
	elseif !empty(a:hlgroup) && a:hlgroup != 'LiningItem'
		call insert(a:list, { 'hlgroup': a:hlgroup, 'format': a:item }, a:pos)
	else
		call insert(a:list, a:item, a:pos)
	endif
endfunction


function lining#left(format, ...)
	let hlgroup = (a:0 > 0) ? ('Lining' . a:1) : ''
	call s:add_item(s:lining_items, s:splitter_pos, a:format, hlgroup)
	let s:splitter_pos += 1
endfunction

function lining#right(format, ...)
	let hlgroup = (a:0 > 0) ? ('Lining' . a:1) : ''
	call s:add_item(s:lining_items, s:splitter_pos + 1, a:format, hlgroup)
endfunction

function lining#altleft(format, ...)
	let hlgroup = (a:0 > 0) ? ('Lining' . a:1) : ''
	call s:add_item(s:lining_alt_items, s:splitter_alt_pos, a:format, hlgroup)
	let s:splitter_alt_pos += 1
endfunction

function lining#altright(format, ...)
	let hlgroup = (a:0 > 0) ? ('Lining' . a:1) : ''
	call s:add_item(s:lining_alt_items, s:splitter_alt_pos + 1, a:format, hlgroup)
endfunction


" Buffer name
let s:buffername_item = { 'color': 'BufName', 'autoformat': 0 }
function s:buffername_item.format(active, bufnum)
	let type = getbufvar(a:bufnum, '&buftype')
	let ft   = getbufvar(a:bufnum, '&filetype')
	let path = bufname(a:bufnum)
	let name = '%t'

	if type ==# 'help'
		let path = 'help/'
	elseif ft ==# 'netrw'
		let path = getbufvar(a:bufnum, 'netrw_curdir')
		let name = fnamemodify(path, ':t')
		let path = fnamemodify(path, ':p:~:.:h') . '/'
	else
		let path = expand(path)
		if !empty(path)
			let path = fnamemodify(path, ':p:~:.:h')
			if path == '.'
				let path = ''
			else
				let path .= '/'
			endif
		endif
	endif

	if a:active
		return printf('%%#LiningBufPath#%%< %s%%#LiningBufName#%%t ', path)
	else
		return printf('%%< %s%%t ', path)
	endif
endfunction
call lining#left(s:buffername_item)
call lining#altleft(s:buffername_item)

" File flags
let s:flags_item = {}
function s:flags_item.format(active, bufnum)
	let flags = ''
	if getbufvar(a:bufnum, '&readonly')
		let flags .= '~'
	endif
	if getbufvar(a:bufnum, '&modifiable')
		if getbufvar(a:bufnum, '&modified')
			let flags .= '+'
		endif
	else
		let flags .= '-'
	endif
	return flags
endfunction
call lining#left(s:flags_item)

" Paste status
let s:paste_item = {}
function s:paste_item.format(active, bufnum)
	if a:active && getbufvar(a:bufnum, '&paste')
		return 'PASTE'
	else
		return ''
	endif
endfunction
call lining#left(s:paste_item, 'Warn')

" Line/Column
call lining#right('%4l:%-3c', 'LnCol')
call lining#altright(' %P ', 'LnCol')

" Git branch/hunk information
if exists('*GitGutterGetHunkSummary')
	function s:git_get_hunks()
		let [hadd, hmod, hdel] = GitGutterGetHunkSummary()
		let hunks = ''
		if hmod > 0
			let hunks = printf(' ~%i', hmod)
		endif
		if hadd > 0
			let hunks = printf('%s +%i', hunks, hadd)
		endif
		if hdel > 0
			let hunks = printf('%s -%i', hunks, hdel)
		endif
		return hunks
	endfunction
else
	function s:git_get_hunks()
		return ''
	endfunction
endif

if exists('*fugitive#detect') && exists('*fugitive#detect')
	let s:git_item = {}
	function s:git_item.format(active, bufnum)
		let head = fugitive#head()
		if empty(head) && !exists('b:git_dir')
			call fugitive#detect(fnamemodify(bufname(a:bufnum), ':p:h'))
			let head = fugitive#head()
		endif
		if empty(head)
			return ''
		endif
		return a:active ? (head . s:git_get_hunks()) : head
	endfunction
	call lining#right(s:git_item, 'VcsInfo')
endif

" File type
call lining#right("%{empty(&filetype) ? 'none' : &filetype}")


function lining#status(winnum)
	let bufnum = winbufnr(a:winnum)
	let type   = getbufvar(bufnum, '&buftype')
	let ft     = getbufvar(bufnum, '&filetype')

	let item_list = s:lining_items
	if type ==# 'help' || ft ==# 'netrw'
		let item_list = s:lining_alt_items
	endif

	let last_hlgroup_id = -1
	let start_hlgroup = 1
	let active = a:winnum == winnr()
	let fmt  = ''

	for item in item_list
		let autoformat = 1
		let hlgroup = 'LiningItem'
		let text = ''

		if type(item) == s:TYPE_NUM && item == 0
			let autoformat = 0
			let hlgroup = active ? 'StatusLine' : 'StatusLineNC'
			let text = active ? '%#StatusLine#%=' : '%#StatusLineNC#%='
		elseif type(item) == s:TYPE_DICT
			let hlgroup = item.hlgroup
			let autoformat = get(item, 'autoformat', 1)
			let text = (type(item.format) == s:TYPE_FREF)
						\ ? item.format(active, bufnum) : item.format
		else
			let text = item
		endif
		unlet item

		if empty(text)
			continue
		endif

		let hlgroup_id = synIDtrans(hlID(hlgroup))
		if hlgroup_id == last_hlgroup_id
			" Next item has the same colors
			if start_hlgroup
				let fmt .= '·'
			endif
			let start_hlgroup = 0
		else
			" Next item has different colors.
			if autoformat && active
				let fmt .= '%#'
				let fmt .= hlgroup
				let fmt .= '#'
			endif
			let last_hlgroup_id = hlgroup_id
			let start_hlgroup = 1
		endif

		if autoformat
			let fmt .= ' '
			let fmt .= text
			let fmt .= ' '
		else
			let fmt .= text
		endif
	endfor

	return fmt
endfunction


function lining#refresh()
	if pumvisible()
		return
	endif
	for nr in range(1, winnr('$'))
		call setwinvar(nr, '&statusline', '%!lining#status(' . nr . ')')
	endfor
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo
