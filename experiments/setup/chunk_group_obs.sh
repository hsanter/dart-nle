export n=$1

cp input.nml input.nml.orig

python chunk_obs_seq.py obs_seq.out.${postf} "${n}" "obs_chunks/obs_seq.out.${postf}"

for (( i=1; i<=n; i++ )); do
  sed \
    -e "s/filename_seq[[:space:]]*=[[:space:]]*'obs_seq.out',/filename_seq         = 'obs_seq.out.${postf}.${i}',/" \
    -e "s/filename_out[[:space:]]*=[[:space:]]*'obs_seq.out.grouped'/filename_out         = 'obs_seq.out.${postf}.${i}'/" \
    input.nml.orig > input.nml.edit
  mv input.nml.edit input.nml

  mv obs_chunks/obs_seq.out.${postf}.${i} .
  ./obs_grouping_tool
  mv obs_seq.out.${postf}.${i} obs_chunks
done

rm input.nml.orig
rm dart_log.nml
rm dart_log.out
