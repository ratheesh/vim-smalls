let s:is_visual       = smalls#util#import('is_visual')
let s:SCREEN = has("gui_running") ? 'gui' : 'cui'

" Util:
function! s:msg(msg) "{{{1
  if !empty(a:msg)
    echohl Type
    echon 'smalls: '
    echohl Normal
  endif
  echon a:msg
endfunction

function! s:options_set(options) "{{{1
  let R = {}
  let curbuf = bufnr('')
  for [var, val] in items(a:options)
    let R[var] = getbufvar(curbuf, var)
    call setbufvar(curbuf, var, val)
    unlet var val
  endfor
  return R
endfunction

function! s:options_restore(options) "{{{1
  for [var, val] in items(a:options)
    call setbufvar(bufnr(''), var, val)
    unlet var val
  endfor
endfunction

function! s:highlight_preserve(hlname) "{{{1
  redir => HL_SAVE
  execute 'silent! highlight ' . a:hlname
  redir END
  return 'highlight ' . a:hlname . ' ' .
        \  substitute(matchstr(HL_SAVE, 'xxx \zs.*'), "\n", ' ', 'g')
endfunction
"}}}

let s:vim_options = {
      \ '&scrolloff':  0,
      \ '&modified':   0,
      \ '&cursorline': 0,
      \ '&modifiable': 1,
      \ '&readonly':   0,
      \ '&spell':      0,
      \ }

" Main:
let s:smalls = {}
function! s:smalls._config() "{{{1
  let R = {
        \ 'adjust':                          '',
        \ 'wildchar':                        g:smalls_wildchar,
        \ 'shade':                           g:smalls_shade,
        \ 'helplang':                        g:smalls_helplang,
        \ 'jump_keys':                       g:smalls_jump_keys,
        \ 'blink_on_notfound':               g:smalls_blink_on_notfound,
        \ 'blink_on_auto_set':               g:smalls_blink_on_auto_set,
        \ 'current_mode':                    g:smalls_current_mode,
        \ 'auto_jump':                       g:smalls_auto_jump,
        \ 'auto_jump_timeout':               g:smalls_auto_jump_timeout,
        \ 'auto_jump_min_input_length':      g:smalls_auto_jump_min_input_length,
        \ 'auto_excursion':                  g:smalls_auto_excursion,
        \ 'auto_excursion_min_input_length': g:smalls_auto_excursion_min_input_length,
        \ 'auto_set':                        g:smalls_auto_set,
        \ 'auto_set_min_input_length':       g:smalls_auto_set_min_input_length,
        \ 'exit_at_notfound':                g:smalls_exit_at_notfound,
        \ }
  return R
endfunction

function! s:smalls.start(mode, config)  "{{{1
  try
    let options_saved = s:options_set(s:vim_options)
    let self.conf     = extend(self._config(), a:config, 'force')
    call self.init(a:mode ==# 'v' ? visualmode() : a:mode)
    call self.cursor_hide()
    call self.loop()

  catch /^SUCCESS/
  catch
    let self.exception = v:exception
  finally
    call self.hl.clear()
    call s:options_restore(options_saved)
    call self.cursor_restore()
    call self.finish()
  endtry
endfunction

function! s:smalls.cursor_hide() "{{{1
  if s:SCREEN is 'gui'
    let self.__hl_cursor_cmd = s:highlight_preserve('Cursor')
    highlight Cursor NONE
  else
    let self.__t_ve_save = &t_ve
    let &t_ve=''
  endif
endfunction

function! s:smalls.cursor_restore() "{{{1
  if s:SCREEN is 'gui'
    execute self.__hl_cursor_cmd
  else
    let &t_ve = self.__t_ve_save
  endif
endfunction

function! s:smalls.env_preserve(mode) "{{{1
  " to get precise start point in visual mode.
  let dest = []
  if s:is_visual(a:mode)
    exe "normal! gv\<Esc>"
    let dest = [ line('.'), col('.') ]
    exe "normal! gvo\<Esc>"
  endif
  let [ l, c ] = [ line('.'), col('.') ]

  return {
        \ 'mode_org': a:mode,
        \ 'mode': a:mode,
        \ 'w0': line('w0'),
        \ 'w$': line('w$'),
        \ 'l': l,
        \ 'dest': dest,
        \ 'c': c,
        \ 'p': smalls#pos#new(self, [l, c]),
        \ }
endfunction

function! s:smalls.init(mode) "{{{1
  let self.poslist         = []
  let self.operation       = {}
  let self.exception       = ''
  let self.env             = self.env_preserve(a:mode)
  let self.hl              = smalls#highlighter#new(self)
  let self.finder          = smalls#finder#new(self)
  let self.keyboard_cli    = smalls#keyboard#cli#new(self)
  let self.keyboard_exc    = smalls#keyboard#excursion#new(self)
  let self.keyboard_cur    = self.keyboard_cli
endfunction

function! s:smalls.finish() "{{{1
  call self.statusline_update('')

  let conf      = self.conf
  let exception = self.exception
  let NOT_FOUND = exception ==# 'NOT_FOUND'
  let CANCELED  = exception ==# 'CANCELED'
  let AUTO_SET  = exception ==# 'AUTO_SET'
  if AUTO_SET
    let self.exception = ''
  endif
  call s:msg(self.exception)

  if ( NOT_FOUND && conf['blink_on_notfound'])
        \ || ( AUTO_SET && conf['blink_on_auto_set'] )
    call self.hl.blink_cword(NOT_FOUND)
  endif

  if (NOT_FOUND || CANCELED) && s:is_visual(self.env.mode_org)
    normal! gv
  endif
  call self.do_operation()
  " to avoid user's input mess buffer, we consume keyinput before exit.
  while getchar(1) | call getchar() | endwhile
endfunction

function! s:smalls.do_operation() "{{{1
  if empty(self.operation)
    return
  endif
  execute 'normal!' self.operation.normal
  if self.operation.startinsert
    startinsert
  endif
endfunction

function! s:smalls.word() "{{{1
  return self.keyboard_cli.data
endfunction

function! s:smalls.loop() "{{{1
  call self.statusline_update(self.keyboard_cur.name)

  while 1
    call self.hl.refresh()
    try
      call self.keyboard_cur.read_input()
      "[NOTE] keyboard_cur might be changed within read_input()
      " So post_input() is not necessarily same as input()ed one
      call self.keyboard_cur.post_input()
    catch /KEYBOARD_TIMEOUT/
      " currently TIMEOUT never occur in excursion mode
      call self.keyboard_cur.on_timeout()
    endtry
  endwhile
endfunction

function! s:smalls.keyboard_swap(kbd) "{{{1
  call self.statusline_update(a:kbd.name)
  let self.keyboard_cur = a:kbd
endfunction

function! s:smalls.do_jump() "{{{1
  call self.hl.clear().shade()
  if empty(self.poslist)
    return
  endif
  try
    call smalls#pos#new(self,
          \ smalls#jump#new(self).get_pos()
          \ ).jump()
  catch 'JUMP_CANCELED'
    return
  endtry
  throw 'SUCCESS'
endfunction

function! s:smalls.pos() "{{{1
  return self.env.p
endfunction

function! s:smalls.mode() "{{{1
  return self.env.mode
endfunction

function! s:smalls.statusline_update(mode) "{{{1
  " force to update statusline by meaningless option update ':help statusline'
  let g:smalls_current_mode = a:mode
  let &ro = &ro
  redraw
endfunction

function! smalls#start(...) "{{{1
  call call( s:smalls.start, a:000, s:smalls)
endfunction
"}}}

" vim: foldmethod=marker
