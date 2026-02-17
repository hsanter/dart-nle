import pydartdiags.obs_sequence.obs_sequence as obsq
import pydartdiags.matplots.matplots as mp
import matplotlib.pyplot as plt

import sys

input_obs_seq = sys.argv[1]
output_fig_title = sys.argv[2]
output_file_name = sys.argv[3]

obs_seq = obsq.ObsSequence(input_obs_seq)
obs_type ="RAW_STATE_VARIABLE"

fig = mp.plot_evolution(
    obs_seq=obs_seq,
    type="RAW_STATE_VARIABLE",
    time_bin_width="500s",  # 1-hour bins
    stat="rmse",
    tick_interval=500,
    time_format="%d", # days
    plot_pvu=False
)
ax = fig.axes[0]
L = ax.get_legend()
L.get_texts()[0].set_text('Prior RMSE')
L.get_texts()[1].set_text('Posterior RMSE')
ax.set_title(output_fig_title)

fig.savefig(output_file_name)
plt.close()
