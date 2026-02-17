import numpy as np
import matplotlib.pyplot as plt
import xarray as xr
import cftime
import re
import sys

in_path = sys.argv[1]
out_path = sys.argv[2]
exp_flag = sys.argv[3]


val = 'rmse'
var = 'RAW_STATE_VARIABLE_guess'

try:
    nc = xr.open_dataset(in_path)
except FileNotFoundError:
    print(in_path + " not found - presumably experiment failed")
method_ind = int(in_path[-4]) - 1

metadata_order = nc['CopyMetaData'].to_numpy().astype(str)
find_index = np.char.find(metadata_order, val)

metadata_index = np.where(find_index == 0)[0][0]

if metadata_order[metadata_index].split(' ')[0] != val:
    raise Exception("Invalid metadata request: " + val)

plot_vals = nc[var][:, metadata_index, 0]

np.save(out_path, plot_vals)
