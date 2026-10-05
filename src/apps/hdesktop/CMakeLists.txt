find_package(PkgConfig REQUIRED)
pkg_check_modules(HD_CURL REQUIRED IMPORTED_TARGET libcurl)

Application(HDesktop
	SOURCES
	hdesktop.cpp

	LIBS be shared tracker game translation localestub opengl GL GLU
		PkgConfig::HD_CURL

	RDEF hdesktop.rdef
)

# VITRUVIAN selects the native BWindow/BGLView layer (HDSdlCompat.h) instead of
# SDL2, and the PipeWire volume path instead of BMediaRoster.
target_compile_definitions(HDesktop PRIVATE VITRUVIAN=1)
UsePrivateHeaders(HDesktop app interface tracker shared)

