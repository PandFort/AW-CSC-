local ffi = assert(ffi, "ffi c")

local function notify(t, m) print(string.format("[%s] %s", t, m)) end

ffi.cdef[[
    typedef struct {
        uint32_t dwFileAttributes;
        uint32_t ftCreationTimeLow,  ftCreationTimeHigh;
        uint32_t ftLastAccessTimeLow, ftLastAccessTimeHigh;
        uint32_t ftLastWriteTimeLow, ftLastWriteTimeHigh;
        uint32_t nFileSizeHigh, nFileSizeLow;
        uint32_t dwReserved0, dwReserved1;
        char     cFileName[260];
        char     cAlternateFileName[14];
    } WIN32_FIND_DATAA;
    void* FindFirstFileA(const char* lpFileName, WIN32_FIND_DATAA* lpFindFileData);
    bool  FindNextFileA (void* hFindFile, WIN32_FIND_DATAA* lpFindFileData);
    bool  FindClose     (void* hFindFile);
    unsigned int GetCurrentDirectoryA(unsigned int nBufferLength, char* lpBuffer);
    int   ShellExecuteA (int hwnd, const char* lpOperation, const char* lpFile,
                         const char* lpParameters, const char* lpDirectory, int nShowCmd);
    int VirtualProtect(void*, uint64_t, unsigned long, unsigned long*);
    const char* CBufStr_Insert_v20(void*, int, const char*, int, bool)
        asm("?Insert@CBufferString@@QEAAPEBDHPEBDH_N@Z");
]]

local k32, sh32
do
    local ok
    ok, k32  = pcall(ffi.load, "kernel32"); if not ok then k32  = ffi.C end
    ok, sh32 = pcall(ffi.load, "shell32");  if not ok then sh32 = ffi.C end
end

local INVALID_HANDLE_VALUE = ffi.cast("void*", -1)
local FILE_ATTRIBUTE_DIRECTORY = 0x10
local PATH_BUF = 260
local FRAME_RENDER_END = 6

local cwd_buf = ffi.new("char[?]", PATH_BUF)
k32.GetCurrentDirectoryA(PATH_BUF, cwd_buf)
local cwd = ffi.string(cwd_buf)
local models_root = cwd:gsub("bin\\win64", "csgo\\characters\\models")
notify("ModelChanger", "Scanning root: " .. models_root)

local models = { [0] = { name = "[ Off / Default ]", path = nil } }

local function res_path_from_full(full)
    return full:gsub("^.*\\characters\\", "characters\\"):gsub("\\", "/"):gsub("%.vmdl_c$", ".vmdl")
end

local function scan_dir(dir, depth)
    if depth > 8 then return end
    local data = ffi.new("WIN32_FIND_DATAA")
    local h = k32.FindFirstFileA(dir .. "\\*", data)
    if h == nil or h == INVALID_HANDLE_VALUE then return end
    repeat
        local name = ffi.string(data.cFileName)
        if name ~= "." and name ~= ".." then
            local full = dir .. "\\" .. name
            if bit.band(data.dwFileAttributes, FILE_ATTRIBUTE_DIRECTORY) ~= 0 then
                scan_dir(full, depth + 1)
            elseif name:lower():match("%.vmdl_c$") then
                models[#models + 1] = {
                    name = name:gsub("%.vmdl_c$", ""):gsub("_", " "),
                    path = res_path_from_full(full),
                }
            end
        end
    until not k32.FindNextFileA(h, data)
    k32.FindClose(h)
end

local function do_scan()
    for i = #models, 1, -1 do models[i] = nil end
    scan_dir(models_root, 0)
    notify("ModelChanger", string.format("Found %d models", #models))
end
do_scan()

local function combo_options()
    local out = {}
    for k = 0, #models do out[#out + 1] = models[k].name end
    return out
end

local client_base = mem.GetModuleBase("client.dll")
if not client_base then notify("ModelChanger", "client.dll not loaded"); return end

local CES_RVA = 0x24E76A0

local function GetEntityInstance(idx)
    if idx <= 0 or idx > 0x7fff then return nil end
    local ces = ffi.cast("uintptr_t*", ffi.cast("uintptr_t", client_base) + CES_RVA)[0]
    if ces == 0 then return nil end
    local chunk, slot = bit.rshift(idx, 9), bit.band(idx, 0x1FF)
    local ok, le = pcall(function() return ffi.cast("uintptr_t*", ces + 0x8 * chunk + 0x10)[0] end)
    if not ok or not le or le == 0 then return nil end
    local ok2, ent = pcall(function() return ffi.cast("uintptr_t*", le + 0x70 * slot)[0] end)
    if not ok2 or not ent or ent == 0 then return nil end
    return ent
end

local fnSetModel = ffi.cast("void*(__thiscall*)(void*, const char*)",
    mem.FindPattern("client.dll", "40 53 48 83 EC 20 48 8B D9 4C 8B C2 48 8B 0D ?? ?? ?? ?? 48 8D 54 24"))
if fnSetModel == nil then notify("ModelChanger", "SetModel sig not found"); return end

local ci_sig = "4C 8B 0D ?? ?? ?? ?? 4C 8B D2 4C 8B D9"
local ci_ty  = ffi.typeof("void*(__cdecl*)(const char*, int*)")

local ci_addr = mem.FindPattern("resourcesystem.dll", ci_sig)
if not ci_addr or ci_addr == 0 then notify("ModelChanger", "CreateInterface sig not found"); return end

local IRS = ffi.cast(ci_ty, ci_addr)("ResourceSystem013", nil)
if IRS == nil then notify("ModelChanger", "no IRS"); return end

local bload_addr = mem.FindPattern("resourcesystem.dll", "40 53 55 57 48 81 EC 80 00 00 00 48 8B 01 49 8B E8 48 8B FA")
if not bload_addr or bload_addr == 0 then notify("ModelChanger", "BlockingLoad sig not found"); return end
local fnPrecache = ffi.cast("void*(__thiscall*)(void*, void*, const char*)", bload_addr)

do
    local vtbl = ffi.cast("void***", IRS)[0]
    local vt41 = tonumber(ffi.cast("uintptr_t", vtbl[41]))
    if vt41 ~= tonumber(bload_addr) then
        notify("ModelChanger", string.format("Warning: vtable[41]=0x%X vs sig 0x%X mismatch", vt41, tonumber(bload_addr)))
    end
end

local tier0 = ffi.load("tier0.dll")
local CBufferString = ffi.metatype([[
    struct { int m_nLength; int m_nAllocatedSize;
             union { char* m_pString; char m_szString[8]; }; }
]], { __index = { Insert = tier0.CBufStr_Insert_v20 } })

local function PrecacheResource(path)
    local names = CBufferString(0, bit.bor(0x80000000, 0x40000000, 8), nil)
    names:Insert(0, path, -1, false)
    return fnPrecache(IRS, names, "")
end

local assignments = {}
local cur_targets = {}
local pending     = {}

local function queue_apply(p_idx)
    for _, v in ipairs(pending) do if v == p_idx then return end end
    pending[#pending + 1] = p_idx
end

local function set_assignment(p_idx, model_idx)
    assignments[p_idx] = (model_idx and model_idx > 0 and models[model_idx]) and model_idx or nil
    cur_targets[p_idx] = nil
    queue_apply(p_idx)
end

local function clear_all_assignments()
    for k in pairs(assignments) do assignments[k] = nil end
    for k in pairs(cur_targets) do cur_targets[k] = nil end
    for i = #pending, 1, -1 do pending[i] = nil end
end

local function ChangeOneModelNow()
    if #pending == 0 then return end
    local p_idx = table.remove(pending, 1)
    local model_idx = assignments[p_idx]
    if not model_idx then cur_targets[p_idx] = nil; return end
    local m = models[model_idx]
    if not m or not m.path then return end
    pcall(PrecacheResource, m.path)
    local inst = GetEntityInstance(p_idx)
    if inst and inst ~= 0 then
        pcall(function() fnSetModel(ffi.cast("void*", inst), m.path) end)
    end
    cur_targets[p_idx] = m.path
end

local function create_interface(dll, name)
    local e = mem.FindPattern(dll, ci_sig)
    if e == nil then return nil end
    return ffi.cast(ci_ty, e)(name, nil)
end

local hook_restores = {}

local function vtable_hook(inst, index, hookfn, typestr)
    local ty = ffi.typeof(typestr)
    local g = ffi.cast(ty, hookfn)
    local vt = ffi.cast("uintptr_t**", inst)[0]
    local orig = vt[index]
    local old = ffi.new("unsigned long[1]")
    local psz = ffi.sizeof("void*")
    ffi.C.VirtualProtect(vt + index, psz, 0x4, old)
    vt[index] = ffi.cast("uintptr_t", g)
    ffi.C.VirtualProtect(vt + index, psz, old[0], old)
    hook_restores[#hook_restores + 1] = function()
        ffi.C.VirtualProtect(vt + index, psz, 0x4, old)
        vt[index] = orig
        ffi.C.VirtualProtect(vt + index, psz, old[0], old)
    end
    return ffi.cast(ty, orig)
end

local Source2Client = create_interface("client.dll", "Source2Client002")
if Source2Client == nil then notify("ModelChanger", "no Source2Client002"); return end

local orig_FSN
orig_FSN = vtable_hook(Source2Client, 36, function(this, stage)
    if stage == FRAME_RENDER_END and #pending > 0 then pcall(ChangeOneModelNow) end
    return orig_FSN(this, stage)
end, "void(__thiscall*)(void*, int)")

local function GetPlayerName(pawn)
    local ok1, ctrl = pcall(function() return pawn:GetPropEntity("m_hController") end)
    if ok1 and ctrl then
        local ok2, n = pcall(function() return ctrl:GetName() end)
        if ok2 and n and n ~= "" then return n end
        local ok3, n2 = pcall(function() return ctrl:GetPropString("m_iszPlayerName") end)
        if ok3 and n2 and n2 ~= "" then return n2 end
    end
    local ok4, n3 = pcall(function() return pawn:GetName() end)
    if ok4 and n3 and n3 ~= "" then return n3 end
    return "#" .. tostring(pawn:GetIndex())
end

local function GetAlivePlayers()
    local result = {}
    local ok_lp, lp = pcall(entities.GetLocalPawn)
    local lp_idx = -1
    if ok_lp and lp then pcall(function() lp_idx = lp:GetIndex() end) end
    local ok_f, pawns = pcall(entities.FindByClass, "C_CSPlayerPawn")
    if not ok_f or not pawns then return result end
    for _, pawn in pairs(pawns) do
        local ok_a, alive = pcall(function() return pawn:IsAlive() end)
        if ok_a and alive then
            local ok_i, p_idx = pcall(function() return pawn:GetIndex() end)
            if ok_i and p_idx and p_idx > 0 then
                local team = 0
                pcall(function() team = pawn:GetTeamNumber() end)
                result[#result + 1] = {
                    pawn = pawn, idx = p_idx,
                    name = GetPlayerName(pawn), team = team,
                    is_local = (p_idx == lp_idx),
                }
            end
        end
    end
    return result
end

local player_list_data = {}
local last_fingerprint = ""

local function build_player_combo()
    local players = GetAlivePlayers()
    local parts = {}
    for _, p in ipairs(players) do parts[#parts + 1] = p.idx .. ":" .. p.name end
    local fp = table.concat(parts, "|")
    if fp == last_fingerprint then return end
    last_fingerprint = fp
    player_list_data = players
    local names = {}
    for _, p in ipairs(players) do names[#names + 1] = p.name end
    if #names == 0 then names[1] = "(No players)" end
    cb_player:SetOptions(unpack(names))
    cb_player:SetValue(0)
end

local window = gui.Window("custom_model_win", "Model Changer by Planexx", 220, 220, 520, 440)
local ref_menu = gui.Reference("Menu")
callbacks.Register("Draw", "cm_WindowToggle", function()
    window:SetActive(ref_menu:IsActive())
end)

local group = gui.Groupbox(window, "Model Changer", 10, 10, 500, 380)

local btn_w = 460
local btn_h = 30

local cb_model = gui.Combobox(group, "cm_model_sel", "Choose Model", unpack(combo_options()))

local cb_batch = gui.Combobox(group, "cm_batch_target", "Target",
    "Apply to Myself", "Apply to Teammates", "Apply to Enemies")

local btn_apply = gui.Button(group, "Apply", function()
    local mi = cb_model:GetValue()
    local bi = cb_batch:GetValue()
    local players = GetAlivePlayers()
    local lp_team = 0
    for _, info in ipairs(players) do
        if info.is_local then lp_team = info.team; break end
    end
    local count = 0
    for _, info in ipairs(players) do
        local match = false
        if bi == 0 then match = info.is_local
        elseif bi == 1 then match = (not info.is_local) and info.team == lp_team
        elseif bi == 2 then match = info.team ~= lp_team and info.team > 1 end
        if match then
            set_assignment(info.idx, mi)
            count = count + 1
        end
    end
    local tgt = ({ "Self", "Teammates", "Enemies" })[bi + 1] or "?"
    if mi == 0 then
        notify("ModelChanger", string.format("%s x%d cleared", tgt, count))
    else
        notify("ModelChanger", string.format("%s x%d -> %s", tgt, count, models[mi].name))
    end
end)
btn_apply:SetWidth(btn_w)
btn_apply:SetHeight(btn_h)

local cb_player = gui.Combobox(group, "cm_player_sel", "Choose Player", "(Starting...)")

local btn_apply_sel = gui.Button(group, "Apply to Selected Player", function()
    local sel = cb_player:GetValue()
    local info = player_list_data[sel + 1]
    if not info then notify("ModelChanger", "No player selected"); return end
    local mi = cb_model:GetValue()
    set_assignment(info.idx, mi)
    if mi == 0 then
        notify("ModelChanger", "Cleared: " .. info.name)
    else
        notify("ModelChanger", string.format("%s -> %s", info.name, models[mi].name))
    end
end)
btn_apply_sel:SetWidth(btn_w)
btn_apply_sel:SetHeight(btn_h)

local btn_ref_player = gui.Button(group, "Refresh Player List", function()
    last_fingerprint = ""
    build_player_combo()
    notify("ModelChanger", string.format("Player list refreshed (%d players)", #player_list_data))
end)
btn_ref_player:SetWidth(btn_w)
btn_ref_player:SetHeight(btn_h)

local btn_clear = gui.Button(group, "Clear All Assignments", function()
    clear_all_assignments()
    notify("ModelChanger", "All assignments cleared")
end)
btn_clear:SetWidth(btn_w)
btn_clear:SetHeight(btn_h)

local btn_ref_model = gui.Button(group, "Refresh Model List", function()
    do_scan()
    cb_model:SetOptions(unpack(combo_options()))
    cb_model:SetValue(0)
    clear_all_assignments()
    notify("ModelChanger", string.format("Model list refreshed (%d models), assignments cleared", #models))
end)
btn_ref_model:SetWidth(btn_w)
btn_ref_model:SetHeight(btn_h)

local btn_open = gui.Button(group, "Open Models Folder", function()
    sh32.ShellExecuteA(0, "open", models_root, nil, nil, 1)
end)
btn_open:SetWidth(btn_w)
btn_open:SetHeight(btn_h)

local refresh_tick = 0
callbacks.Register("Draw", "cm_player_auto_refresh", function()
    refresh_tick = refresh_tick + 1
    if refresh_tick == 90 or refresh_tick % 180 == 0 then
        pcall(build_player_combo)
    end
end)

local watch_n = 0
callbacks.Register("Draw", "cm_reapply_watch", function()
    watch_n = watch_n + 1
    if watch_n % 60 ~= 0 or not next(assignments) then return end
    local ok_f, pawns = pcall(entities.FindByClass, "C_CSPlayerPawn")
    if not ok_f or not pawns then return end
    for _, pawn in pairs(pawns) do
        local ok_i, p_idx = pcall(function() return pawn:GetIndex() end)
        if ok_i and p_idx and assignments[p_idx] then
            local nm_ok, cur = pcall(function() return pawn:GetModelName() end)
            local tgt = cur_targets[p_idx]
            if nm_ok and cur and tgt and cur ~= tgt then
                queue_apply(p_idx)
            end
        end
    end
end)

callbacks.Register("Unload", "cm_unload", function()
    for _, r in ipairs(hook_restores) do pcall(r) end
    notify("ModelChanger", "Unloaded (hooks restored)")
end)

notify("ModelChanger", "Loaded (multiplayer)")
