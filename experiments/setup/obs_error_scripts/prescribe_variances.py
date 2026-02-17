
import sys

fname = sys.argv[1]
new_var = sys.argv[2]
# fname = 'obs_seq_RAW_STATE_VARIABLE_480.out'


with open(fname, 'r+') as ofile:
    text = ofile.read()
    text = text.split('\n')

    for line_no in range(len(text)):
        if text[line_no] == 'kind':
            text[line_no + 3] = "{:.14f}".format(float(new_var))

    text = text[:-1]

with open(fname, 'w') as ofile:
    pass

with open(fname, 'a') as ofile:
    for line in text:
        ofile.write(f"{line}\n")
