# SkinnedMeshRagdoll

A lightweight, strict-typed Lua module for Roblox that provides smooth and efficient control over a hybrid ragdoll + hitbox system using Roblox's **Bone** instances.

This module allows you to seamlessly switch between:
- A precise hitbox-based animation system **(hitboxes follow bones)**
- A physics-based ragdoll **(bones follow hitboxes)**

Perfect for games that need accurate hit detection during normal gameplay and realistic ragdoll physics when a character is knocked out or dies.

<video src="https://github.com/user-attachments/assets/642db5e7-5814-4d29-b743-f160b9abbae1" controls></video>

<video src="https://github.com/user-attachments/assets/31af5148-8782-4db5-b4e5-b3d98713bb01" controls></video>


## Features

- Toggle ragdoll mode on/off
- Toggle hitbox-follow mode on/off (mutually exclusive with ragdoll)
- High-performance updates using `workspace:BulkMoveTo`
- Optional custom update rate (default uses `RunService.Stepped`)

## Requirements

- Skinned mesh created using `Bone` instances
- Character model with a `PrimaryPart` set
- A `Folder` containing hitbox parts, each with:
  - A string attribute named `"From"` that matches the name of the Bone it should bind to
  - Optional constraints (e.g., BallSocketConstraint, HingeConstraint) as children for ragdoll physics

## Installation

1. Copy the Lua file into your project (e.g., as a ModuleScript named `SkinnedMeshRagdoll`)
2. Require it where needed

## Usage
```lua
local character = -- your character Model
local hitboxFolder = -- Folder containing your hitbox parts

local ragdoll = RagdollController.new(character, hitboxFolder)

-- Enable hitbox mode (default state for normal gameplay)
ragdoll:SetHitboxState(true)

-- When the character dies, switch to ragdoll
ragdoll:SetRagdollState(true)

-- Optional: set a fixed update interval (e.g., 60 FPS)
ragdoll:SetUpdateRate(1/60)

-- Clean up when done
ragdoll:Destroy()
```
