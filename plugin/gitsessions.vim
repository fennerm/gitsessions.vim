" gitsessions.vim - auto save/load vim sessions based on git branches
" Maintainer:       William Ting <io at williamting.com>
" Site:             https://github.com/wting/gitsessions.vim

" SETUP

if exists('g:loaded_gitsessions') || v:version < 700 || &cp
    finish
endif
let g:loaded_gitsessions = 1

function! s:RTrim_slashes(string)
    return substitute(a:string, '[/\\]$', '', '')
endfunction

" fix for Windows users (https://github.com/wting/gitsessions.vim/issues/2)
if !exists('g:VIMFILESDIR')
    let g:VIMFILESDIR = has('unix') ? $HOME . '/.vim/' : $VIM . '/vimfiles/'
endif

" sessions save path
if !exists('g:gitsessions_dir')
    let g:gitsessions_dir = 'sessions'
else
    let g:gitsessions_dir = s:RTrim_slashes(g:gitsessions_dir)
endif

" Cache session file
" Pros: performance gain (x100) on large repositories
" Cons: switch between git branches will be missed from GitSessionUpdate()
" 	You are advised to save it manually by calling to GitSessionSave()
" Default - cache disabled
if !exists('g:gitsessions_use_cache')
    let g:gitsessions_use_cache = 1
endif

" used to control auto-save behavior
if !exists('s:session_exist')
    let s:session_exist = 0
endif

" HELPER FUNCTIONS

function! s:ReplaceBadChars(string)
    return substitute(a:string, '/', '_', 'g')
endfunction

function! s:Trim(string)
    return substitute(substitute(a:string, '^\s*\(.\{-}\)\s*$', '\1', ''), '\n', '', '')
endfunction

function! s:GitBranchName()
    let l:branch_name = s:ReplaceBadChars(s:Trim(system("\git rev-parse --abbrev-ref HEAD")))
    if v:shell_error == 128
        return 0
    else
        return l:branch_name
    endif
endfunction

function! s:InGitRepo()
    let l:is_git_repo = system("\git rev-parse --git-dir >/dev/null")
    return v:shell_error == 0

endfunction

function! s:OsSep()
    " TODO(wting|2013-12-29): untested for Windows gvim
    return has('unix') ? '/' : '\'
endfunction

function! s:IsAbsPath(path)
    return a:path[0] == s:OsSep()
endfunction

" LOGIC FUNCTIONS

function! s:ParentDir(path)
    let l:sep = s:OsSep()
    let l:front = s:IsAbsPath(a:path) ? l:sep : ''
    return l:front . join(split(a:path, l:sep)[:-2], l:sep)
endfunction

function! s:FindGitDir(dir)
    if isdirectory(a:dir . '/.git')
        return a:dir . '/.git'
    elseif has('file_in_path') && has('path_extra')
        return finddir('.git', a:dir . ';')
    else
        return s:FindGitDirAux(a:dir)
    endif
endfunction

function! s:FindGitDirAux(dir)
    return isdirectory(a:dir . '/.git') ? a:dir . '/.git' : s:FindGitDirAux(s:ParentDir(a:dir))
endfunction

function! s:FindProjectDir(dir)
    return s:ParentDir(s:FindGitDir(a:dir))
endfunction

function! s:SessionPath(sdir, pdir)
    let l:path = a:sdir . a:pdir
    return s:IsAbsPath(a:sdir) ? l:path : g:VIMFILESDIR . l:path
endfunction

function! s:SessionDir()
    if s:InGitRepo()
        return s:SessionPath(g:gitsessions_dir, s:FindProjectDir(getcwd()))
    else
        return s:SessionPath(g:gitsessions_dir, getcwd())
    endif
endfunction

function! s:SessionFile(invalidate_cache)
    if g:gitsessions_use_cache && !a:invalidate_cache && exists('s:cached_SessionFile')
        return s:cached_SessionFile
    endif
    let l:dir = s:SessionDir()
    let l:branch = s:GitBranchName()

    if exists('s:cached_SessionFile')
        unlet s:cached_SessionFile
    endif

    if l:branch == 0
        let s:cached_SessionFile = l:dir . '/session'
    else
        let s:cached_SessionFile = (empty(l:branch)) ? l:dir . '/master' : l:dir . '/' . l:branch
    endif
    return s:cached_SessionFile
endfunction

function! g:SessionFile(invalidate_cache)
    if g:gitsessions_use_cache && !a:invalidate_cache && exists('g:cached_SessionFile')
        return g:cached_SessionFile
    endif
    let l:dir = g:SessionDir()
    let l:branch = g:GitBranchName()
    if exists('g:cached_SessionFile')
        unlet g:cached_SessionFile
    endif
    if l:branch == 0
        let g:cached_SessionFile = l:dir . '/session'
    else
        let g:cached_SessionFile = (empty(l:branch)) ? l:dir . '/master' : l:dir . '/' . l:branch
    endif
    return g:cached_SessionFile
endfunction

" PUBLIC FUNCTIONS

function! g:GitSessionSave()
    let l:dir = s:SessionDir()
    let l:file = s:SessionFile(1)

    if !isdirectory(l:dir)
        call mkdir(l:dir, 'p')

        if !isdirectory(l:dir)
            echoerr "cannot create directory:" l:dir
            return
        endif
    endif

    if isdirectory(l:dir) && (filewritable(l:dir) != 2)
        echoerr "cannot write to:" l:dir
        return
    endif

    let s:session_exist = 1
    if filereadable(l:file)
        execute 'mksession!' l:file
        echom "session updated:" l:file
    else
        execute 'mksession!' l:file
        echom "session saved:" l:file
    endif
    redrawstatus!
endfunction

function! g:GitSessionUpdate(...)
    let l:show_msg = a:0 > 0 ? a:1 : 1
    let l:file = s:SessionFile(0)

    if s:session_exist && filereadable(l:file)
        execute 'mksession!' l:file
        if l:show_msg
            echom "session updated:" l:file
        endif
    endif
endfunction

function! g:GitSessionLoad(...)
    if argc() != 0
        return
    endif

    let l:show_msg = a:0 > 0 ? a:1 : 0
    let l:file = s:SessionFile(1)

    if filereadable(l:file)
        let s:session_exist = 1
        execute 'source' l:file
        echom "session loaded:" l:file
    elseif l:show_msg
        echom "session not found:" l:file
    endif
    redrawstatus!
endfunction

function! g:GitSessionDelete()
    " Delete is a tricky case, we still need to use cached version if any.
    " This version was used and saved by GitSessionUpdate(), however
    " we should ensure that session cached variable is cleared.
    let l:file = s:SessionFile(1)
    let s:session_exist = 0
    if exists('s:cached_SessionFile')
        unlet s:cached_SessionFile
    endif
    if filereadable(l:file)
        call delete(l:file)
        echom "session deleted:" l:file
    endif
endfunction

augroup gitsessions
    autocmd!
    if ! exists("g:gitsessions_disable_auto_load")
        autocmd VimEnter * nested :call g:GitSessionLoad()
    endif
    autocmd BufEnter * :call g:GitSessionUpdate(0)
    autocmd VimLeave * :call g:GitSessionUpdate()
augroup END

command GitSessionSave call g:GitSessionSave()
command GitSessionLoad call g:GitSessionLoad(1)
command GitSessionDelete call g:GitSessionDelete()
