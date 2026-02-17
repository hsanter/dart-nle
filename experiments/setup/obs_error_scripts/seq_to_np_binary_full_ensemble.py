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

# input_obs_seq = 'temp'
# output_file_name = "test.npz"

ens_size = 80
num_obs_vals = 2*ens_size

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
# num_obs = 6
# subprocess.call(["sed -i -e 's/hello/helloworld/g' www.txt"], shell=True)


first_obs_loc = 17 + num_obs_types - 1 + num_obs_vals
first_pm_loc = 19 + num_obs_types - 1+ num_obs_vals
first_am_loc = 20 + num_obs_types - 1+ num_obs_vals
first_pv_loc = 21 + num_obs_types - 1+ num_obs_vals
first_av_loc = 22 + num_obs_types - 1+ num_obs_vals
first_r_loc = 32 + num_obs_types - 1 + (num_obs_types-1)*17 + 2* num_obs_vals
first_time_loc = 31 + num_obs_types - 1 + 2 * num_obs_vals
first_ens_mem_loc = 23 + num_obs_types - 1+ num_obs_vals
first_last_ens_mem_loc = 23 + num_obs_types - 2 + 2* num_obs_vals
fol = str(first_obs_loc)
fpml = str(first_pm_loc)
faml = str(first_am_loc)
fpvl = str(first_pv_loc)
favl = str(first_av_loc)
frl = str(first_r_loc)
ftl = str(first_time_loc)
feml = str(first_ens_mem_loc)

# number of assimilation cycles; inferred by number of distinct times obs occur at
# in file, so not robust.
sed_call = subprocess.run(["sed -n '" + ftl + "~{}p' ".format(17+num_obs_vals) + input_obs_seq +
                          " | uniq | wc -l"], shell=True, capture_output=True)
num_cycles = int(sed_call.stdout.decode())


# get obs
sed_call = subprocess.run(
    ["sed -n '" + fol + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_obs_strings = sed_call.stdout.decode().split('\n')
all_obs = np.array(all_obs_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get prior mean
sed_call = subprocess.run(
    ["sed -n '" + fpml + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_pm_strings = sed_call.stdout.decode().split('\n')
all_pm = np.array(all_pm_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get post mean
sed_call = subprocess.run(
    ["sed -n '" + faml + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_am_strings = sed_call.stdout.decode().split('\n')
all_am = np.array(all_am_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get prior var
sed_call = subprocess.run(
    ["sed -n '" + fpvl + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_pv_strings = sed_call.stdout.decode().split('\n')
all_pv = np.array(all_pv_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get post var
sed_call = subprocess.run(
    ["sed -n '" + favl + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_av_strings = sed_call.stdout.decode().split('\n')
all_av = np.array(all_av_strings[:num_obs]).astype(
    float).reshape((num_cycles, num_obs//num_cycles))

# get ensemble values
sed_call = subprocess.run(
    ["sed -n '" + feml + "~{},+{}p' ".format(17 + num_obs_vals, num_obs_vals-1) + input_obs_seq], shell=True, capture_output=True)
all_ens_strings = sed_call.stdout.decode().split('\n')
all_ens = np.array(all_ens_strings[:len(all_ens_strings)-1]).astype(
    float).reshape((num_obs, num_obs_vals))

all_prior_ens = all_ens[:,::2]
all_post_ens = all_ens[:,1::2]

# get r estimates
sed_call = subprocess.run(
    ["sed -n '" + frl + "~{}p' ".format(17 + num_obs_vals) + input_obs_seq], shell=True, capture_output=True)
all_r_strings = sed_call.stdout.decode().split('\n')
all_r = np.array(all_r_strings[:num_obs:num_obs//num_cycles]).astype(float)
print(all_r)

np.savez(output_file_name, all_obs=all_obs, all_pm=all_pm,
         all_am=all_am, all_pv=all_pv, all_av=all_av, all_r=all_r, all_prior_ens=all_prior_ens, all_post_ens=all_post_ens)
