# Definitive newline here. If the original script didn't have a terminal newline
# we'd otherwise append to another method call.
function(kcrash_validator_get_subs output dir)
    # NB: the same function has the same scope if called recursively.
    get_property(_subs DIRECTORY ${dir} PROPERTY SUBDIRECTORIES)
    foreach(sub ${_subs})
        kcrash_validator_get_subs(${output} ${sub})
    endforeach()
    set(${output} ${${output}} ${_subs} PARENT_SCOPE)
endfunction()

function(kcrash_validator_check_all_targets)
    set(linked_types "MODULE_LIBRARY;EXECUTABLE;SHARED_LIBRARY")

    kcrash_validator_get_subs(subs .)
    foreach(sub ${subs})
        get_property(targets DIRECTORY ${sub} PROPERTY BUILDSYSTEM_TARGETS)
        foreach(target ${targets})
            # Is a linked type (exectuable/lib)
            get_target_property(target_type ${target} TYPE)
            list(FIND linked_types ${target_type} linked_type_index)
            if(${linked_type_index} LESS 0)
                continue()
            endif()

            # Is part of all target
            get_target_property(target_exclude_all ${target} EXCLUDE_FROM_ALL)
            if(${target_exclude_all})
                continue()
            endif()

            # Wants KCrash
            # NB: cannot use IN_LIST condition because it is policy dependant
            #   and we do not want to change the policy configuration
            get_target_property(target_libs ${target} LINK_LIBRARIES)
            list(FIND target_libs "KF5::Crash" target_lib_index)
            if(${target_lib_index} LESS 0)
                continue()
            endif()

            # Not probably a test
            # (There is no actual way to tell a test from a regular target in
            # CMake before 3.10 [introduces TESTS property on DIRECTORY], so
            # we can only approximate this)
            list(FIND target_libs "Qt5::Test" target_testlib_index)
            if(${target_testlib_index} GREATER -1)
                continue()
            endif()

            message("target: ${target}")
            add_custom_target(objdump-kcrash-${target} ALL
                COMMAND echo "  $<TARGET_FILE:${target}>"
                COMMAND objdump -p $<TARGET_FILE:${target}> | grep NEEDED | grep libKF5Crash.so
                DEPENDS ${target}
                COMMENT "Checking if target linked KCrash: ${target}")
        endforeach()
    endforeach()
endfunction()

kcrash_validator_check_all_targets()
