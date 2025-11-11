import numpy as np
import matplotlib.pyplot as plt
import xarray as xr
import os
from mpl_toolkits.mplot3d import Axes3D  # needed for 3D projection
import subprocess# --- Load dataset ---

ds = xr.open_dataset("analysis.nc")
state_mean = ds["state_mean"]  # expected shape (N, 3)

N = state_mean.shape[0]


# --- Loop through n = 20 .. N ---
fignum=0
for n in range(10, 100, 2):
    window = state_mean[n - 10:n]
    pts = window.values
    fig = plt.figure(figsize=(6, 5))
    ax = fig.add_subplot(111, projection="3d")
    ax.plot(pts[:, 0], pts[:, 1], pts[:, 2], "-o", markersize=3)
    ax.set_title(f"L63 Ensemble Mean: t = {n}")
    plt.tight_layout()
    ax.set_xlim(-20,20)
    ax.set_ylim(-20,20)
    ax.set_zlim(0,50)
    plt.savefig(f"figures/state_mean_{fignum:04d}.png", dpi=150)
    fignum+=1
    plt.close(fig)

print("3D trajectories saved in the 'figures/' directory.")

gif_path = "figures/l63_ana_traj.gif"
print("Creating gif")
subprocess.run(
    ["convert", "-delay", "20", "figures/state_mean_*.png", gif_path],
    check=True
)
subprocess.run("rm -f figures/state_mean_*.png", shell=True, check=True)


