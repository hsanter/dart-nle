! DART software - Copyright UCAR. This open source software is provided
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download

! Author HMS, 11/2023

!> Assign "covariance group" numbers to observations in an obs sequence
!> file based on their location/type. This corresponds to the third
!> value in the row of three values for a given obs in an obs sequence file.
!> Default value is -1. Currently only supports obs on a 1D domain.

program obs_grouping_tool

use        types_mod, only : r8, missing_r8, metadatalength, obstypelength,           &
                             MISSING_I
  
use     location_mod, only : location_type, get_location, set_location,               &
                             LocationName, is_location_in_region !%! , vert_is_height 
                             ! comment in select_gps_by_height() explains !%!

use      obs_def_mod, only : obs_def_type, get_obs_def_time, get_obs_def_type_of_obs, &
                             get_obs_def_location

use     obs_kind_mod, only : get_name_for_type_of_obs, get_index_for_type_of_obs

use time_manager_mod, only : time_type, operator(>), set_time

use    utilities_mod, only : get_unit, error_handler,                                 &
                             find_namelist_in_file, check_namelist_read,              &
                             E_ERR, E_MSG, nmlfileunit, do_nml_file, do_nml_term,     &
                             open_file, close_file, initialize_utilities

use obs_sequence_mod, only : obs_sequence_type, obs_type, write_obs_seq,              &
                             get_obs_def, set_obs_def,                                &
                             read_obs_seq_header, read_obs_seq, get_num_obs,          &
                             get_first_obs, get_next_obs,                             &
                             get_num_key_range, delete_obs_by_typelist,               &
                             get_obs_key, copy_partial_obs,                           &
                             read_obs_subset_def_count, read_obs_subset_defs,         &
                             obs_subset_def_type, set_obs, set_cov_group,             &
                             get_obs_subset_num, get_obs_subset_type,                 &
                             get_obs_subset_bounds, get_obs_subset_def_num

implicit none

character(len=*), parameter :: source = 'obs_grouping_tool.f90'
integer, parameter :: max_num_input_files = 1000

integer                                :: size_seq_in, num_copies_in, num_qc_in
integer                                :: iunit, io, i, current, next
integer                                :: num_subsets, subset_file_id, group_num
integer                                :: max_num_obs, seq_file_id, remaining_obs_count
character(len=metadatalength)          :: read_format, meta_data
logical                                :: pre_I_format
character(len=512)                     :: msgstring1, msgstring2, msgstring3
type(location_type)                    :: min_loc, max_loc
type(time_type)                        :: first_obs_time, last_obs_time
type(obs_sequence_type)                :: seq_in
type(obs_subset_def_type), allocatable :: subsets(:)
type(obs_type)                         :: obs, next_obs
type(obs_def_type)                     :: obs_def


! Namelist input with default values

character(len=256) :: filename_seq = ''
character(len=256) :: filename_subset_spec = ''
character(len=256) :: filename_out = 'obs_seq.grouped'

logical  :: completion_flag

namelist /obs_grouping_tool_nml/ &
         filename_seq, filename_subset_spec, filename_out


!!$ ------- Start program ---------

call initialize_utilities("obs_grouping_tool")

! Read the namelist entry
call find_namelist_in_file("input.nml", "obs_grouping_tool_nml", iunit)
read(iunit, nml = obs_grouping_tool_nml, iostat = io)
call check_namelist_read(iunit, io, "obs_grouping_tool_nml")

! get information about subsets
call read_obs_subset_def_count(num_subsets, filename_subset_spec, subset_file_id, &
     close_the_file = .true.)

allocate(subsets(num_subsets))

call read_obs_subset_defs(subsets, num_subsets, filename_subset_spec, subset_file_id, &
     close_the_file = .true.)

! get the obs sequence we're operating on
call read_obs_seq_header(filename_seq, num_copies_in, num_qc_in, &
   size_seq_in, max_num_obs, seq_file_id, read_format, pre_I_format, &
   close_the_file = .true.)
call read_obs_seq(filename_seq, 0, 0, 0, seq_in)

! completion_flag checks if there are any obs left in the sequence

completion_flag = get_first_obs(seq_in, obs)
if(.not. completion_flag) return
do while(completion_flag)
   
   call assign_obs_subset(obs, subsets, num_subsets, group_num)
   call set_cov_group(obs, group_num)
   call set_obs(seq_in, obs)
   call get_next_obs(seq_in, obs, obs, completion_flag)
   completion_flag = .not. completion_flag

end do
   
deallocate(subsets)

call write_obs_seq(seq_in, filename_out)

!!$ ------- End program ---------

contains

! compares a given obs against the subset specifications outlined in
! filename_subset_spec. leaves cov group unchanged if obs doesn't
! fit into any of the specified subsets.

! HMS 11/2023
! in practice, anything that obs_sequence_tool does to
! modify obs sequences should be usable as criteria
! for identifying obs subsets, but that's not currently
! implemented. this currently only supports subsetting by
! observation location in 1D and observation type, but extending it
! shouldn't be too onerous.
subroutine assign_obs_subset(obs, subsets, num_subsets, group)

  integer, intent(in)                   :: num_subsets
  integer, intent(out)                  :: group
  type(obs_type), intent(in)            :: obs
  type(obs_subset_def_type), intent(in) :: subsets(num_subsets)
  
  type(location_type)                   :: min_loc, max_loc
  type(location_type)                   :: location
  type(obs_def_type)                    :: obs_def
  integer                               :: i, obs_type_ind
  integer                               :: subset_type_ind
  character(len=obstypelength)          :: subset_type_string(1)
  character(len=obstypelength)          :: obs_type_string
  real(r8)                              :: min_1d, max_1d

  ! default cov group assignment is -1
  group = -1 

  call get_obs_def(obs, obs_def)
  location = get_obs_def_location(obs_def)

  ! types are generally specified by name
  ! (i.e. RAW_STATE_VARIABLE instead of 1)
  ! but for simple models where we want to observe
  ! the nth state variable with obs_type_ind = -1, -2, etc.
  ! we can also pass those in (still as strings) to the subset spec.
  obs_type_ind = get_obs_def_type_of_obs(obs_def)
  if(obs_type_ind > 0) then
     obs_type_string = get_name_for_type_of_obs(obs_type_ind)
  end if

  do i=1,num_subsets

     ! is obs in the right location for this subset?
     call get_obs_subset_bounds(subsets(i), min_1d, max_1d)
     min_loc = set_location(min_1d)
     max_loc = set_location(max_1d)
     if(.not. is_location_in_region(location, min_loc, max_loc)) cycle

     ! is obs the right type for this subset?
     call get_obs_subset_type(subsets(i), subset_type_string)
     if(obs_type_ind > 0) then
        if(subset_type_string(1) /= obs_type_string) cycle
     else
        read(subset_type_string(1), *) subset_type_ind
        if(subset_type_ind /= obs_type_ind) cycle
     end if

     ! if we've made it this far, this obs falls within the subset
     ! we're looking at.
     group = get_obs_subset_def_num(subsets(i))
     return

  end do

end subroutine assign_obs_subset


end program obs_grouping_tool
