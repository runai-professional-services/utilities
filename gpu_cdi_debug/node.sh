#!/bin/bash
# Run on one GPU node. Creates output dir and writes each command's output to a file.

OUT=~/runai-cdi-collect-$(date +%Y%m%d)
mkdir -p "$OUT"
cd "$OUT" || exit 1

# 1. CDI directory and files
ls -la /etc/cdi 2>/dev/null > "$OUT/cdi_etc_ls.txt"
ls -la /var/run/cdi 2>/dev/null > "$OUT/cdi_var_run_ls.txt"
cat /var/run/cdi/management.nvidia.com-gpu.yaml 2>/dev/null > "$OUT/cdi_spec_management_nvidia_gpu.yaml"
find /etc/cdi /var/run/cdi -type f 2>/dev/null -exec echo "=== {} ===" \; -exec cat {} \; > "$OUT/cdi_all_files.txt" 2>&1

# 2. Containerd config
containerd config dump 2>/dev/null > "$OUT/containerd_config_dump.txt"
cat /cm/local/apps/containerd/var/etc/config.toml 2>/dev/null > "$OUT/containerd_bcm_config.txt"
ls -la /cm/local/apps/containerd/var/etc/conf.d/ 2>/dev/null > "$OUT/containerd_conf_d_listing.txt"

# 3. Toolkit config and driver visibility
cat /usr/local/nvidia/toolkit/.config/nvidia-container-runtime/config.toml 2>/dev/null > "$OUT/toolkit_config_toml.txt"
nvidia-container-cli info 2>/dev/null > "$OUT/nvidia_container_cli_info.txt"
ls -la /usr/bin/nvidia-smi /usr/lib/x86_64-linux-gnu/libnvidia-ml.so* 2>/dev/null > "$OUT/driver_paths.txt"

# 4. Toolkit process and mounts
ps aux 2>/dev/null | grep -E 'nvidia-toolkit|nvidia-cdi' > "$OUT/toolkit_process.txt" 2>&1
mount 2>/dev/null | grep -E 'cdi|nvidia' > "$OUT/toolkit_mounts.txt" 2>&1
ls -la /var/run/cdi > "$OUT/var_run_cdi_ls.txt" 2>&1
readlink -f /var/run/cdi 2>/dev/null > "$OUT/var_run_cdi_realpath.txt" 2>&1

# 5. BCM conf.d contents (no redirect inside the for "in" list)
for f in /cm/local/apps/containerd/var/etc/conf.d/*.toml; do
  [ -e "$f" ] || continue
  echo "=== $f ==="
  cat "$f" 2>/dev/null
done > "$OUT/bcm_conf_d_toml.txt" 2>&1

echo "Node collection done. Outputs in $OUT"
ls -la "$OUT"
