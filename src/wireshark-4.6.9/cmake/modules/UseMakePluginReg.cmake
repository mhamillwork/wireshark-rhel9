#
function(register_plugin_files _outputfile _registertype)
	file(RELATIVE_PATH output "${CMAKE_BINARY_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/${_outputfile}")
	get_filename_component(_output_name "${_outputfile}" NAME)
	# plugin.c is the generated output. A CMakeLists that passes PLUGIN_FILES
	# here also passes that name, and Ninja then reports
	# "dependency cycle: plugin.c -> plugin.c".
	set(_sources)
	foreach(_src IN LISTS ARGN)
		get_filename_component(_src_name "${_src}" NAME)
		if(_src_name STREQUAL _output_name)
			continue()
		endif()
		list(APPEND _sources "${_src}")
	endforeach()
	add_custom_command(
	    OUTPUT
	      ${_outputfile}
	    COMMAND ${Python3_EXECUTABLE}
	      ${CMAKE_SOURCE_DIR}/tools/make-plugin-reg.py
	      ${CMAKE_CURRENT_SOURCE_DIR}
	      ${_registertype}
	      ${_sources}
	    COMMENT "Generating ${output}"
	    DEPENDS
	      ${_sources}
	      ${CMAKE_SOURCE_DIR}/tools/make-plugin-reg.py
	)
endfunction()
