let s:self_version = expand('<sfile>:t:r')
let s:self_file = expand('<sfile>')

" Note: The extra argument to globpath() was added in Patch 7.2.051.
let s:globpath_third_arg = v:version > 702 || v:version == 702 && has('patch51')

let s:loaded = {}
let s:cache_module_path = {}
let s:cache_sid = {}

let s:_vital_files_cache_runtimepath = ''
let s:_vital_files_cache = []
let s:_unify_path_cache = {}

function! s:import(name, ...) abort
  let target = {}
  let functions = []
  for a in a:000
    if type(a) == type({})
      let target = a
    elseif type(a) == type([])
      let functions = a
    endif
    unlet a
  endfor
  let module = s:_import(a:name)
  if empty(functions)
    call extend(target, module, 'keep')
  else
    for f in functions
      if has_key(module, f) && !has_key(target, f)
        let target[f] = module[f]
      endif
    endfor
  endif
  return target
endfunction

function! s:load(...) dict abort
  for arg in a:000
    let [name; as] = type(arg) == type([]) ? arg[: 1] : [arg, arg]
    let target = split(join(as, ''), '\W\+')
    let dict = self
    let dict_type = type({})
    while !empty(target)
      let ns = remove(target, 0)
      if !has_key(dict, ns)
        let dict[ns] = {}
      endif
      if type(dict[ns]) == dict_type
        let dict = dict[ns]
      else
        unlet dict
        break
      endif
    endwhile

    if exists('dict')
      call extend(dict, s:_import(name))
    endif
    unlet arg
  endfor
  return self
endfunction

function! s:unload() abort
  let s:loaded = {}
  let s:cache_sid = {}
  let s:cache_module_path = {}
endfunction

function! s:exists(name) abort
  return s:_get_module_path(a:name) !=# ''
endfunction

function! s:search(pattern) abort
  let paths = s:_vital_files(a:pattern)
  let modules = sort(map(paths, 's:_file2module(v:val)'))
  return s:_uniq(modules)
endfunction

function! s:expand_modules(entry, all) abort
  if type(a:entry) == type([])
    let candidates = s:_concat(map(copy(a:entry), 's:search(v:val)'))
    if empty(candidates)
      throw printf('vital: Any of module %s is not found', string(a:entry))
    endif
    if eval(join(map(copy(candidates), 'has_key(a:all, v:val)'), '+'))
      let modules = []
    else
      let modules = [candidates[0]]
    endif
  else
    let modules = s:search(a:entry)
    if empty(modules)
      throw printf('vital: Module %s is not found', a:entry)
    endif
  endif
  call filter(modules, '!has_key(a:all, v:val)')
  for module in modules
    let a:all[module] = 1
  endfor
  return modules
endfunction

function! s:_import(name) abort
  if type(a:name) == type(0)
    return s:_build_module(a:name)
  endif
  let path = s:_get_module_path(a:name)
  if path ==# ''
    throw 'vital: module not found: ' . a:name
  endif
  let sid = s:_get_sid_by_script(path)
  if !sid
    try
      execute 'source' fnameescape(path)
    catch /^Vim\%((\a\+)\)\?:E484/
      throw 'vital: module not found: ' . a:name
    catch /^Vim\%((\a\+)\)\?:E127/
      " Ignore.
    endtry

    let sid = s:_get_sid_by_script(path)
  endif
  return s:_build_module(sid)
endfunction

function! s:_get_module_path(name) abort
  let key = a:name . '_'
  if has_key(s:cache_module_path, key)
    return s:cache_module_path[key]
  endif
  if s:_is_absolute_path(a:name) && filereadable(a:name)
    return a:name
  endif
  if a:name ==# ''
    let paths = [s:self_file]
  elseif a:name =~# '\v^\u\w*%(\.\u\w*)*$'
    let paths = s:_vital_files(a:name)
  else
    throw 'vital: Invalid module name: ' . a:name
  endif

  call filter(paths, 'filereadable(expand(v:val, 1))')
  let path = get(paths, 0, '')
  let s:cache_module_path[key] = path
  return path
endfunction

function! s:_get_sid_by_script(path) abort
  if has_key(s:cache_sid, a:path)
    return s:cache_sid[a:path]
  endif

  let path = s:_unify_path(a:path)
  for line in filter(split(s:_redir('scriptnames'), "\n"),
  \                  'stridx(v:val, s:self_version) > 0')
    let list = matchlist(line, '^\s*\(\d\+\):\s\+\(.\+\)\s*$')
    if !empty(list) && s:_unify_path(list[2]) ==# path
      let s:cache_sid[a:path] = list[1] - 0
      return s:cache_sid[a:path]
    endif
  endfor
  return 0
endfunction

function! s:_file2module(file) abort
  let filename = fnamemodify(a:file, ':p:gs?[\\/]?/?')
  let tail = matchstr(filename, 'autoload/vital/_\w\+/\zs.*\ze\.vim$')
  return join(split(tail, '[\\/]\+'), '.')
endfunction

if filereadable(expand('<sfile>:r') . '.VIM')
  " resolve() is slow, so we cache results.
  " Note: On windows, vim can't expand path names from 8.3 formats.
  " So if getting full path via <sfile> and $HOME was set as 8.3 format,
  " vital load duplicated scripts. Below's :~ avoid this issue.
  function! s:_unify_path(path) abort
    if has_key(s:_unify_path_cache, a:path)
      return s:_unify_path_cache[a:path]
    endif
    let value = tolower(fnamemodify(resolve(fnamemodify(
    \                   a:path, ':p')), ':~:gs?[\\/]?/?'))
    let s:_unify_path_cache[a:path] = value
    return value
  endfunction
else
  function! s:_unify_path(path) abort
    return resolve(fnamemodify(a:path, ':p:gs?[\\/]?/?'))
  endfunction
endif

if s:globpath_third_arg
  function! s:_runtime_files(path) abort
    return split(globpath(&runtimepath, a:path, 1), "\n")
  endfunction
else
  function! s:_runtime_files(path) abort
    return split(globpath(&runtimepath, a:path), "\n")
  endfunction
endif

function! s:_vital_files(pattern) abort
  if s:_vital_files_cache_runtimepath !=# &runtimepath
    let path = printf('autoload/vital/%s/**/*.vim', s:self_version)
    let s:_vital_files_cache = s:_runtime_files(path)
    let mod = ':p:gs?[\\/]\+?/?'
    call map(s:_vital_files_cache, 'fnamemodify(v:val, mod)')
    let s:_vital_files_cache_runtimepath = &runtimepath
  endif
  let target = substitute(a:pattern, '\.', '/', 'g')
  let target = substitute(target, '\*', '[^/]*', 'g')
  let regexp = printf('autoload/vital/%s/%s.vim', s:self_version, target)
  return filter(copy(s:_vital_files_cache), 'v:val =~# regexp')
endfunction

" Copy from System.Filepath
if has('win16') || has('win32') || has('win64')
  function! s:_is_absolute_path(path) abort
    return a:path =~? '^[a-z]:[/\\]'
  endfunction
else
  function! s:_is_absolute_path(path) abort
    return a:path[0] ==# '/'
  endfunction
endif

function! s:_build_module(sid) abort
  if has_key(s:loaded, a:sid)
    return copy(s:loaded[a:sid])
  endif
  let functions = s:_get_functions(a:sid)

  let prefix = '<SNR>' . a:sid . '_'
  let module = {}
  for func in functions
    let module[func] = function(prefix . func)
  endfor
  if has_key(module, '_vital_created')
    call module._vital_created(module)
  endif
  let export_module = filter(copy(module), 'v:key =~# "^\\a"')
  let s:loaded[a:sid] = get(g:, 'vital_debug', 0) ? module : export_module
  if has_key(module, '_vital_loaded')
    let V = vital#{s:self_version}#new()
    call module._vital_loaded(V)
  endif
  return copy(s:loaded[a:sid])
endfunction

if exists('+regexpengine')
  function! s:_get_functions(sid) abort
    let funcs = s:_redir(printf("function /\\%%#=2^\<SNR>%d_", a:sid))
    let map_pat = '<SNR>' . a:sid . '_\zs\w\+'
    return map(split(funcs, "\n"), 'matchstr(v:val, map_pat)')
  endfunction
else
  function! s:_get_functions(sid) abort
    let prefix = '<SNR>' . a:sid . '_'
    let funcs = s:_redir('function')
    let filter_pat = '^\s*function ' . prefix
    let map_pat = prefix . '\zs\w\+'
    return map(filter(split(funcs, "\n"),
    \          'stridx(v:val, prefix) > 0 && v:val =~# filter_pat'),
    \          'matchstr(v:val, map_pat)')
  endfunction
endif

if exists('*uniq')
  function! s:_uniq(list) abort
    return uniq(a:list)
  endfunction
else
  function! s:_uniq(list) abort
    let i = len(a:list) - 1
    while 0 < i
      if a:list[i] ==# a:list[i - 1]
        call remove(a:list, i)
        let i -= 2
      else
        let i -= 1
      endif
    endwhile
    return a:list
  endfunction
endif

function! s:_concat(lists) abort
  let result_list = []
  for list in a:lists
    let result_list += list
  endfor
  return result_list
endfunction

function! s:_redir(cmd) abort
  let [save_verbose, save_verbosefile] = [&verbose, &verbosefile]
  set verbose=0 verbosefile=
  redir => res
    silent! execute a:cmd
  redir END
  let [&verbose, &verbosefile] = [save_verbose, save_verbosefile]
  return res
endfunction

function! vital#{s:self_version}#new() abort
  return s:_import('')
endfunction
