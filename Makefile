DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsNeonPulseBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsNeonPulse
AxsNeonPulse_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsNeonPulse_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsNeonPulse_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
AxsNeonPulse_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsNeonPulsePrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
