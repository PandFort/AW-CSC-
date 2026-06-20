# 🎭 Counter-Strike 2 Custom Model Changer

<p align="center">
  <img src="https://img.shields.io/badge/Game-CS2-red?style=for-the-badge&logo=counter-strike" alt="Game Compatibility">
  <img src="https://img.shields.io/badge/Language-Lua-blue?style=for-the-badge&logo=lua" alt="Language">
  <img src="https://img.shields.io/badge/Platform-Windows-0078d4?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/Status-Updated-brightgreen?style=for-the-badge" alt="Status">
</p>

A high-performance player model changer Lua script designed for compatible Counter-Strike 2 cheat loaders (supporting Aimware-like Lua API, including FFI, custom GUI, memory, and entity systems). This script allows you to scan, preload, and apply custom compiled model files (`.vmdl_c`) to players in game.

---

## 📌 Table of Contents
* [👥 Credits & Authorship](#-credits--authorship)
* [🚀 Key Features](#-key-features)
* [📂 Directory Structure](#-directory-structure)
* [🛠️ Installation & Setup](#-installation--setup)
* [⚠️ Disclaimer](#%EF%B8%8F-disclaimer)

---

## 👥 Credits & Authorship

> [!IMPORTANT]
> Please respect the original author's rights and keep this credit section intact when sharing or modifying the script.

* **Original Author**: [Planexx](https://aimware.net/forum/thread/180868) — Original logic, GUI implementation, and memory hooking design.
* **Modified & Updated by**: **PandFort** — Offsets, memory pattern updates, compatibility with latest CS2 versions, and general maintenance.

---

## 🚀 Key Features

* **🔍 Automatic Model Scanner**: Searches your game directory (`csgo/characters/models/`) recursively up to 8 directories deep for compiled `.vmdl_c` player models and lists them in the GUI automatically.
* **⚡ Precache & Load System**: Calls `ResourceSystem013` APIs via FFI to safely load and precache resources before applying them, avoiding game crashes.
* **🎯 Targeting Modes**:
  * **Batch Apply**: Quickly swap models for Yourself, Teammates, or Enemies.
  * **Individual Apply**: Interactively choose a specific alive player from a dynamically updating list to change only their model.
* **🔄 Auto-Reapply Watcher**: Monitors pawns and automatically reapplies the custom model if it is reset by the game (e.g., on round restart or respawn).
* **🧹 Safe Cleanup**: Properly hooks and restores vtable entries (`Source2Client::FrameStageNotify`) on unload to ensure the game client remains stable.

---

## 📂 Directory Structure

To load models correctly, place them according to this hierarchy:

```text
Counter-Strike Global Offensive/
└── game/
    └── csgo/
        └── characters/
            └── models/
                ├── custom_model_1.vmdl_c
                └── custom_model_2.vmdl_c
```

---

## 🛠️ Installation & Setup

### Step 1: Download & Place Custom Models
Put your custom character models (`.vmdl_c` files) into:
```path
<CS2_Folder>\game\csgo\characters\models\
```
*(Create the subfolders if they do not exist)*

### Step 2: Load the Script
Load `custom_skins.lua` through your compatible cheat loader's Lua tab/console.

### Step 3: Configure in the GUI
1. Open the cheat menu to display the **Model Changer** interface.
2. Click **Refresh Model List** to load custom models from disk.
3. Select a model, choose a target (Self, Teammates, Enemies, or a specific player), and click **Apply**.
4. Use **Clear All Assignments** to restore default player models.


