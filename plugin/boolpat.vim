" Vim plugin -- Boolean-logic based regular expression pattern matching
" File:         boolpat.vim
" Created:      2011 Nov 30
" Last Change:  2012 Jan 28
" Rev Days:     6
" Author:       Andy Wokula <anwoku@yahoo.de>
" License:      Vim License, see :h license
" Version:      0.1.1
"
" Based on  LogiPat v3c, Copyright (C) 1999-2006 Charles E. Campbell, Jr.
"           http://vim.sf.net/scripts/script.php?script_id=1290
"           http://drchip.0sites.net/astronaut/
"
" Usage: {{{1
"
" :BoolPat {expr}
"
"   converts boolean-logic pattern {expr} into a normal regexp pattern and
"   searches for it.  Basically, {expr} can be any regexp pattern with some
"   special characters in it for boolean operators:
"       !           logical NOT ("not" the following pattern)
"       | or ||     logical OR
"       & or &&     logical AND
"       (...)       grouping
"       whitespace  separates items
"       '...'       quoting
"
" Quoting:
"   Single quotes '...' can be used for literal inclusion of special
"   characters and whitespace in the pattern.  Two single quotes '' result
"   in one single quote, inside or outside of '...':
"       {expr}      RESULT
"       ''          '
"       ''''        ''
"       '''a'       'a   (result of '' followed by 'a')
"       abc'def'    abcdef
"       abc'def     abcdef (optional closing single quote at the end)
"       abc''def    abc'def
"
" Example:
"   :BoolPat !(january | fe'br'uary)
"       matches lines not containing the strings "january" or "february"
"
" Obsolete for now:
"   Get Latest Vim Scripts: 1290 1 :AutoInstall: LogiPat.vim

" Customization: {{{1
" :let g:boolpat_flags = ""
"   flags for the search() function when :BoolPat looks for the first match
"   (not defined per default)
"
" Comparision to LogiPat v3c {{{1
" - :BoolPat replaces :LogiPat
" - new argument syntax: double quotes no longer work around pattern items;
"   quoting is done with single quotes
" - all characters can be included literally in the pattern
" - now uses Vim7 constructs (lists for the stacks), Vim7 is required
" - fixed highlighting activation
" - removed (sorry): Decho overhead
" - :BoolPat error handling: now breaks at first error and doesn't search
"   for erroneous pattern
" - :BoolPat reports if pattern not found
" - fixed "a & b | c" -> "\%(.*a.*\&\%(.*b.*\|.*c.*\)\)" (preclvl bug)
" - ... style changes ...

" ---------------------------------------------------------------------
" Load Once: {{{1
if exists("loaded_boolpat")
  finish
endif
let loaded_boolpat = 1

if v:version < 700 || &cp
  echomsg "boolpat: you need at least Vim 7.0 and 'nocp' set"
  finish
endif

let s:keepcpo = &cpo
set cpo&vim

" Public Interface: {{{1

com! -nargs=? BoolPat  exec s:MakePatAndSearch(<q-args>)

" sil! com -nargs=* BP   exec s:MakePatAndSearch(<q-args>)
" com! -nargs=? BoolPatFlags  let s:BoolPatFlags = <q-args>

" ---------------------------------------------------------------------
" Functions: {{{1
" s:MakePatAndSearch: :BoolPat implementation, execute the search {{{2
" returns the command to activate hlsearch, must be outside a function
func! s:MakePatAndSearch(args)
  if a:args == ""
    echo 'Usage:  :BoolPat {expr}'
    return ""
  endif
  try
    let pat = BoolPat(a:args)
    if exists("g:boolpat_flags") && type(g:boolpat_flags) == type("")
      let sres = search(pat, g:boolpat_flags)
    else
      let sres = search(pat)
    endif
    let @/ = pat
    call histadd("search", pat)
    if sres == 0
      echoerr 'BoolPat: Pattern not found:' pat
    endif
    return 'set hls<'
  catch
    echohl ErrorMsg
    echomsg matchstr(v:exception, ':\zs.*')
    echohl None
  endtry
  return ""
endfunc

" BoolPat: get a regexp pattern from a bool-pattern {{{2
func! BoolPat(pat)
  let s:global_preclvl = 0
  let s:pat_stack = []
  let s:op_stack = []

  let tokens = s:Tokenize(a:pat)

  for pat in tokens
    if pat =~# '^s'
      if pat != "s"
        call s:PushPat('.*'. strpart(pat, 1). '.*')
      else
        echoerr "BoolPat: empty pattern item"
      endif
    else
      call s:PushOp(pat)
    endif
  endfor

  call s:PushOp('Z')

  let result = s:PopPat()

  " sanity checks and cleanup
  if !empty(s:pat_stack)
    echoerr "BoolPat:" len(s:pat_stack)." patterns left on stack -- missing operator?"
  endif
  if !empty(s:op_stack)
    echoerr "BoolPat:" len(s:op_stack)." operators left on stack!"
  endif

  return result
endfunc

" s:Tokenize: tokenize BoolPat's argument {{{2
func! s:Tokenize(pat)
  let ph = s:GetPlaceHolder(a:pat)
  let mod_pat = substitute(a:pat, s:token_pat, ph.'&'.ph, 'g')
  let tokens = split(mod_pat, '\%('.ph.'\)\+')
  call filter(tokens, 'v:val =~ ''\S''')
  call map(tokens, 'get(s:token_map, v:val, s:StrToken(v:val))')
  return tokens
endfunc

let s:token_pat = '&&\|||\|[!()&|]\|\%(\S\@=[^!()&|'']\|''[^'']*\%(''\|$\)\)\+'
let s:token_map = {'&&': '&', '||': '|', '&': '&', '!': '!', '(': '(', ')': ')', '|': '|'}

" unquote {str} and prepend "s" as type information; a closing single quote
" is optional
func! s:StrToken(str)
  return "s". (a:str =~ "'" ? substitute(a:str, '''\(.\)\|''$', '\1', 'g') : a:str)
endfunc

" s:GetPlaceHolder: return a string that doesn't occur in {str} {{{2
func! s:GetPlaceHolder(str)
  for dgt in range(10)
    if a:str !~ "".dgt
      return dgt
    endif
  endfor
  let mid = ''
  while a:str =~ '3'. mid. '5'
    let mid .= '6'
  endwhile
  return '3'. mid. '5'
endfunc

" s:PushPat: {{{2
func! s:PushPat(pat)
  call insert(s:pat_stack, a:pat)
endfunc

" s:PopPat: pop a number/variable from BoolPat's pattern stack {{{2
func! s:PopPat()
  if !empty(s:pat_stack)
    return remove(s:pat_stack, 0)
  else
    echoerr "BoolPat: missing pattern item"
    return '---error---'
  endif
endfunc

" s:PushOp: {{{2
func! s:PushOp(op)

  " determine new operator's precedence level
  if a:op == '('
    let s:global_preclvl += 10
    let preclvl = s:global_preclvl
  elseif a:op == ')'
    let s:global_preclvl -= 10
    if s:global_preclvl < 0
      let s:global_preclvl = 0
      echoerr "BoolPat: too many )s"
    endif
    let preclvl = s:global_preclvl
  elseif a:op == '|'
    let preclvl = s:global_preclvl + 2
  elseif a:op == '&'
    let preclvl = s:global_preclvl + 4
  elseif a:op == '!'
    let preclvl = s:global_preclvl + 6
  elseif a:op == 'Z'
    let preclvl = -1
  else
    echoerr "BoolPat: expr<".expr."> not supported (yet)"
    let preclvl = s:global_preclvl
  endif

  " execute higher-precedence operators
  call s:ReduceStack(preclvl)

  " push new operator onto operator-stack
  if a:op =~ '[!|&]'
    if a:op == '|'
      let preclvl = s:global_preclvl + 1
    elseif a:op == '&'
      let preclvl = s:global_preclvl + 3
    endif
    call insert(s:op_stack, {'op': a:op, 'preclvl': preclvl})
  endif

endfunc

" s:ReduceStack: execute operators from opstack using pattern stack {{{2
func! s:ReduceStack(preclvl)

  while !empty(s:op_stack) && a:preclvl < s:op_stack[0].preclvl
    let op = remove(s:op_stack, 0).op

    if op == '!'
      let n1 = s:PopPat()
      call s:PushPat(s:GetNotPat(n1))

    elseif op == '|'
      let n1 = s:PopPat()
      let n2 = s:PopPat()
      call s:PushPat(s:GetOrPat(n2,n1))

    elseif op == '&'
      let n1 = s:PopPat()
      let n2 = s:PopPat()
      call s:PushPat(s:GetAndPat(n2,n1))
    endif
  endwhile

endfunc

" s:GetNotPat: writes a logical-not for a pattern {{{2
func! s:GetNotPat(pat)
  if a:pat =~ '^\.\*' && a:pat =~ '\.\*$'
    let pat = substitute(a:pat,'^\.\*\(.*\)\.\*$','\1','')
    let ret = '^\%(\%('.pat.'\)\@!.\)*$'
  else
    let ret = '^\%(\%('.a:pat.'\)\@!.\)*$'
  endif
  return ret
endfunc

" s:GetOrPat: writes a logical-or branch using two patterns {{{2
func! s:GetOrPat(pat1, pat2)
  let ret = '\%('.a:pat1.'\|'.a:pat2.'\)'
  return ret
endfunc

" s:GetAndPat: writes a logical-and concat using two patterns {{{2
func! s:GetAndPat(pat1, pat2)
  let ret = '\%('.a:pat1.'\&'.a:pat2.'\)'
  return ret
endfunc

" ---------------------------------------------------------------------
" Cleanup And Modeline: {{{1
let &cpo = s:keepcpo
unlet s:keepcpo
" vim: sts=2 sw=2 et fdm=marker
