-- @description Sort focused ReaEQ bands by frequency
-- @version 1.0
-- @author MPL
-- @website http://forum.cockos.com/showthread.php?t=188335

  -- NOT reaper NOT gfx
  for key in pairs(reaper) do _G[key]=reaper[key]  end 
  function msg(s) ShowConsoleMsg(s..'\n') end
  -----------------------------------------------------------------------------
  function MPL_SortReaEQByFreq(track, fx)
    if not track or not fx then return end
    local test_exist = TrackFX_GetEQ( track, false )
    if not test_exist then return end
    
    -- get whole table of bands + order
    local bands = {}
    local num_params = TrackFX_GetNumParams( track, fx )
    for paramidx = 3, num_params, 3 do
      local retval, bandtype_norm =  TrackFX_GetNamedConfigParm( track, fx, 'BANDTYPE'..(paramidx/3-1) )
      if retval then 
        bands[#bands+1] = {bandtype = tonumber(bandtype_norm),
                            enabled = tonumber(( {TrackFX_GetNamedConfigParm( track, fx, 'BANDENABLED'..(paramidx/3-1) )})[2]),
                            freq = TrackFX_GetParamNormalized( track, fx, paramidx-3),
                            gain = TrackFX_GetParamNormalized( track, fx, paramidx-2),
                            Q = TrackFX_GetParamNormalized( track, fx, paramidx-1),
                            prev_freq = paramidx-3,
                            prev_gain = paramidx-2,
                            prev_Q = paramidx-1}
      end
    end
    
    -- sort by Freq
    local t_sorted = {}
    for _, key in ipairs(getKeysSortedByValue(bands, function(a, b) return a < b end, 'freq')) do t_sorted[#t_sorted+1] = bands[key] end
    
    
    -- push new order to ReaEQ
    -- generate map table
      local map_t = {}
      for band_idx = 0, #t_sorted-1 do
        map_t[t_sorted[band_idx+1].prev_freq] = band_idx*3
        map_t[t_sorted[band_idx+1].prev_gain] = band_idx*3+1
        map_t[t_sorted[band_idx+1].prev_Q] = band_idx*3+2
        TrackFX_SetParamNormalized( track, fx, band_idx*3+0, t_sorted[band_idx+1].freq )
        TrackFX_SetParamNormalized( track, fx, band_idx*3+1, t_sorted[band_idx+1].gain )
        TrackFX_SetParamNormalized( track, fx, band_idx*3+2, t_sorted[band_idx+1].Q )        
        TrackFX_SetNamedConfigParm( track, fx, 'BANDTYPE'..band_idx, t_sorted[band_idx+1].bandtype )
        TrackFX_SetNamedConfigParm( track, fx, 'BANDENABLED'..band_idx, t_sorted[band_idx+1].enabled )
      end
      
    return map_t 
    
  end
  -----------------------------------------------------------------------------
  function getKeysSortedByValue(tbl, sortFunction, param) -- https://stackoverflow.com/questions/2038418/associatively-sorting-a-table-by-value-in-lua
    local keys = {}
    for key in pairs(tbl) do table.insert(keys, key) end  
    table.sort(keys, function(a, b) return sortFunction(tbl[a][param], tbl[b][param])  end)  
    return keys
  end  
  -----------------------------------------------------------------------------
  function eugen27771_GetTrackStateChunk(track)
    if not track then return end
    local fast_str, track_chunk
    fast_str = SNM_CreateFastString("")
    if SNM_GetSetObjectState(track, fast_str, false, false) then track_chunk = SNM_GetFastString(fast_str) end
    SNM_DeleteFastString(fast_str)  
    return track_chunk
  end 
  ----------------------------------------------------------------------------- 
  function literalize(str) -- http://stackoverflow.com/questions/1745448/lua-plain-string-gsub
     if str then  return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%" .. c end) end
  end  
  -----------------------------------------------------------------------------
  function ModFXChunk(src_chunk, map_t) -- FXID.....WAK
    -- mod TCP controls
      local ret = ModChunk_TCP(src_chunk, map_t)
      if ret then src_chunk = ret end
    
    -- extract/modify env and PM chunks
      local PM_Env_chunks = src_chunk:match('<.*>')
      if PM_Env_chunks then 
        local PM_Env_ch_t = {}
        for ch in PM_Env_chunks:gmatch('<.->') do PM_Env_ch_t[#PM_Env_ch_t+1] = ch end
        for i = 1, #PM_Env_ch_t do 
          local out = ModChunk_EnvPMChunk(PM_Env_ch_t[i], map_t)
          if out then PM_Env_ch_t[i] = out end
        end
        local PM_Env_chunks_out = table.concat(PM_Env_ch_t, '\n') 
        src_chunk = src_chunk:gsub(literalize(PM_Env_chunks), PM_Env_chunks_out)
      end
      
    -- learn
      local ret = ModChunk_Learn(src_chunk, map_t)
      if ret then src_chunk = ret end
            
    return src_chunk
  end
  -----------------------------------------------------------------------------
  function ModChunk_TCP(src_chunk, map_t)
    local TCP = src_chunk:find('PARM_TCP')
    local TCP_src, TCP_new
    if TCP then 
      TCP_src = src_chunk:match('PARM_TCP.*\n')
      local TCPctrl_t = {}
      for num in TCP_src:gmatch('[%d]+') do TCPctrl_t[#TCPctrl_t+1] = tonumber(num) end
      TCP_new = 'PARM_TCP '
      for i = 1, #TCPctrl_t do 
        local old_id = TCPctrl_t[i]
        if not map_t [old_id] then 
          TCP_new = TCP_new..TCPctrl_t[i]..' '
         else
          TCP_new = TCP_new..map_t [old_id]..' '
        end
      end
      TCP_new = TCP_new..'\n'
      return src_chunk:gsub(TCP_src, TCP_new)
    end  
  end
  -----------------------------------------------------------------------------
  function ModChunk_Learn(src_chunk, map_t)
    local learn = src_chunk:find('PARMLEARN')
    if learn then
      local learn_src = src_chunk:match('PARMLEARN.*\n')
      local learn_new = ''
      for line in learn_src:gmatch('[^\r\n]+') do
        local id = tonumber(line:match('%d'))
        local follow = line:match('%d(.*)')
        if map_t[id] then
          learn_new = learn_new..'PARMLEARN '..map_t[id]..follow..' \n'
         else
          learn_new = learn_new..line..'\n'
        end
      end
      return src_chunk:gsub(learn_src, learn_new)
    end
    
  end
  -----------------------------------------------------------------------------
  function ModChunk_EnvPMChunk(src, map_t)
    local pat_word
    local ch_match = src:match('PARMENV.-\n') 
    if ch_match then pat_word = 'PARMENV' end
    if not pat_word then
      ch_match = src:match('PROGRAMENV.-\n') 
      if ch_match then pat_word = 'PROGRAMENV' end
      if not pat_word then return end
    end   
 
    local par_id = tonumber(ch_match:match('[%d]+'))
    local follow = ch_match:match('[%d]+(.*)')
    if map_t[par_id] then 
      local ch_match_mod = pat_word..' '..map_t[par_id]..follow
      local out = src:gsub(pat_word..'.-\n', ch_match_mod)
      if out then return out end
    end
  end
  -----------------------------------------------------------------------------
  function ModLinksAcrossFX(chunk, tr, fxnumber, map_t)
    local out_chunk = chunk
    for fx = 1, TrackFX_GetCount( tr ) do
        local fxGUID = TrackFX_GetFXGUID( tr, fx-1 )
        local pat = 'FXID '..literalize(fxGUID)..'.-WAK'
        local lim,lim2 =  out_chunk:find(pat)
        local mod_chunk = out_chunk:match(pat)
        mod_chunk = ModLinksAcrossFX_sub(mod_chunk, map_t, fx-1, fxnumber)
        if mod_chunk then out_chunk = out_chunk:sub(0, lim-1)..mod_chunk..out_chunk:sub(lim2+1) end
    end
    return out_chunk
  end
  -----------------------------------------------------------------------------
  function ModLinksAcrossFX_sub(src_chunk, map_t, cur_fxid, fxnumber_src)
    -- extract/modify env and PM chunks
      local PM_Env_chunks = src_chunk:match('<.*>')
      if PM_Env_chunks then 
        local PM_Env_ch_t = {}
        for ch in PM_Env_chunks:gmatch('<.->') do PM_Env_ch_t[#PM_Env_ch_t+1] = ch end
        for i = 1, #PM_Env_ch_t do 
          local plink_str = PM_Env_ch_t[i]:match('PLINK.-\n')
          local new_plink_str = ''
          if plink_str then
            local t = {}
            for val in plink_str:gmatch('[^%s]+') do t[#t+1] = val end
            if #t == 5 and t[3]:match('%:') then
              local param = tonumber(t[4])
              local inc_fxid = t[3]:match('%:([%d%p]+)')
              if inc_fxid then inc_fxid = tonumber(inc_fxid) end
              local fx_id = cur_fxid + inc_fxid
              if fx_id == fxnumber_src and map_t[param] then 
                t[4] = map_t[param]
                new_plink_str = table.concat(t, ' ')
              end
            end
          end
          local out = PM_Env_ch_t[i]:gsub('PLINK.-\n', new_plink_str..'\n')
          if out then PM_Env_ch_t[i] = out end
        end
        local PM_Env_chunks_out = table.concat(PM_Env_ch_t, '\n') 
        src_chunk = src_chunk:gsub(literalize(PM_Env_chunks), PM_Env_chunks_out)
        return src_chunk
      end
  end
  -----------------------------------------------------------------------------
  function VsrCheck(vrs, pre)
    local appvrs = GetAppVersion()
    local app_full = appvrs:match('[%d%p]+') if app_full then app_full = tonumber(app_full) end
    local app_pre = appvrs:match('pre([%d]+)') if app_pre then app_pre = tonumber(app_pre) end
    if app_full>=vrs then
      if not pre then 
        return true
       elseif pre and app_pre>=pre then
        return true
      end
    end
  end
  -----------------------------------------------------------------------------
  function main()
    local retval, tracknumber, itemnumber, fxnumber = GetFocusedFX()  
    if retval == 1 and itemnumber == -1 and fxnumber >= 0 then
      local tr = CSurf_TrackFromID( tracknumber, false )
      local map_t = MPL_SortReaEQByFreq(tr, fxnumber)
      local fxGUID = TrackFX_GetFXGUID( tr, fxnumber )
      local chunk = eugen27771_GetTrackStateChunk(tr)
      local pat = 'FXID '..literalize(fxGUID)..'.-WAK'
      local lim,lim2 =  chunk:find(pat)
      local mod_chunk = ModFXChunk(chunk:match(pat), map_t)
      local out_chunk = chunk:sub(0, lim-1)..mod_chunk..chunk:sub(lim2+1)
      SetTrackStateChunk( tr, out_chunk, true )
      
      local out_chunk0 = ModLinksAcrossFX(out_chunk, tr, fxnumber, map_t)
      if out_chunk0 then SetTrackStateChunk( tr, out_chunk0, true )  end      
    end
  end
  -----------------------------------------------------------------------------  
  local ret = VsrCheck(5.81, 5)
  if ret then main() else
    MB('Script requre REAPER 5.81pre5+','Sort ReaEQ bands',0)
  end
  
  