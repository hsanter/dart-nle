import pydartdiags.obs_sequence.obs_sequence as obsq
import pydartdiags.matplots.matplots as mp
from pydartdiags.stats import stats
import matplotlib.pyplot as plt

import sys

input_obs_seq = sys.argv[1]
output_fig_title = sys.argv[2]
output_file_name = sys.argv[3]

obs_seq = obsq.ObsSequence(input_obs_seq)
obs_type ="RAW_STATE_VARIABLE"

df = obs_seq.df
stats.diag_stats(df)
stats.bin_by_time(df,'10800s')
tick_interval=800
time_format='%m-%d'
df_by_time = stats.time_statistics(df)


fig, ax = plt.subplots()

ax.plot(df_by_time['time_bin_midpoint'], df_by_time['prior_rmse'], label='Prior RMSE')

tick_positions = df["time_bin_midpoint"][::tick_interval]
ax.set_xticks(tick_positions)
ax.set_xticklabels(
    tick_positions.dt.strftime(time_format), rotation=45, ha="right"
)

ax.legend()
ax.set_xlabel('Model Time')
ax.set_ylabel('O-B RMSEs')
ax.set_title(output_fig_title)

fig.savefig(output_file_name)
plt.close()
