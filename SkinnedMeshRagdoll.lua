--!strict

local module = {}

local RunService = game:GetService("RunService")

local Stepped = RunService.Stepped

export type RagdollController = {
	PrimaryPart: BasePart,

	HitboxParts: {[string]: BasePart},

	SetRagdollState: (self: RagdollController, ragdoll: boolean)->(),
	GetRagdollState: (self: RagdollController)->(boolean),

	SetHitboxState: (self: RagdollController, hitbox: boolean)->(),
	GetHitboxState: (self: RagdollController)->(boolean),

	SetUpdateRate: (self: RagdollController, rate: number)->(),

	Update: (self: RagdollController)->(),

	Reset: (self: RagdollController)->(),

	Destroy: (self: RagdollController)->(),
}

type RagdollControllerInternal = {
	_hitbox_active: boolean,
	_ragdoll_active: boolean,
	_destroyed: boolean,
	_update_rate: number,

	_hitbox_update_thread: thread?,
	_ragdoll_update_thread: thread?,

	NumHitbox: number,
	BoneIndices: {string},
	BoneToHitboxMap: {[string]: string},
	HitboxToBoneMap: {[string]: string},
	RagdollConstraints: {[string]: Constraint},

	HitboxRootOffsetMap: {[BasePart]: CFrame},
	BoneOriginMap: {[Bone]: CFrame},

	Bones: {[string]: Bone},

} & RagdollController

local function get_handle(ragdoll: RagdollController) : RagdollControllerInternal
	return ragdoll :: RagdollControllerInternal
end

local function update_assembly(ragdoll: RagdollController)
	local ragdoll_active = get_handle(ragdoll)._ragdoll_active

	for name, part in ragdoll.HitboxParts do
		part.Anchored = not ragdoll_active
		part.CanCollide = ragdoll_active
	end
end

local function reset_bone_transforms(ragdoll: RagdollController)
	local handle = get_handle(ragdoll)

	for _,bone_name in pairs(handle.BoneIndices) do
		local bone = handle.Bones[bone_name]
		if ( not bone ) then
			continue
		end

		bone.CFrame = handle.BoneOriginMap[bone]
		bone.Transform = CFrame.identity
	end
end

local function reset_hitbox_transforms(ragdoll: RagdollController)
	local handle = get_handle(ragdoll)

	local root_transform = ragdoll.PrimaryPart.CFrame
	
	local part_list = table.create(handle.NumHitbox)
	local transform_list = table.create(handle.NumHitbox)

	for part,transform in handle.HitboxRootOffsetMap do
		table.insert(part_list, part)
		table.insert(transform_list, root_transform * transform)
	end

	workspace:BulkMoveTo(part_list, transform_list, Enum.BulkMoveMode.FireCFrameChanged)
end

local function create_update_thread(handle: RagdollControllerInternal)
	return task.spawn(function()
		while (not handle._destroyed) do
			handle.Update(handle)

			-- Step
			if ( handle._update_rate <= 0 ) then
				Stepped:Wait()
			else
				task.wait(handle._update_rate)
			end
		end
	end)
end

local function set_hitbox_state(ragdoll: RagdollController, state: boolean, hitbox_offsets: {[BasePart]: CFrame})
	local handle = get_handle(ragdoll)
	if ( handle._hitbox_active == state ) then
		return
	end

	handle._hitbox_active = state

	update_assembly(handle)

	if ( state ) then
		ragdoll:SetRagdollState(false)
		--ragdoll:Update()
	end

	-- Manage thread
	do
		if ( handle._hitbox_update_thread ) then
			task.cancel(handle._hitbox_update_thread)
			handle._hitbox_update_thread = nil
		end

		if ( state ) then
			handle._hitbox_update_thread = create_update_thread(handle)
		end
	end
end

local function set_ragdoll_state(ragdoll: RagdollController, state: boolean, bone_offsets: {[Bone]: CFrame})
	local handle = get_handle(ragdoll)

	if ( handle._ragdoll_active == state ) then
		return
	end

	handle._ragdoll_active = state

	update_assembly(handle)

	for _,v in handle.RagdollConstraints do
		v.Enabled = state
	end

	if ( state ) then
		-- bandaid fix... super gross... Makes sure the hitbox is in the correct place before we switch over to ragdolling
		do
			local old_hitbox_active = handle._hitbox_active
			handle._hitbox_active = true
			handle._ragdoll_active = false
			handle:Update()
			handle._hitbox_active = old_hitbox_active
			handle._ragdoll_active = true
		end

		ragdoll:SetHitboxState(false)
		--ragdoll:Update()
	else
		reset_bone_transforms(ragdoll)
	end

	-- Manage thread
	do
		if ( handle._ragdoll_update_thread ) then
			task.cancel(handle._ragdoll_update_thread)
			handle._ragdoll_update_thread = nil
		end

		if ( state ) then
			handle._ragdoll_update_thread = create_update_thread(handle)
		end
	end
end

function module.new(character_model: Model, hitbox_folder: Folder) : RagdollController

	local hitbox_ragdoll = {
		_hitbox_active = false,
		_ragdoll_active = false,
		_destroyed = false,
		_update_rate = 0.0,

		PrimaryPart = character_model.PrimaryPart,

		NumHitbox = 0,
		BoneIndices = {},
		BoneToHitboxMap = {},
		HitboxToBoneMap = {},

		HitboxRootOffsetMap = {},
		BoneOriginMap = {},

		RagdollConstraints = {},
		HitboxParts = {},
		Bones = {},
	} :: RagdollControllerInternal

	local hitbox_offsets: {[BasePart]: CFrame} = {}
	local bone_offsets: {[Bone]: CFrame} = {}

	---------------------------------------------------------------------------

	hitbox_ragdoll.Destroy = function(self: RagdollController)
		local root_transform = self.PrimaryPart.CFrame

		for _,v in hitbox_ragdoll.RagdollConstraints do
			v.Enabled = false
		end

		reset_hitbox_transforms(self)

		reset_bone_transforms(self)

		for k,_ in self do
			hitbox_ragdoll[k] = nil
		end

		table.clear(hitbox_offsets)
		table.clear(bone_offsets)

		hitbox_ragdoll._destroyed = true
	end

	hitbox_ragdoll.Reset = function(self: RagdollController)
		reset_hitbox_transforms(self)
		reset_bone_transforms(self)
	end

	hitbox_ragdoll.GetRagdollState = function(self: RagdollController)
		return hitbox_ragdoll._ragdoll_active
	end

	hitbox_ragdoll.SetRagdollState = function(self: RagdollController, ragdoll: boolean)
		set_ragdoll_state(self, ragdoll, bone_offsets)
	end

	hitbox_ragdoll.SetUpdateRate = function(self: RagdollController, rate: number)
		assert(typeof(rate) == "number")
		hitbox_ragdoll._update_rate = rate
	end

	hitbox_ragdoll.GetHitboxState = function(self: RagdollController)
		return hitbox_ragdoll._hitbox_active
	end

	hitbox_ragdoll.SetHitboxState = function(self: RagdollController, hitbox: boolean)
		set_hitbox_state(self, hitbox, hitbox_offsets)
	end

	local part_list = table.create(hitbox_ragdoll.NumHitbox)
	local transform_list = table.create(hitbox_ragdoll.NumHitbox)

	hitbox_ragdoll.Update = function(self: RagdollController)
		-- Bones follow the ragdoll assembly
		if ( hitbox_ragdoll._ragdoll_active ) then
			for _,bone_name in pairs(hitbox_ragdoll.BoneIndices) do
				local bone = hitbox_ragdoll.Bones[bone_name]
				if ( not bone ) then
					continue
				end

				local hitbox_part_name = hitbox_ragdoll.BoneToHitboxMap[bone_name]
				local hitbox_part = hitbox_ragdoll.HitboxParts[hitbox_part_name]
				if ( not hitbox_part ) then
					continue
				end

				bone.WorldCFrame = hitbox_part.CFrame * bone_offsets[bone]
			end
		end

		-- Hitbox assembly follow the bones
		if ( hitbox_ragdoll._hitbox_active ) then
			table.clear(part_list)
			table.clear(transform_list)

			for hitbox_name, hitbox_part in hitbox_ragdoll.HitboxParts do
				local bone = hitbox_ragdoll.Bones[hitbox_ragdoll.HitboxToBoneMap[hitbox_name]]
				if ( not bone ) then
					continue
				end

				table.insert(part_list, hitbox_part)
				table.insert(transform_list, bone.TransformedWorldCFrame * hitbox_offsets[hitbox_part])
			end

			workspace:BulkMoveTo(part_list, transform_list, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	---------------------------------------------------------------------------

	for _,v in hitbox_ragdoll.PrimaryPart:GetDescendants() do
		if v:IsA("Bone") then
			hitbox_ragdoll.Bones[v.Name] = v

			hitbox_ragdoll.BoneOriginMap[v] = v.CFrame

			hitbox_ragdoll.BoneIndices[#hitbox_ragdoll.BoneIndices+1] = v.Name
		end
	end

	local root_cframe = hitbox_ragdoll.PrimaryPart.CFrame
	local i_root_cframe = root_cframe:Inverse()

	-- Process the rig
	for _,part in hitbox_folder:GetChildren() do
		if ( not part:IsA("BasePart") ) then
			continue
		end

		local bone_name = part:GetAttribute("From")
		if ( not bone_name ) then
			continue
		end

		local bone = hitbox_ragdoll.Bones[bone_name]
		if ( not bone ) then
			continue
		end

		for _,k in part:GetChildren() do
			if ( not k:IsA("NoCollisionConstraint") and k:IsA("Constraint") ) then
				hitbox_ragdoll.RagdollConstraints[k.Name] = k
			end
		end

		local attachment = part:FindFirstChild("HitboxAttachment") :: Attachment
		if ( not attachment ) then
			attachment = Instance.new("Attachment")
			assert(attachment)

			attachment.Name = "HitboxAttachment"
			attachment.Parent = part
			attachment.WorldCFrame = bone.WorldCFrame
			
			part.CanQuery = true
		end

		hitbox_ragdoll.HitboxRootOffsetMap[part] = i_root_cframe * part.CFrame
		bone_offsets[bone] = attachment.CFrame
		hitbox_offsets[part] = attachment.CFrame:Inverse()
		
		if ( not part.Anchored ) then
			part.Anchored = true
		end

		hitbox_ragdoll.NumHitbox += 1

		hitbox_ragdoll.HitboxToBoneMap[part.Name] = bone_name
		hitbox_ragdoll.BoneToHitboxMap[bone_name] = part.Name
		hitbox_ragdoll.HitboxParts[part.Name] = part
	end

	return hitbox_ragdoll
end

return module
