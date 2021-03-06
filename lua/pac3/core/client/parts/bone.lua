jit.on(true, true)

local PART = {}

PART.ClassName = "bone"

pac.StartStorableVars()
	pac.GetSet(PART, "Scale", Vector(1,1,1))
	pac.GetSet(PART, "Size", 1)
	pac.GetSet(PART, "Jiggle", false)
	pac.GetSet(PART, "ScaleChildren", false)
	pac.GetSet(PART, "AlternativeBones", false)
	pac.GetSet(PART, "MoveChildrenToOrigin", false)
	pac.GetSet(PART, "FollowAnglesOnly", false)
	pac.SetupPartName(PART, "FollowPart")
pac.EndStorableVars()

function PART:GetNiceName()
	return self:GetBone()
end

PART.ThinkTime = 0

function PART:OnShow()
	self.BoneIndex = nil
end

PART.OnParent = PART.OnShow

function PART:GetOwner()
	local parent = self:GetParent()
	
	if parent:IsValid() then		
		if parent.ClassName == "model" and parent.Entity:IsValid() then
			return parent.Entity
		end
	end
	
	return self.BaseClass.GetOwner(self)
end

function PART:OnThink()
	-- this is to setup the cached values
	if not self.first_getbpos and self:GetOwner():IsValid() then
		self:GetBonePosition()
		self.first_getbpos = true
	end
end

for k,v in pairs(ents.GetAll()) do
	v.pac_bone_setup_data = nil
end

function PART:OnHide()	
	local owner = self:GetOwner()
	
	if owner:IsValid() then
		owner.pac_bone_setup_data = owner.pac_bone_setup_data or {}
		owner.pac_bone_setup_data[self.UniqueID] = nil
	end
end

function PART:GetBonePosition()
	local owner = self:GetOwner()
	local pos, ang
	
	pos, ang = pac.GetBonePosAng(owner, self.Bone, true)
	if owner:IsValid() then owner:InvalidateBoneCache() end
		
	self.cached_pos = pos
	self.cached_ang = ang

	return pos, ang
end

local dt = 1

local function manpos(ent, id, pos, self, force_set)
	if self.AlternativeBones then
		ent.pac_bone_setup_data[self.UniqueID].pos = self.Position + self.PositionOffset
	else
		ent:ManipulateBonePosition(id, ent:GetManipulateBonePosition(id) + pos)
	end
end

local function manang(ent, id, ang, self, force_set)		
	if self.AlternativeBones then	
		ent.pac_bone_setup_data[self.UniqueID].ang = self.Angles + self.AngleOffset		
	else
		ent:ManipulateBoneAngles(id, ent:GetManipulateBoneAngles(id) + ang)
	end
end

local function manscale(ent, id, scale, self, force_set)
	if self.AlternativeBones then		
		ent.pac_bone_setup_data[self.UniqueID].scale = self.Scale * self.Size		
	else
		ent:ManipulateBoneScale(id, ent:GetManipulateBoneScale(id) * self.Scale * self.Size)
	end
end

local VEC0 = Vector(0,0,0)
local pairs = pairs

local function scale_children(owner, id, scale, origin)
	for _, id in pairs(owner:GetChildBones(id)) do
		local mat = owner:GetBoneMatrix(id)
		if mat then	
			if origin then
				mat:SetTranslation(origin)
			end
			mat:Scale(mat:GetScale() * scale)
			owner:SetBoneMatrix(id, mat)
		end
		scale_children(owner, id, scale, origin)
	end
end

function pac.build_bone_callback(ent)
	if ent.pac_bone_setup_data then
		for uid, data in pairs(ent.pac_bone_setup_data) do
			local part = data.part or NULL
			
			if part:IsValid() then
				local mat = ent:GetBoneMatrix(data.bone)
				if mat then	
					
					if part.FollowPart:IsValid() then
						if part.FollowAnglesOnly then
							local pos = mat:GetTranslation()
							mat:SetAngles(part.Angles + part.AngleOffset + part.FollowPart.cached_ang)									
							mat:SetTranslation(pos)
						else
							mat:SetAngles(part.Angles + part.AngleOffset + part.FollowPart.cached_ang)									
							mat:SetTranslation(part.Position + part.PositionOffset + part.FollowPart.cached_pos)	
						end
					else
						if data.pos then
							mat:Translate(data.pos)
						end				
						
						if data.ang then
							mat:Rotate(data.ang)
						end					
					end
				
					if data.scale then	
						mat:Scale(mat:GetScale() * data.scale)
					end
					
					if part.ScaleChildren then						
						local scale = part.Scale * part.Size
						scale_children(ent, data.bone, scale, data.origin)
					end
									
					ent:SetBoneMatrix(data.bone, mat)
				end
			else
				ent.pac_bone_setup_data[uid] = nil
			end
		end
	end
end

function PART:OnBuildBonePositions()	

	dt = FrameTime() * 2
	local owner = self:GetOwner()
	
	if not owner:IsValid() then return end
	
	self.BoneIndex = self.BoneIndex or owner:LookupBone(self:GetRealBoneName(self.Bone)) or 0

	owner.pac_bone_setup_data = owner.pac_bone_setup_data or {}
	
	if self.AlternativeBones or self.ScaleChildren or self.FollowPart:IsValid() then
		owner.pac_bone_setup_data[self.UniqueID] = owner.pac_bone_setup_data[self.UniqueID] or {}
		owner.pac_bone_setup_data[self.UniqueID].bone = self.BoneIndex
		owner.pac_bone_setup_data[self.UniqueID].part = self
	else
		owner.pac_bone_setup_data[self.UniqueID] = nil
	end
	
	local ang = self:CalcAngles(self.Angles) or self.Angles

	if not owner.pac_follow_bones_function then
		owner.pac_follow_bones_function = pac.build_bone_callback
		owner:AddCallback("BuildBonePositions", function(ent) pac.build_bone_callback(ent) end)
	end
	
	if not self.FollowPart:IsValid() then			
		if self.EyeAngles or self.AimPart:IsValid() then
			ang.r = ang.y
			ang.y = -ang.p			
		end
		
		manpos(owner, self.BoneIndex, self.Position + self.PositionOffset, self)
		manang(owner, self.BoneIndex, ang + self.AngleOffset, self)
	end
	
	if owner.pac_bone_setup_data[self.UniqueID] then
		if self.MoveChildrenToOrigin then
			owner.pac_bone_setup_data[self.UniqueID].origin = self:GetBonePosition()
		else
			owner.pac_bone_setup_data[self.UniqueID].origin = nil
		end
	end
	
	owner:ManipulateBoneJiggle(self.BoneIndex, type(self.Jiggle) == "number" and self.Jiggle or (self.Jiggle and 1 or 0)) -- afaik anything but 1 is not doing anything at all
	
	manscale(owner, self.BoneIndex, self.Scale * self.Size, self)
end

pac.RegisterPart(PART)