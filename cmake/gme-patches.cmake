# Local patch to GME 0.6.5 (2026-11-26). Keep the fetched or offline source
# checkout pristine. Compile corrected translation units alongside the
# upstream sources, preserving its copyright notice and license.
set(nsf_source "${game_music_emu_SOURCE_DIR}/gme/Nsf_Emu.cpp")
file(SHA256 "${nsf_source}" source_hash)
if(NOT source_hash STREQUAL "380857679b888e34a4ce17b2d47af0680de451fe7cbae51f9ee973be120a29a9")
  message(FATAL_ERROR "NSF allocation patch requires the audited GME 0.6.5 source")
endif()
file(READ "${nsf_source}" nsf_code)
string(REPLACE "apu_names.resize( count_total );"
  "/* Cirrus Retro, 2026-11-26: propagate allocation failure. */\n\tRETURN_ERR( apu_names.resize( count_total ) );"
  nsf_code "${nsf_code}")
# GME runs guest code in ~50 ms emulated quanta even for a small PCM request.
# Bound dispatches (including very short/custom play periods and bad opcodes).
# Each CPU dispatch already has a 32767 guest-clock limit in this pinned file.
string(REPLACE "while ( time() < duration )\n\t{"
  "unsigned dispatches = 0;\n\twhile ( time() < duration )\n\t{\n\t\t/* Cirrus Retro: bound untrusted CPU dispatch per audio quantum. */\n\t\tif ( ++dispatches > 8192 ) return \"NSF guest work limit\";"
  nsf_code "${nsf_code}")
set(patched_nsf "${CMAKE_CURRENT_BINARY_DIR}/patched-gme/Nsf_Emu.cpp")
file(CONFIGURE OUTPUT "${patched_nsf}" CONTENT "${nsf_code}" @ONLY)
# The SNES DSP wraps sample-directory addresses in its 64 KiB address space.
# A voice can change its sample number and directory page during playback.
set(dsp_source "${game_music_emu_SOURCE_DIR}/gme/Spc_Dsp.cpp")
file(SHA256 "${dsp_source}" dsp_hash)
if(NOT dsp_hash STREQUAL "f42be04184870f10be655be786c26f254c49dbdaa4604a6b75132abf934e5da2")
  message(FATAL_ERROR "SPC directory patch requires the audited GME 0.6.5 source")
endif()
file(READ "${dsp_source}" dsp_code)
string(REPLACE "uint8_t const* const dir = &ram [REG(dir) * 0x100];"
  "int const dir = REG(dir) * 0x100; /* Cirrus Retro: wrap DSP directory reads. */"
  dsp_code "${dsp_code}")
string(REPLACE "&dir [VREG(v_regs,srcn) * 4 + i * 2]"
  "&ram [(dir + VREG(v_regs,srcn) * 4 + i * 2) & 0xffff]" dsp_code "${dsp_code}")
set(patched_dsp "${CMAKE_CURRENT_BINARY_DIR}/patched-gme/Spc_Dsp.cpp")
file(CONFIGURE OUTPUT "${patched_dsp}" CONTENT "${dsp_code}" @ONLY)

foreach(target gme_shared gme_static)
  if(TARGET ${target})
    get_target_property(sources ${target} SOURCES)
    list(REMOVE_ITEM sources Nsf_Emu.cpp Spc_Dsp.cpp)
    set_property(TARGET ${target} PROPERTY SOURCES ${sources} "${patched_nsf}" "${patched_dsp}")
    target_include_directories(${target} PRIVATE "${game_music_emu_SOURCE_DIR}/gme")
    # Plain stereo is sufficient for the base APU. The effects constructor
    # allocates std::vectors in a library compiled with exceptions disabled.
    target_compile_definitions(${target} PRIVATE GME_DISABLE_STEREO_DEPTH=1)
  endif()
endforeach()
