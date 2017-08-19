" Author: Bjorn Neergaard <bjorn@neersighted.com>, modified by Yann fery <yann@fery.me>
" Description: Manages the loclist and quickfix lists

" Return 1 if there is a buffer with buftype == 'quickfix' in bufffer list
function! ale#list#IsQuickfixOpen() abort
    for l:buf in range(1, bufnr('$'))
        if getbufvar(l:buf, '&buftype') is# 'quickfix'
            return 1
        endif
    endfor
    return 0
endfunction

" Check if we should open the list, based on the save event being fired, and
" that setting being on, or the setting just being set to `1`.
function! s:ShouldOpen(buffer) abort
    let l:val = ale#Var(a:buffer, 'open_list')
    let l:saved = getbufvar(a:buffer, 'ale_save_event_fired', 0)

    return l:val is 1 || (l:val is# 'on_save' && l:saved)
endfunction

" A comparison function for de-duplicating loclist items for quickfix.
function! ale#list#TextLocItemCompare(left, right) abort
    let l:cmp_val = ale#util#LocItemCompare(a:left, a:right)

    if l:cmp_val
        return l:cmp_val
    endif

    if a:left.text < a:right.text
        return -1
    endif

    if a:left.text > a:right.text
        return 1
    endif

    return 0
endfunction

function! ale#list#GetCombinedList() abort
    let l:list = []

    for l:info in values(g:ale_buffer_info)
        call extend(l:list, l:info.loclist)
    endfor

    call sort(l:list, function('ale#list#TextLocItemCompare'))
    call uniq(l:list, function('ale#list#TextLocItemCompare'))

    return l:list
endfunction

function! s:FixList(list) abort
    let l:new_list = []

    for l:item in a:list
        if l:item.bufnr == -1
            " If the buffer number is invalid, remove it.
            let l:fixed_item = copy(l:item)
            call remove(l:fixed_item, 'bufnr')
        else
            " Don't copy the Dictionary if we do not need to.
            let l:fixed_item = l:item
        endif

        call add(l:new_list, l:fixed_item)
    endfor

    return l:new_list
endfunction

function! ale#list#SetLists(buffer, loclist) abort
    let l:title = expand('#' . a:buffer . ':p')

    if g:ale_set_quickfix
        let l:quickfix_list = ale#list#GetCombinedList()

        if has('nvim')
            call setqflist(s:FixList(l:quickfix_list), ' ', l:title)
        else
            call setqflist(s:FixList(l:quickfix_list))
            call setqflist([], 'r', {'title': l:title})
        endif
    elseif g:ale_set_loclist
        " If windows support is off, bufwinid() may not exist.
        " We'll set result in the current window, which might not be correct,
        " but is better than nothing.
        let l:win_id = exists('*bufwinid') ? bufwinid(str2nr(a:buffer)) : 0

        if has('nvim')
            call setloclist(l:win_id, s:FixList(a:loclist), ' ', l:title)
        else
            call setloclist(l:win_id, s:FixList(a:loclist))
            call setloclist(l:win_id, [], 'r', {'title': l:title})
        endif
    endif

    let l:keep_open = ale#Var(a:buffer, 'keep_list_window_open')

    " Open a window to show the problems if we need to.
    "
    " We'll check if the current buffer's List is not empty here, so the
    " window will only be opened if the current buffer has problems.
    if s:ShouldOpen(a:buffer) && (l:keep_open || !empty(a:loclist))
        let l:winnr = winnr()
        let l:mode = mode()
        let l:reset_visual_selection = l:mode is? 'v' || l:mode is# "\<c-v>"
        let l:reset_character_selection = l:mode is? 's' || l:mode is# "\<c-s>"

        if g:ale_set_quickfix
            if !ale#list#IsQuickfixOpen()
                execute 'copen ' . str2nr(ale#Var(a:buffer, 'list_window_size'))
            endif
        elseif g:ale_set_loclist
            execute 'lopen ' . str2nr(ale#Var(a:buffer, 'list_window_size'))
        endif

        " If focus changed, restore it (jump to the last window).
        if l:winnr isnot# winnr()
            wincmd p
        endif

        if l:reset_visual_selection || l:reset_character_selection
            " If we were in a selection mode before, select the last selection.
            normal! gv

            if l:reset_character_selection
                " Switch back to Select mode, if we were in that.
                normal! "\<c-g>"
            endif
        endif
    endif
endfunction

function! ale#list#CloseWindowIfNeeded(buffer) abort
    if ale#Var(a:buffer, 'keep_list_window_open') || !s:ShouldOpen(a:buffer)
        return
    endif

    try
        " Only close windows if the quickfix list or loclist is completely empty,
        " including errors set through other means.
        if g:ale_set_quickfix
            if empty(getqflist())
                cclose
            endif
        elseif g:ale_set_loclist && empty(getloclist(0))
            lclose
        endif
    " Ignore 'Cannot close last window' errors.
    catch /E444/
    endtry
endfunction
