"""Keep a runtime-suspended NVIDIA dGPU asleep while tests nest Hyprland.

Two things woke it, measured by sampling power/runtime_status:
- glvnd and the Vulkan loader load the NVIDIA vendor while enumerating and
  hold /dev/nvidia0 for the whole run. Rendering stays on Mesa, like the
  desktop's iGPU.
- Hyprland runs `lspci -vnn` at startup only to log the GPUs; lspci reads PCI
  config space, which resumes the dGPU for about five seconds. A no-op lspci
  first on the compositor's PATH leaves only that log line empty.
"""
from __future__ import annotations

import os
from pathlib import Path

MESA_ONLY = {
    key: value for key, value in (
        ("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json"),
        ("VK_ICD_FILENAMES", "/usr/share/vulkan/icd.d/radeon_icd.json"),
    ) if Path(value).is_file()
}


def compositor_env(env: dict, base: Path) -> dict:
    """env for the nested Hyprland itself: Mesa only, and no PCI probing."""
    stub = base / "nested-gpu-bin"
    stub.mkdir(exist_ok=True)
    lspci = stub / "lspci"
    lspci.write_text("#!/bin/sh\nexit 0\n")
    lspci.chmod(0o755)
    return {**env, **MESA_ONLY, "PATH": f"{stub}:{env.get('PATH', os.environ['PATH'])}"}
