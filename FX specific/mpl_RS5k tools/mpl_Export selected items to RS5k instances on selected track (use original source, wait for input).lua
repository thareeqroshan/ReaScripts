-- @description Export selected items to RS5k instances on selected track (use original source, wait for input)
-- @version 1.0
-- @author MPL
-- @website https://forum.cockos.com/showthread.php?t=188335
-- @noindex
-- @changelog
--    + 


  local vrs = 'v1.0'
  local scr_title = 'Export selected items to RS5k instances on selected track (use original source, wait for input)'
  --NOT gfx NOT reaper
 --------------------------------------------------------------------
  function main()
    
    Undo_BeginBlock2( 0 )
    -- track check
      local track = GetSelectedTrack(0,0)
      if not track then return end        
    -- item check
      local item = GetSelectedMediaItem(0,0)
      if not item then return true end  
      
    --[[ get base pitch
      local ret, base_pitch = reaper.GetUserInputs( scr_title, 1, 'Set base pitch', 60 )
      if not ret 
        or not tonumber(base_pitch) 
        or tonumber(base_pitch) < 0 
        or tonumber(base_pitch) > 127 then
        return 
      end
      base_pitch = math.floor(tonumber(base_pitch))    ]]
      
    -- get info for new midi take
      local proceed_MIDI, MIDI = ExportSelItemsToRs5k_FormMIDItake_data()        
    -- export to RS5k
      for i = 1, CountSelectedMediaItems(0) do
        local item = reaper.GetSelectedMediaItem(0,i-1)
        local it_len = GetMediaItemInfo_Value( item, 'D_LENGTH' )
        local take = reaper.GetActiveTake(item)
        if not take or reaper.TakeIsMIDI(take) then goto skip_to_next_item end
        local tk_src =  GetMediaItemTake_Source( take )
        local s_offs = GetMediaItemTakeInfo_Value( take, 'D_STARTOFFS' )
        local src_len =GetMediaSourceLength( tk_src )
        local filepath = reaper.GetMediaSourceFileName( tk_src, '' )
        if filepath == '' then 
          par_src = GetMediaSourceParent( tk_src )
          filepath = reaper.GetMediaSourceFileName( par_src, '' )
          src_len =GetMediaSourceLength( tk_src )
        end
        --msg(s_offs/src_len)
        ExportItemToRS5K(base_pitch + i-1,filepath, s_offs/src_len, (s_offs+it_len)/src_len, track)
        ::skip_to_next_item::
      end
      
      reaper.Main_OnCommand(40006,0)--Item: Remove items      
    -- add MIDI
      if proceed_MIDI then ExportSelItemsToRs5k_AddMIDI(track, MIDI,base_pitch) end        
      reaper.Undo_EndBlock2( 0, 'Export selected items to RS5k instances', -1 )     
    
  end 
  ----------------------------------------------------------------------- 
  function ExportItemToRS5K(note,filepath, start_offs, end_offs, track)
    local rs5k_pos = TrackFX_AddByName( track, 'ReaSamplomatic5000', false, -1 )
    TrackFX_SetNamedConfigParm(  track, rs5k_pos, 'FILE0', filepath)
    TrackFX_SetNamedConfigParm(  track, rs5k_pos, 'DONE', '')      
    TrackFX_SetParamNormalized( track, rs5k_pos, 2, 0) -- gain for min vel
    TrackFX_SetParamNormalized( track, rs5k_pos, 3, note/127 ) -- note range start
    TrackFX_SetParamNormalized( track, rs5k_pos, 4, note/127 ) -- note range end
    TrackFX_SetParamNormalized( track, rs5k_pos, 5, 0.5 ) -- pitch for start
    TrackFX_SetParamNormalized( track, rs5k_pos, 6, 0.5 ) -- pitch for end
    TrackFX_SetParamNormalized( track, rs5k_pos, 8, 0 ) -- max voices = 0
    TrackFX_SetParamNormalized( track, rs5k_pos, 9, 0 ) -- attack
    TrackFX_SetParamNormalized( track, rs5k_pos, 11, 1) -- obey note offs
    if start_offs and end_offs then
      TrackFX_SetParamNormalized( track, rs5k_pos, 13, start_offs ) -- attack
      TrackFX_SetParamNormalized( track, rs5k_pos, 14, end_offs )   
    end  
  end
  ----------------------------------------------------------------------
  function ftest()
    local stop
    local retval, rawmsg, tsval, devIdx, projPos, projLoopCnt = MIDI_GetRecentInputEvent(0)
    if retval ~= 0 and tsval > -SR*1 then
      if (devIdx & 0x10000) == 0 or devIdx == 0x1003e then -- should works without this after REAPER6.39rc2, so thats just in case
        local isNoteOn = rawmsg:byte(1)>>4 == 0x9
        if isNoteOn then 
          base_pitch = rawmsg:byte(2)
          stop = true
          reaper.Undo_BeginBlock2( 0 )
          main()
          reaper.Undo_EndBlock2( 0, 'Export items to rs5k', 0xFFFFFFFF )
        end
      end
    end
      
    if os.clock() - TS > 5 then stop = true end
    if not stop then defer(ftest) end
  end
  ----------------------------------------------------------------------
  function VF_CheckFunctions(vrs)  local SEfunc_path = reaper.GetResourcePath()..'/Scripts/MPL Scripts/Functions/mpl_Various_functions.lua'  if  reaper.file_exists( SEfunc_path ) then dofile(SEfunc_path)  if not VF_version or VF_version < vrs then  reaper.MB('Update '..SEfunc_path:gsub('%\\', '/')..' to version '..vrs..' or newer', '', 0) else return true end   else  reaper.MB(SEfunc_path:gsub('%\\', '/')..' not found. You should have ReaPack installed. Right click on ReaPack package and click Install, then click Apply', '', 0) if reaper.APIExists('ReaPack_BrowsePackages') then ReaPack_BrowsePackages( 'Various functions' ) else reaper.MB('ReaPack extension not found', '', 0) end end end
  --------------------------------------------------------------------  
  local ret = VF_CheckFunctions(3.18) if ret then local ret2 = VF_CheckReaperVrs(5.975,true) if ret2 then 
    local scr_name = ({reaper.get_action_context()})[2]
    SR = tonumber(reaper.format_timestr_pos( 1-reaper.GetProjectTimeOffset( 0,false ), '', 4 )) -- get sample rate obey project start offset
    TS = os.clock()
    ftest()
  end end