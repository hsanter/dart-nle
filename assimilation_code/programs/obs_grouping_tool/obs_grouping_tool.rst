.. _obs grouping tool:

program ``obs_grouping_tool``
=============================

Overview
--------

DART observation sequence files are stored in a proprietary format. DART observations themselves can each be assigned a group number for
batching observations into different subsets (which may be used to indicate that a group of observations have correlated errors, or that
a group of observations all are believed to have identically distributed errors). This program provides some basic infrastructure for going
through an observation sequence file and assigning group numbers based on the location and type of an observation. For the time being,
obs_grouping_tool is only usable for 1D model data.

The actions of the ``obs_grouping_tool`` program are controlled by a Fortran namelist, read from a file named
``input.nml`` in the current directory. A detailed description of each namelist item is described in the namelist
section below.

Additionally, a file specifying the constraints defining each observation group must be provided. A description of the required format
of this observation subset specification file is located below.

Located in this document is a typical example of how obs_grouping_tool is used. Below that are more
details about DART observation sequence files, the structure of individual observations, and general background
information.

Namelist
--------

This namelist is read from the file ``input.nml``. Namelists start with an ampersand '&' and terminate with a slash '/'.
Character strings that contain a '/' must be enclosed in quotes to prevent them from prematurely terminating the
namelist.

::

   &obs_grouping_tool_nml
      filename_seq         = ''
      filename_subset_spec    = ''
      filename_out         = 'obs_seq.grouped'
      /

| 

.. container::

   +------------------------------+-------------------------------------+------------------------------------------------------------------------+
   | Item                         | Type                                | Description                                                            |
   +==============================+=====================================+========================================================================+
   | filename_seq                 | character(len=256)  | The name of the observation sequence file                                              |
   |                              |                                     | to process.                                                            |
   +------------------------------+-------------------------------------+------------------------------------------------------------------------+
   | filename_out                 | character(len=256)                  | The name of the resulting output observation sequence                  |
   |                              |                                     | file, with group numbers assigned.                                     |
   +------------------------------+-------------------------------------+------------------------------------------------------------------------+
   | filename_subset_spec         | character(len=256)                  | The name of the file that specifies the constraints defining each      |
   |                              |                                     | observation subset.                                                    |
   +------------------------------+-------------------------------------+------------------------------------------------------------------------+

| 


Defining observation group constraints
---------------------------------------

The observation group constraints defined in filename_subset_spec follow a predefined format that is read in by obs_grouping_tool.
The contents of a typical filename_subset_spec will look like this:

::

   obs_subset_defs

   SUBSET
   1
   min_box
   0.0
   max_box
   1.0
   type
   'RAW_STATE_VARIABLE'

   SUBSET
   2
   min_box
   0.0
   max_box
   1.0
   type
   'RAW_STATE_VARIABLE_LV'

 CONITNUE HERE TODO


Example
--------


Merge multiple files
~~~~~~~~~~~~~~~~~~~~

Either specify a list of input files for ``filename_seq``, like:

::

   &obs_sequence_tool_nml
      filename_seq       = 'obs_seq20071101',
                           'qscatL2B_2007_11_01a.out',
                           'obs_seq.gpsro_2007110106',
      filename_out       = 'obs_seq20071101.all',
      gregorian_cal      = .true.
   /

and all observations in each of the three input files will be merged in time order and output in a single observation
sequence file. Or from the command line create a file containing one filename per line, either with 'ls':

::

   ls obs_seq_in* > tlist

or with a text editor, or any other tool of your choice. Then,

::

   &obs_sequence_tool_nml
      filename_seq_list = 'tlist',
      filename_out       = 'obs_seq20071101.all',
      gregorian_cal      = .true.
   /

will open 'tlist' and read the filenames, one per line, and merge them together. The output file will be named
'obs_seq20071101.all'. Note that the filenames inside the list file should not have delimiters (e.g. single or double
quotes) around the filenames.



Discussion
----------

DART observation sequence files are lists of individual observations, each with a type, a time, one or more values
(called copies), zero or more quality control flags, a location, and an error estimate. Regardless of the physical order
of the observations in the file, they are always processed in increasing time order, using a simple linked list
mechanism. This tool reads in one or more input observation sequence files, and creates a single output observation
sequence file with all observations sorted into a single, monotonically increasing time ordered output file.

DART observation sequence files contain a header with the total observation count and a table of contents of observation
types. The output file from this tool culls out unused observations, and only includes observation types in the table of
contents which actually occur in the output file. The table of contents **does not** need to be the same across multiple
files to merge them. Each file has a self-contained numbering system for observation types. However, the
``obs_sequence_tool`` must be compiled with a list of observation types (defined in the ``obs_def`` files listed in the
``preprocess`` namelist) which includes all defined types across all input files. See the building section below for
more details on compiling the tool.

The tool can handle observation sequence files at any stage along the processing pipeline: a template file with
locations but no data, input files for an assimilation which have observation values only, or output files from an
assimilation which then might include the prior and posterior mean and standard deviation, and optionally the output
from the forward operator from each ensemble member. In all of these cases, the format of each individual observation is
the same. It has zero or more *copies*, which is where the observation value and the means, forward operators, etc are
stored. Each observation also has zero or more quality control values, *qc*, which can be associated with the incoming
data quality, or can be added by the DART software to indicate how the assimilation processed this observation. Each of
the copies and qc entries has an single associated character label at the start of the observation sequence file which
describes what each entry is, called the *metadata*.

For multiple observation sequence files to be merged they must have the same number of *copies* and *qc* values, and all
associated *metadata* must be identical. To merge multiple files where the numbers do not match exactly, the tool can be
used on the individual files to rename, subset, and reorder the *copies* and/or *qc* first, and then the resulting files
are mergeable. To merge multiple files where the metadata strings do not match, but the data copy or qc values are
indeed the same things, there are options to rename the metadata strings. **This option should be used with care. If the
copies or qc values in different files are not really the same, the tool will go ahead and merge them but the resulting
file will be very wrong.**

The tool offers an additional option for specifying a list of input files. The user creates an ASCII file by any desired
method (e.g. ls > file, editor), with one filename per line. The names on each line in the file should not have any
delimiters, e.g. no single or double quotes at the start or end of the filename. They specify this file with the
``filename_seq_list`` namelist item, and the tool opens the list file and processes each input file in turn. The
namelist item ``num_input_files`` is now DEPRECATED and is ignored. The number of input files is computed from either
the explicit list in ``filename_seq``, or the contents of the ``filename_seq_list`` file.

Time is stored inside of DART as a day number and number of seconds, which is the same no matter which calendar is being
used. But many real-world observations use the Gregorian calendar for converting between number of days and an actual
date. If the ``gregorian_cal`` namelist item is set to ``.TRUE.`` then any times will be printed out to the log file
will be both in day/seconds and calendar date. If the observation times are not using the Gregorian calendar, then set
this value to ``.FALSE.`` and only days/seconds will be printed.

The most common use of this tool is to process a set of input files into a single output file, or to take one input file
and extract a subset of observations into a smaller file. The examples section below outlines several common scenerios.

The tool now also allows the number of copies to be changed, but only to select subsets or reorder them. It is not yet
possible to merge copies or QCs from observations in different files into a single observation with more copies.

Observations can also be selected by a given range of quality control values or data values.

Observations can be restricted to a given bounding box, either in latitude and longitude (in the horizontal only), or if
the observations have 1D locations, then a single value for min_box and max_box can be specified to restrict the
observations to a subset of the space.

Faq
---

Can i merge files where the observation types are different?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Yes. The numbering in the table of contents at the top of each file is only local to that file. All processing of types
is done with the string name, not the numbers. Neither the set of obs types, nor the observation numbers need to match
across files.

I get an error about unknown observation types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Look at the ``&preprocess_nml`` namelist in the input.nml file in the directory where your tool was built. It must have
all the observation types you need to handle listed in the ``input_files`` item.

Can i list more files than necessary in my input file list?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Sure. It will take slightly longer to run, in that the tool must open the file and check the times and observation
types. But it is not an error to list files where no observations will be copied to the output file. It is a common task
to list a set of observation files and then set the first and last observation times, run the tool to select a shorter
time period, then change the first and last times and run again with the same list of files.

Building
--------

Most ``$DART/models/*/work`` directories will build the tool along with other executable programs. It is also possible
to build the tool in the ``$DART/observations/utilities`` directory. The ``preprocess`` program must be built and run
first, to define what set of observation types will be supported. See the
:doc:`../../../assimilation_code/programs/preprocess/preprocess` for more details on how to define the list and run it.
The combined list of all observation types which will be encountered over all input files must be in the preprocess
input list. The other important choice when building the tool is to include a compatible locations module. For the
low-order models, the ``oned`` module should be used; for real-world observations, the ``threed_sphere`` module should
be used.

Modules used
------------

::

   types_mod
   utilities_mod
   time_manager_mod
   obs_def_mod
   obs_sequence_mod

Files
-----

-  ``input.nml``
-  The input files specified in the ``filename_seq`` namelist variable, or inside the file named in
   ``filename_seq_list``.
-  The output file specified in the ``filename_out`` namelist variable.

References
----------

-  none
