
###### Henry Santer ########
## Script for generating basic RMSE figure from DART obs_seq files ##
## March 2026 ##

import pydartdiags.obs_sequence.obs_sequence as obsq
import pydartdiags.matplots.matplots as mp
from pydartdiags.stats import stats
import matplotlib.pyplot as plt
import numpy as np

import sys

input_obs_seq = sys.argv[1]
output_fig_title = sys.argv[2]
output_file_name = sys.argv[3]
rmse_type = int(sys.argv[4])

# rmse_types:
# 1: OMB
# 2: OMA
# 3: TMB
# 4: TMA

rmse_choices = ['OMB', 'OMA', 'TMB', 'TMA']

obs_seq = obsq.ObsSequence(input_obs_seq)
obs_type ="RAW_STATE_VARIABLE"

df = obs_seq.df
stats.diag_stats(df)
stats.bin_by_time(df,'10800s')
tick_interval=800
time_format='%m-%d'
df_by_time = stats.time_statistics(df)

if rmse_type == 1:
    df['sq_err'] = (df['prior_ensemble_mean'] - df['observation'])**2
elif rmse_type == 2:
    df['sq_err'] = (df['posterior_ensemble_mean'] - df['observation'])**2
elif rmse_type == 3:
    df['sq_err'] = (df['prior_ensemble_mean'] - df['truth'])**2
elif rmse_type == 4:
    df['sq_err'] = (df['posterior_ensemble_mean'] - df['truth'])**2
else:
    raise ValueError('Invalid selection for rmse_type: {}'.format(rmse_type))

rmse = np.sqrt(df.groupby('time_bin', observed=True)['sq_err'].mean())
df_by_time = stats.time_statistics(df)



fig, ax = plt.subplots()

ax.plot(df_by_time['time_bin_midpoint'], rmse, label='{} RMSE'.format(rmse_choices[rmse_type-1]))

tick_positions = df["time_bin_midpoint"][::tick_interval]
ax.set_xticks(tick_positions)
ax.set_xticklabels(
    tick_positions.dt.strftime(time_format), rotation=45, ha="right"
)

ax.legend()
ax.set_xlabel('Model Time')
ax.set_ylabel('RMSE')
ax.set_title(output_fig_title)

fig.savefig(output_file_name)
plt.close()
