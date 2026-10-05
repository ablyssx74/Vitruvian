find_package(PkgConfig REQUIRED)
pkg_check_modules(HD_SDL2 REQUIRED IMPORTED_TARGET sdl2)
pkg_check_modules(HD_CURL REQUIRED IMPORTED_TARGET libcurl)

Application(HDesktop
	SOURCES
	hdesktop.cpp

	LIBS be shared tracker game translation localestub opengl GL GLU
		PkgConfig::HD_SDL2 PkgConfig::HD_CURL

	RDEF hdesktop.rdef
)

# Selects the PipeWire volume path instead of BMediaRoster.
target_compile_definitions(HDesktop PRIVATE VITRUVIAN=1)
UsePrivateHeaders(HDesktop app interface tracker shared)

# SDL2 pulls in libpulse, whose libpulsecommon lives in a pulseaudio/ subdir
# that the linker does not search by itself (undefined libpulse references).
if(VITRUVIAN_CHROOT_BUILD AND VITRUVIAN_CHROOT_PATH AND VITRUVIAN_MULTIARCH_TRIPLE)
	target_link_options(HDesktop PRIVATE
		"-Wl,-rpath-link=${VITRUVIAN_CHROOT_PATH}/usr/lib/${VITRUVIAN_MULTIARCH_TRIPLE}/pulseaudio")
endif()
