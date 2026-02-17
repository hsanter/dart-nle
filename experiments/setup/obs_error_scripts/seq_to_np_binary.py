# HS: python script for converting a DART obs sequence file to a
# series of numpy binaries with innovation statistics stored.
# written for use with L05 model, 4/2024, and assuming that no ensemble obs space members
# are output

import subprocess
import numpy as np
import sys
import re

input_obs_seq = sys.argv[1]
output_file_name = sys.argv[2]

# input_obs_seq = '/Users/santer/dart-home/work/run_control/filter111/obs_seq.final.control.1'
# output_file_name = "all_np_files_test.npz"

grep_call = subprocess.run(
    ["grep -A1 'obs_type_definitions' " + input_obs_seq + " | grep -v 'obs_type_definitions'"], shell=True, capture_output=True)
num_obs_types_string = grep_call.stdout.decode()
num_obs_types = int(num_obs_types_string)

grep_call = subprocess.run(
    ["grep 'num_copies' " + input_obs_seq], shell=True, capture_output=True)
num_copies_string = grep_call.stdout.decode()
num_copies = np.array(
    [int(s) for s in re.findall(r'\b\d+\b', num_copies_string)]).sum()

grep_call = subprocess.run(
    ["grep 'num_obs' " + input_obs_seq], shell=True, capture_output=True)
num_obs_string = grep_call.stdout.decode()
num_obs = np.array([int(s) for s in re.findall(r'\b\d+\b', num_obs_string)])[0]
# subprocess.call(["sed -i -e 's/hello/helloworld/g' www.txt"], shell=True)


first_obs_loc = 17 + num_obs_types - 1
first_pm_loc = 19 + num_obs_types - 1
first_am_loc = 20 + num_obs_types - 1
first_pv_loc = 21 + num_obs_types - 1
first_r_loc = 32 + num_obs_types - 1 + (num_obs_types-1)*17
first_time_loc = 31 + num_obs_types - 1
fol = str(first_obs_loc)
fpml = str(first_pm_loc)
faml = str(first_am_loc)
fpvl = str(first_pv_loc)
frl = str(first_r_loc)
ftl = str(first_time_loc)

# number of assimilation cycles; inferred by number of distinct times obs occur at
# in file, so not robust.
sed_call = subprocess.run(["sed -n '" + ftl + "~17p' " + input_obs_seq +
                          " | uniq | wc -l"], shell=True, capture_output=True)
num_cycles = int(sed_call.stdout.decode())


# get obs
sed_call = subprocess.run(
    ["sed -n '" + fol + "~17p' " + input_obs_seq], shell=True, capture_output=True)
all_obs_strings = sed_call.stdout.decode().split('\n')
all_obs = np.array(all_obs_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))
# get prior mean
sed_call = subprocess.run(
    ["sed -n '" + fpml + "~17p' " + input_obs_seq], shell=True, capture_output=True)
all_pm_strings = sed_call.stdout.decode().split('\n')
all_pm = np.array(all_pm_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))
# get post mean
sed_call = subprocess.run(
    ["sed -n '" + faml + "~17p' " + input_obs_seq], shell=True, capture_output=True)
all_am_strings = sed_call.stdout.decode().split('\n')
all_am = np.array(all_am_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))
# get prior var
sed_call = subprocess.run(
    ["sed -n '" + fpvl + "~17p' " + input_obs_seq], shell=True, capture_output=True)
all_pv_strings = sed_call.stdout.decode().split('\n')
all_pv = np.array(all_pv_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get r estimates
sed_call = subprocess.run(
    ["sed -n '" + frl + "~17p' " + input_obs_seq], shell=True, capture_output=True)
all_r_strings = sed_call.stdout.decode().split('\n')
all_r = np.array(all_r_strings[:num_obs:num_obs//num_cycles]).astype(float)
print(all_r)

np.savez(output_file_name, all_obs=all_obs, all_pm=all_pm,
         all_am=all_am, all_pv=all_pv, all_r=all_r)
